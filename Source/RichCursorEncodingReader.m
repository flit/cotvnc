//
//  RichCursorEncodingReader.m
//  Chicken of the VNC
//
//  Created by Chris Reed on 2/14/09.
//  Copyright 2009 Immo Software. All rights reserved.
//

#import "RichCursorEncodingReader.h"
#import "ByteBlockReader.h"
#import "TrueColorFrameBuffer.h"
#import "RFBConnection.h"

//! \brief I-beam cursor data.
//!
//! This cursor data matches the I-beam cursor used in many Mac applications such as BBEdit
//! and Firefox. The data is in 32-bit ARGB pixel format, with a size of 16x16 pixels.
const uint32_t kIBeamCursorData[] = {
	0x00000000, 0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00ffffff, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00000000, 0x00ffffff, 0x00000000, 0x00000000, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
	0x00000000, 0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000, 0x00000000, 0x00ffffff, 0x00ffffff, 
	0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
	};

@implementation RichCursorEncodingReader

- (id)initTarget:(id)aTarget action:(SEL)anAction
{
    if (self = [super initTarget:aTarget action:anAction])
	{
		_pixelReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setCursorPixels:)];
		_maskReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setCursorMask:)];
	}
	
    return self;
}

- (void)dealloc
{
    [_pixelReader release];
    [_maskReader release];
    [super dealloc];
}

- (void)setConnection:(id)connection
{
	_connection = connection;
}

- (void)resetReader
{
	// Cursor pixel data size in bytes.
    unsigned s = [frameBuffer bytesPerPixel] * frame.size.width * frame.size.height;
	
	// Cursor mask data size in bytes. The mask is one bit per pixel, round the width up
	// to the next byte.
	unsigned m = ((unsigned)frame.size.width + 7) / 8 * (unsigned)frame.size.height;

#ifdef COLLECT_STATS
    bytesTransferred = s + m;
#endif

	// Set reader sizes.
    [_pixelReader setBufferSize:s];
	[_maskReader setBufferSize:m];

	// We first read the cursor pixel data in the client pixel format.
    [target setReader:_pixelReader];
}

//! The cursor pixel data is in the client pixel format.
- (void)setCursorPixels:(NSData *)pixels
{
	_pixels = [pixels retain];
	
	// After reading the pixel data we read the mask data.
	[target setReader:_maskReader];
}

//! The cursor mask is a 1 bit-per-pixel mask with each row rounded up to the next byte.
- (void)setCursorMask:(NSData *)mask
{
//	NSLog(@"setting cursor: size={%g, %g}, hotspot={%g, %g}", frame.size.width, frame.size.height, frame.origin.x, frame.origin.y);
	
	// Create the new cursor instance. The origin of the update rect is the cursor's hotspot.
	// The connection will take ownership of this cursor object.
	[_connection setRemoteCursor:[self createCursorWithPixels:_pixels mask:mask]];
	
	// We no longer need the pixel data.
	[_pixels release];
	
	// We're done processing, so perform our action.
    [target performSelector:action withObject:self];
}

- (NSCursor *)createCursorWithPixels:(NSData *)pixelData mask:(NSData *)maskData
{
	unsigned i;
	
	// Treat a request for an empty cursor specially. We can't just use the normal code below
	// because CGImages don't like to be empty.
	if (frame.size.width == 0 && frame.size.height == 0)
	{
		return nil;
	}
	
	// Create a new framebuffer to render the cursor pixel data into. We can't necessarily
	// create a CGImage directly from the pixel data because it may not have the same bits
	// per component for each component.
	rfbPixelFormat * format = [frameBuffer getServerPixelFormat];
	TrueColorFrameBuffer * cursorFrameBuffer = [[TrueColorFrameBuffer alloc] initWithSize:frame.size andFormat:format];
	NSRect putRect = NSMakeRect(0, 0, frame.size.width, frame.size.height);
	[cursorFrameBuffer putRect:putRect fromData:(unsigned char*)[pixelData bytes]];

	// Check if this is a specially handled cursor.
	unsigned pixelDataLength = [cursorFrameBuffer pixelDataSize];
	if ((pixelDataLength == sizeof(kIBeamCursorData)) && (memcmp(kIBeamCursorData, [cursorFrameBuffer pixelData], pixelDataLength) == 0))
	{
		// This is the I-beam cursor we handle specially. It shows up invisibly because the
		// cursor was intended to be used in XOR mode, but that doesn't pass through RFB.
		// So, we just set the cursor to the local I-beam cursor.
		[cursorFrameBuffer release];
		return [NSCursor IBeamCursor];
	}
	
	CGBitmapInfo bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault;
	CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
	
	// Create the full color cursor image.
	NSData * translatedPixelsData = [NSData dataWithBytes:[cursorFrameBuffer pixelData] length:[cursorFrameBuffer pixelDataSize]];
	CGDataProviderRef pixelsProvider = CGDataProviderCreateWithCFData((CFDataRef)translatedPixelsData);
	CGImageRef image = CGImageCreate((size_t)frame.size.width, (size_t)frame.size.height, 8, 32, (int)frame.size.width * 4, rgbColorSpace, bitmapInfo, pixelsProvider, NULL, false, kCGRenderingIntentDefault);
	CFRelease(rgbColorSpace);
	CFRelease(pixelsProvider);
	
	// Invert the mask data as the "see-through" value is the opposite of what CG wants, which is
	// a value of 1 for opaque and 0 for transparent. We also use this loop to see if the cursor
	// is completely invisible.
	unsigned maskLength = [maskData length];
	uint8_t * maskBytes = (uint8_t *)malloc(maskLength);
	[maskData getBytes:maskBytes];

	uint8_t * maskByte = maskBytes;
	bool isInvisible = true;
	for (i=0; i < maskLength; ++i, ++maskByte)
	{
		*maskByte = ~(*maskByte);
		isInvisible = isInvisible && (*maskByte == 0xff);
	}
	
	// If the cursor is invisible, then we switch to the standard cotvnc cursor.
	if (isInvisible)
	{
		free(maskBytes);
		CFRelease(image);
		[cursorFrameBuffer release];
		return nil;
	}
	
	maskData = [NSData dataWithBytesNoCopy:maskBytes length:maskLength freeWhenDone:YES];
	
	// Create the 1 bpp mask image.
	CGDataProviderRef maskProvider = CGDataProviderCreateWithCFData((CFDataRef)maskData);
	CGImageRef mask = CGImageMaskCreate((size_t)frame.size.width, (size_t)frame.size.height, 1, 1, ((size_t)frame.size.width + 7) / 8, maskProvider, NULL, false);
	CFRelease(maskProvider);
	[cursorFrameBuffer release];
	
	// Combine the cursor pixel and mask image into one.
	CGImageRef maskedCursorImage = CGImageCreateWithMask(image, mask);
	CFRelease(image);
	CFRelease(mask);
	
	// Create an NSImage from our combined CGImage.
	NSBitmapImageRep * rep = [[[NSBitmapImageRep alloc] initWithCGImage:maskedCursorImage] autorelease];
	NSImage * cursorImage = [[[NSImage alloc] initWithSize:frame.size] autorelease];
	[cursorImage addRepresentation:rep];
	
	// And finally, create the cursor object from our NSImage. The cursor's hotspot comes
	// from the origin of the encoding frame.
	NSCursor * cursor = [[[NSCursor alloc] initWithImage:cursorImage hotSpot:frame.origin] autorelease];
	[cursor setOnMouseEntered:YES];
	[cursor setOnMouseExited:YES];
	CFRelease(maskedCursorImage);
	
	return cursor;
}

@end
