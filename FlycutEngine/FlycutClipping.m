//
//  FlycutClipping.m
//  Flycut
//
//  Flycut by Gennadiy Potapov and contributors. Based on Jumpcut by Steve Cook.
//  Copyright 2011 General Arcade. All rights reserved.
//
//  This code is open-source software subject to the MIT License; see the homepage
//  at <https://github.com/TermiT/Flycut> for details.
//


#import "FlycutClipping.h"
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

@interface FlycutClipping ()
-(NSString *) imagePlaceholderString;
@end

@implementation FlycutClipping

-(id) init
{
    [self initWithContents:@""
                  withType:@""
         withDisplayLength:40
      withAppLocalizedName:@""
          withAppBundleURL:nil
             withTimestamp:0];
    return self;
}

-(id) initWithContents:(NSString *)contents withType:(NSString *)type withDisplayLength:(int)displayLength withAppLocalizedName:(NSString *)localizedName withAppBundleURL:(NSString*)bundleURL withTimestamp:(NSInteger)timestamp
{
    [super init];
    clipContents = [[[NSString alloc] init] retain];
    clipDisplayString = [[[NSString alloc] init] retain];
    clipType = [[[NSString alloc] init] retain];
    clipImageData = nil;

    [self setContents:contents setDisplayLength:displayLength];
    [self setType:type];
    [self setAppLocalizedName:localizedName];
    [self setAppBundleURL:bundleURL];
    [self setTimestamp:timestamp];
    [self setHasName:false];

    return self;
}

-(id) initWithImageData:(NSData *)imageData withType:(NSString *)type withDisplayLength:(int)displayLength withAppLocalizedName:(NSString *)localizedName withAppBundleURL:(NSString *)bundleURL withTimestamp:(NSInteger)timestamp
{
    [super init];
    clipContents = [[[NSString alloc] init] retain];
    clipDisplayString = [[[NSString alloc] init] retain];
    clipType = [[[NSString alloc] init] retain];
    clipImageData = nil;

    [self setType:type];
    [self setImageData:imageData];
    if ( displayLength > 0 ) {
        clipDisplayLength = displayLength;
    }
    [self resetDisplayString]; // build placeholder string from image metadata
    // Mirror the placeholder text into clipContents so search and the legacy "Contents" field have something
    // to match against.
    [self setContents:clipDisplayString];
    [self setAppLocalizedName:localizedName];
    [self setAppBundleURL:bundleURL];
    [self setTimestamp:timestamp];
    [self setHasName:false];

    return self;
}

/* - (id)initWithCoder:(NSCoder *)coder
{
    NSString * newContents;
    int newDisplayLength;
    NSString *newType;
    BOOL newHasName;
    if ( self = [super init]) {
        newContents = [NSString stringWithString:[coder decodeObject]];
        [coder decodeValueOfObjCType:@encode(int) at:&newDisplayLength];
        newType = [NSString stringWithString:[coder decodeObject]];
        [coder decodeValueOfObjCType:@encode(BOOL) at:&newHasName];
        [self 	     setContents:newContents
                setDisplayLength:newDisplayLength];
        [self setType:newType];
        [self setHasName:newHasName];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    int codeDisplayLength = [self displayLength];
    BOOL codeHasName = [self hasName];
    [coder encodeObject:[self contents]];
    [coder encodeValueOfObjCType:@encode(int) at:&codeDisplayLength];
    [coder encodeObject:[self type]];
    [coder encodeValueOfObjCType:@encode(BOOL) at:&codeHasName];
} */

-(void) setContents:(NSString *)newContents setDisplayLength:(int)newDisplayLength
{
    id old = clipContents;
    [newContents retain];
    clipContents = newContents;
    [old release];
    if ( newDisplayLength  > 0 ) {
        clipDisplayLength = newDisplayLength;
    }
   [self resetDisplayString];
}

-(void) setContents:(NSString *)newContents
{
    id old = clipContents;
    [newContents retain];
    clipContents = newContents;
    [old release];
    [self resetDisplayString];
}

-(void) setType:(NSString *)newType
{
    id old = clipType;
    [newType retain];
    clipType = newType;
    [old release];
}

-(void) setDisplayLength:(int)newDisplayLength
{
    if ( newDisplayLength > 0 && clipDisplayLength != newDisplayLength ) {
        clipDisplayLength = newDisplayLength;
        [self resetDisplayString];
    }
}

-(void) setAppLocalizedName:(NSString *)new
{
    id old = appLocalizedName;
    [new retain];
    appLocalizedName = new;
    [old release];
}

-(void) setAppBundleURL:(NSString *)new
{
    id old = appBundleURL;
    [new retain];
    appBundleURL = new;
    [old release];
}

-(void) setTimestamp:(NSInteger)newTimestamp
{
    clipTimestamp = newTimestamp;
}

-(void) setHasName:(BOOL)newHasName
{
        clipHasName = newHasName;
}

-(void) setImageData:(NSData *)newImageData
{
    id old = clipImageData;
    [newImageData retain];
    clipImageData = newImageData;
    [old release];
}

-(void) resetDisplayString
{
    NSString *newDisplayString, *firstLineOfClipping, *trimmedString;
	NSUInteger start, lineEnd, contentsEnd;
	NSRange startRange = NSMakeRange(0,0);
	NSRange contentsRange;
	// We're resetting the display string, so release the old one.
    [clipDisplayString release];

    // Image clippings get a synthesized "[Image WxH KB]" placeholder, which both flows through
    // the existing menu/bezel rendering and makes them grep-able in the search box.
    if ( clipImageData != nil ) {
        NSString *placeholder = [self imagePlaceholderString];
        [placeholder retain];
        clipDisplayString = placeholder;
        return;
    }

	// We want to restrict the display string to the clipping contents through the first line break.
    trimmedString = [clipContents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [trimmedString getLineStart:&start end:&lineEnd contentsEnd:&contentsEnd forRange:startRange];
	contentsRange = NSMakeRange(0, contentsEnd);
	firstLineOfClipping = [trimmedString substringWithRange:contentsRange];
    if ( [firstLineOfClipping length] > clipDisplayLength ) {
        newDisplayString = [[NSString stringWithString:[firstLineOfClipping substringToIndex:clipDisplayLength]] stringByAppendingString:@"…"];
    } else {
        newDisplayString = [NSString stringWithString:firstLineOfClipping];
    }
    [newDisplayString retain];
    clipDisplayString = newDisplayString;
}

-(NSString *) imagePlaceholderString
{
    NSUInteger byteCount = [clipImageData length];
    NSString *sizeLabel;
    if ( byteCount < 1024 ) sizeLabel = [NSString stringWithFormat:@"%lu B", (unsigned long)byteCount];
    else if ( byteCount < 1024 * 1024 ) sizeLabel = [NSString stringWithFormat:@"%.0f KB", byteCount / 1024.0];
    else sizeLabel = [NSString stringWithFormat:@"%.1f MB", byteCount / (1024.0 * 1024.0)];

    NSString *typeLabel = @"Image";
    if ( [clipType isEqualToString:@"public.png"] || [clipType isEqualToString:@"NSPasteboardTypePNG"] ) typeLabel = @"PNG";
    else if ( [clipType isEqualToString:@"public.tiff"] || [clipType isEqualToString:@"NSPasteboardTypeTIFF"] ) typeLabel = @"TIFF";
    else if ( [clipType isEqualToString:@"public.jpeg"] ) typeLabel = @"JPEG";

    CGSize pixelSize = CGSizeZero;
#if TARGET_OS_OSX
    NSImage *probe = [[NSImage alloc] initWithData:clipImageData];
    if ( probe ) {
        pixelSize = probe.size;
        [probe release];
    }
#else
    UIImage *probe = [[UIImage alloc] initWithData:clipImageData];
    if ( probe ) {
        pixelSize = probe.size;
        [probe release];
    }
#endif

    if ( pixelSize.width > 0 && pixelSize.height > 0 )
        return [NSString stringWithFormat:@"[%@ %.0fx%.0f, %@]", typeLabel, pixelSize.width, pixelSize.height, sizeLabel];
    return [NSString stringWithFormat:@"[%@ image, %@]", typeLabel, sizeLabel];
}

-(NSString *) description
{
    NSString *description = [[super description] stringByAppendingString:@": "];
    description = [description stringByAppendingString:[self displayString]];   
    return description;
}

-(FlycutClipping *) clipping
{
    return self;
}

-(NSString *) contents
{
//    NSString *returnClipContents;
//    returnClipContents = [NSString stringWithString:clipContents];
//    return returnClipContents;
    return clipContents;
}

-(NSString *) appLocalizedName
{
    return appLocalizedName;
}

-(NSString *) appBundleURL
{
    return appBundleURL;
}

-(NSInteger) timestamp
{
    return clipTimestamp;
}

-(int) displayLength
{
    return clipDisplayLength;
}

-(NSString *) type
{
    return clipType;
}

-(NSString *) displayString
{
    // QUESTION
    // Why doesn't the below work?
    // NSString *returnClipDisplayString;
    // returnClipDisplayString = [NSString stringWithString:clipDisplayString];
    // return returnClipDisplayString;
    return clipDisplayString;
}

-(BOOL) hasName
{
    return clipHasName;
}

-(NSData *) imageData
{
    return clipImageData;
}

-(BOOL) isImage
{
    return clipImageData != nil;
}

- (BOOL)isEqual:(id)other {
    if (other == self)
        return YES;
    if (!other || ![other isKindOfClass:[self class]])
        return NO;
    FlycutClipping * otherClip = (FlycutClipping *)other;
    // Two image clippings match when their raw bytes match. Mixed image/text never matches.
    if ( clipImageData != nil || otherClip->clipImageData != nil ) {
        if ( clipImageData == nil || otherClip->clipImageData == nil ) return NO;
        return [clipImageData isEqualToData:otherClip->clipImageData];
    }
    return (/*[self.type isEqualToString:otherClip.type] &&*/ // Type is under-utilized a this time and will mismatch on cross-device (macOS <-> iOS) usage.  This should be revisited once we have support for more than just raw text clippings.
            [self.contents isEqualToString:otherClip.contents]);
}



-(void) dealloc
{
    [clipContents release];
    [clipType release];
    [appLocalizedName release];
    [appBundleURL release];
    [clipImageData release];
    clipDisplayLength = 0;
    [clipDisplayString release];
    clipHasName = 0;
    [super dealloc];
}
@end
