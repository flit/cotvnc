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

#import <Cocoa/Cocoa.h>

@class ConnectionMetrics;

/*!
 * @brief Protocol for delegates of ConnectionMetrics.
 */
@protocol MetricsDelegate

//! @brief Informs the delegate that metrics values have been modified.
- (void)metricsDidUpdate:(ConnectionMetrics *)metrics;

@end

/*!
 * @brief Computes metrics for an RFB connection.
 */
@interface ConnectionMetrics : NSObject
{
    uint64_t _totalBytesReceived;   //!< Total number of bytes received from server.
    uint64_t _totalBytesSent;       //!< Total number of bytes sent to the server.
    uint64_t _startTime;    //!< Time in microseconds when the connection was opened.
    uint64_t _totalPixels;  //!< Total number of uncompressed pixels transferred.
    uint32_t _totalRects;   //!< Number of rectangles transferred.
    uint32_t _totalRequests; //!< Number of update requests.
    uint64_t _bytesRepresented; //!< Number of bytes of uncompressed pixel data. 
    double _throughput;
    double _peakThroughput;
    unsigned _bytesPerPixel;
    NSTimer * _timer;   //!< Timer to update metrics on a regular basis.
    uint32_t _recentBytesReceived;
    uint32_t _recentBytesSent;
    uint64_t _lastTimestamp;
    uint32_t _recentPixels;
    double _pixelThroughput;    //!< Pixels per second.
    double _peakPixelThroughput;    //!< Maximum pixels per second.
    double _sentThroughput;     //!< Bytes per second of data sent to the server.
    double _peakSentThroughput; //!< Maximum bytes per second.
    id<MetricsDelegate> _delegate;
}

@property(readonly) uint64_t bytesReceived;
@property(readonly) uint64_t bytesSent;
@property(readonly) uint64_t totalMicroseconds;
@property(readonly) uint64_t totalPixels;
@property(readonly) uint32_t totalRects;
@property(readonly) uint32_t totalUpdateRequests;
@property(readonly) uint64_t bytesRepresented;
@property(readonly) float compressionRatio;
@property(assign) unsigned bytesPerPixel;
@property(readonly) double throughput;
@property(readonly) double peakThroughput;
@property(readonly) double pixelThroughput;
@property(readonly) double peakPixelThroughput;
@property(readonly) double sentThroughput;
@property(readonly) double peakSentThroughput;

@property(nonatomic, assign) id<MetricsDelegate> delegate;

//! @brief Designated initializer.
- (id)init;

//! @brief Send this message when the connection has closed.
- (void)connectionDidClose;

- (void)addBytesReceived:(uint32_t)byteCount;
- (void)addBytesSent:(uint32_t)byteCount;
- (void)addRect:(NSRect)pixelRect;
- (void)addUpdateRequest;

@end

