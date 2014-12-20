/*
 * Copyright (C) 2009 Chris Reed
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#import "ConnectionMetrics.h"
#import <CoreAudio/CoreAudio.h>

@interface ConnectionMetrics ()

- (void)dealloc;
- (void)updateMetrics:(NSTimer *)theTimer;

@end

@implementation ConnectionMetrics

@synthesize bytesReceived = _totalBytesReceived;
@synthesize bytesSent = _totalBytesSent;
@synthesize totalPixels = _totalPixels;
@synthesize totalRects = _totalRects;
@synthesize totalUpdateRequests = _totalRequests;
@synthesize bytesRepresented = _bytesRepresented;
@synthesize bytesPerPixel = _bytesPerPixel;
@synthesize throughput = _throughput;
@synthesize peakThroughput = _peakThroughput;
@synthesize pixelThroughput = _pixelThroughput;
@synthesize peakPixelThroughput = _peakPixelThroughput;
@synthesize sentThroughput = _sentThroughput;
@synthesize peakSentThroughput = _peakSentThroughput;
@synthesize delegate = _delegate;

- (id)init
{
    if (self = [super init])
    {
        _startTime = AudioConvertHostTimeToNanos(AudioGetCurrentHostTime());
        _lastTimestamp = _startTime;
        _timer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateMetrics:) userInfo:nil repeats:YES] retain];
    }
    
    return self;
}

- (void)dealloc
{
    [_timer release];
    [super dealloc];
}

- (void)connectionDidClose
{
    // Invalidate the timer so it will release its retain on us and allow us to be deallocated.
    [_timer invalidate];
}

- (void)addBytesReceived:(uint32_t)byteCount
{
    _totalBytesReceived += byteCount;
    _recentBytesReceived += byteCount;
}

- (void)addBytesSent:(uint32_t)byteCount
{
    _totalBytesSent += byteCount;
    _recentBytesSent += byteCount;
}

- (void)addRect:(NSRect)pixelRect
{
    uint32_t pixelCount = NSWidth(pixelRect) * NSHeight(pixelRect);
    _totalPixels += pixelCount;
    _recentPixels += pixelCount;
    _totalRects++;
    
    _bytesRepresented += pixelCount * _bytesPerPixel;
}

- (uint64_t)totalMicroseconds
{
    uint64_t nowTime = AudioConvertHostTimeToNanos(AudioGetCurrentHostTime());
    return nowTime - _startTime;
}

- (float)compressionRatio
{
    return (float)_bytesRepresented / (float)_totalBytesReceived;
}

- (void)updateMetrics:(NSTimer *)theTimer
{
    uint64_t nowTime = AudioConvertHostTimeToNanos(AudioGetCurrentHostTime());
    uint64_t microsecondsDelta = nowTime - _lastTimestamp;
    double secondsDelta = (double)microsecondsDelta / 1.0e9;

    // Compute byte throughput.
    _throughput = (double)_recentBytesReceived / secondsDelta;
    if (_throughput > _peakThroughput)
    {
        _peakThroughput = _throughput;
    }
    
    // Compute sent byte throughput.
    _sentThroughput = (double)_recentBytesSent / secondsDelta;
    if (_sentThroughput > _peakSentThroughput)
    {
        _peakSentThroughput = _sentThroughput;
    }
    
    // Compute pixel throughput.
    _pixelThroughput = (double)_recentPixels / secondsDelta;
    if (_pixelThroughput > _peakPixelThroughput)
    {
        _peakPixelThroughput = _pixelThroughput;
    }

    _lastTimestamp = nowTime;
    
    // Reset recent byte counts.
    _recentBytesReceived = 0;
    _recentBytesSent = 0;
    _recentPixels = 0;
    
    // Tell delegate we've updated.
    if (_delegate)
    {
        [(id)_delegate performSelectorOnMainThread:@selector(metricsDidUpdate:) withObject:self waitUntilDone:NO];
    }
}

- (void)addUpdateRequest
{
    _totalRequests++;
}

@end
