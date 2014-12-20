//
//  RichCursorEncodingReader.h
//  Chicken of the VNC
//
//  Created by Chris Reed on 2/14/09.
//  Copyright 2009 Immo Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "EncodingReader.h"

/*!
 * @brief Reads the rich cursor RFB encoding.
 */
@interface RichCursorEncodingReader : EncodingReader
{
    id _pixelReader;
    id _maskReader;
	id _connection;
	NSData * _pixels;
}

- (void)setConnection:(id)connection;

- (void)setCursorPixels:(NSData*)pixels;
- (void)setCursorMask:(NSData *)mask;

- (NSCursor *)createCursorWithPixels:(NSData *)pixelData mask:(NSData *)maskData;

@end
