//
//  ZlibEncodingReader.m
//  Chicken of the VNC
//
//  Created by Helmut Maierhofer on Wed Nov 06 2002.
//  Copyright (c) 2002 Helmut Maierhofer. All rights reserved.
//

#import "ZlibEncodingReader.h"
#import "CARD32Reader.h"
#import "ByteBlockReader.h"
#import "RFBConnection.h"


@implementation ZlibEncodingReader

- (id)initTarget:(id)aTarget action:(SEL)anAction
{
    if (self = [super initTarget:aTarget action:anAction]) {
		int inflateResult;
	
		capacity = kZlibInitialOutputBufferSize;
		pixels = malloc(capacity);
        assert(pixels);
        
		numBytesReader = [[CARD32Reader alloc] initTarget:self action:@selector(setNumBytes:)];
		pixelReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setCompressedData:)];
		connection = [aTarget topTarget];
        
		inflateResult = inflateInit(&stream);
		if (inflateResult != Z_OK)
        {
            @throw [NSException exceptionWithName:kRFBConnectionException reason:[NSString stringWithFormat:@"Zlib encoding: inflateInit: %s", stream.msg] userInfo:nil];
		}
	}
    return self;
}

- (void)dealloc
{
	free(pixels);
	[numBytesReader release];
    [pixelReader release];
	inflateEnd(&stream);
    [super dealloc];
}

- (void)resetReader
{
    [target setReader:numBytesReader];
}

- (void)setNumBytes:(NSNumber*)numBytes
{
#ifdef COLLECT_STATS
	bytesTransferred = 4 + [numBytes unsignedIntValue];
#endif
	[pixelReader setBufferSize:[numBytes unsignedIntValue]];
	[target setReader:pixelReader];
}

- (void)setCompressedData:(NSData*)data
{
    // Set up the stream with the new input data.
    stream.next_in   = (unsigned char*)[data bytes];
    stream.avail_in  = [data length];
    stream.next_out  = pixels;
    stream.avail_out = capacity;
    stream.data_type = Z_BINARY;
    
    // Decompress input data until it is all used up. If the inflate function returns with
    // input data remaining unprocessed, we have to grow our output buffer and continue.
    uint32_t startTotalOutputLength = stream.total_out;
    while (stream.avail_in)
    {
        int inflateResult = inflate(&stream, Z_SYNC_FLUSH);
        if (inflateResult == Z_NEED_DICT)
        {
            @throw [NSException exceptionWithName:kRFBConnectionException reason:NSLocalizedString(@"Zlib inflate needs a dictionary.", nil) userInfo:nil];
        }
        else if (inflateResult < 0)
        {
            @throw [NSException exceptionWithName:kRFBConnectionException reason:[NSString stringWithFormat:NSLocalizedString(@"Zlib inflate error: %s", nil), stream.msg] userInfo:nil];
        }
        
        // If there is still input data but no more room in the output buffer, we have to expand it.
        if (inflateResult == Z_OK && stream.avail_in && !stream.avail_out)
        {
            uint32_t offset = stream.next_out - pixels;
            capacity += kZlibOutputBufferChunkSize;
            pixels = realloc(pixels, capacity);
            assert(pixels);
            stream.next_out = pixels + offset;
            stream.avail_out = capacity - offset;
        }
    }
    
    uint32_t decompressedLength = stream.total_out - startTotalOutputLength;
	[self setUncompressedData:pixels length:decompressedLength];
}

- (void)setUncompressedData:(unsigned char*)data length:(int)length
{
	[frameBuffer putRect:frame fromData:pixels];
    [target performSelector:action withObject:self];
}

@end
