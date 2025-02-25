/*
 *  Copyright (c) 2014-present, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "CKTextComponentLayer.h"

#import "CKInternalHelpers.h"
#import "CKTextKitAttributes.h"
#import "CKTextKitRenderer.h"
#import "CKTextKitRendererCache.h"
#import "CKAssert.h"

#import "CKTextComponentLayerHighlighter.h"

static CK::TextKit::Renderer::Cache *rasterContentsCache()
{
  // 6MB raster contents cache that evicts 20% of the least recently used bitmaps it contains when it hits 6MB
  static CK::TextKit::Renderer::Cache *__rasterContentsCache (new CK::TextKit::Renderer::Cache("CKTextComponentRasterContentsCache", 6 * 1024 * 1025, 0.2));
  return __rasterContentsCache;
}

@implementation CKTextComponentLayer
{
  CKTextComponentLayerHighlighter *_highlighter;
  CGRect _innerBounds;
}

+ (id)defaultValueForKey:(NSString *)key
{
  if ([key isEqualToString:@"contentsScale"]) {
    return @(CKScreenScale());
  } else if ([key isEqualToString:@"backgroundColor"]) {
    return (id)[UIColor whiteColor].CGColor;
  } else if ([key isEqualToString:@"opaque"]) {
    return (id)kCFBooleanTrue;
  } else if ([key isEqualToString:@"userInteractionEnabled"]) {
    return (id)kCFBooleanTrue;
  } else if ([key isEqualToString:@"needsDisplayOnBoundsChange"]) {
    return (id)kCFBooleanTrue;
  }
  return [super defaultValueForKey:key];
}

- (void)setNeedsDisplayOnBoundsChange:(BOOL)needsDisplayOnBoundsChange
{
  // Don't allow this property to be disabled.  Unfortunately, UIView will turn this off when setting the
  // backgroundColor, for reasons that cannot be understood.  Even worse, it doesn't ever set it back, so it will
  // subsequently stay off.  Just make sure that it never gets overridden, because the text will not be drawn in the
  // correct way (or even at all) if this is set to NO.
  if (needsDisplayOnBoundsChange) {
    [super setNeedsDisplayOnBoundsChange:needsDisplayOnBoundsChange];
  }
}

- (void)setRenderer:(CKTextKitRenderer *)renderer
{
  CKAssertMainThread();
  if (renderer != _renderer) {
    if (renderer && _renderer) {
      if (renderer.attributes == _renderer.attributes
          && CGSizeEqualToSize(self.bounds.size, _innerBounds.size)) {
        // If the renderers are identical there's no point in re-rendering
        _renderer = renderer;
        return;
      } else {
        // If the renderers are truly not equal we need to nil out the contents so we don't display old text
        // from a previous renderer.
        self.contents = nil;
      }
    }

    _innerBounds = self.bounds;
    _renderer = renderer;
    [self setNeedsDisplay];
  }
}

- (NSObject *)drawParameters
{
  return _renderer;
}

- (id)willDisplayAsynchronouslyWithDrawParameters:(id<NSObject>)drawParameters
{
  UIUserInterfaceStyle u = UIUserInterfaceStyleLight;
  UIView *v = (UIView *)self.delegate;
  if ([v isKindOfClass:UIView.class]) {
    u = v.traitCollection.userInterfaceStyle;
  }

  return rasterContentsCache()->objectForKey({u, _renderer.attributes, self.bounds.size});
}

- (void)didDisplayAsynchronously:(id)newContents withDrawParameters:(id<NSObject>)drawParameters
{
  if (newContents) {
    UIUserInterfaceStyle u = UIUserInterfaceStyleLight;
    UIView *v = (UIView *)self.delegate;
    if ([v isKindOfClass:UIView.class]) {
      u = v.traitCollection.userInterfaceStyle;
    }

    CGImageRef imageRef = (__bridge CGImageRef)newContents;
    NSUInteger bytes = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
    rasterContentsCache()->cacheObject({u, _renderer.attributes, self.bounds.size}, newContents, bytes);
  }
}

+ (void)drawInContext:(CGContextRef)context parameters:(CKTextKitRenderer *)renderer
{
  CGRect boundsRect = CGContextGetClipBoundingBox(context);
  [renderer drawInContext:context bounds:boundsRect];
}

- (void)drawInContext:(CGContextRef)ctx
{
  // When we're drawing synchronously we need to manually fill the bg color because CKAsyncLayer doesn't.
  if (self.opaque && self.backgroundColor != NULL) {
    CGRect boundsRect = CGContextGetClipBoundingBox(ctx);
    CGContextSetFillColorWithColor(ctx, self.backgroundColor);
    CGContextFillRect(ctx, boundsRect);
  }
  [super drawInContext:ctx];
}

#pragma mark - Highlighting

- (CKTextComponentLayerHighlighter *)highlighter
{
  CKAssertMainThread();
  if (!_highlighter) {
    _highlighter = [[CKTextComponentLayerHighlighter alloc] initWithTextComponentLayer:self];
  }
  return _highlighter;
}

- (void)layoutSublayers
{
  // Do not generate a highlighter if one doesn't already exist
  if (_highlighter) {
    [_highlighter layoutHighlight];
  }
  [super layoutSublayers];
}

@end
