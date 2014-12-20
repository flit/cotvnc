//
//  ZlibEncodingReader.h
//  Chicken of the VNC
//
//  Created by Helmut Maierhofer on Wed Nov 06 2002.
//  Copyright (c) 2002 Helmut Maierhofer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <zlib.h>
#import "EncodingReader.h"

enum
{
    //! Starting size for the output buffer.
    kZlibInitialOutputBufferSize = 256*1024,
    
    //! The size used to expand the output buffer each time it is too small.
    kZlibOutputBufferChunkSize = 64*1024
};

@interface ZlibEncodingReader : EncodingReader
{
	unsigned char*	pixels;
	unsigned int	capacity;
	id				numBytesReader;
	id				pixelReader;
	id				connection;
	z_stream		stream;
}

- (void)setUncompressedData:(unsigned char*)data length:(int)length;

@end
