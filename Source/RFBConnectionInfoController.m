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

#import "RFBConnectionInfoController.h"
#import "NSString_ByteString.h"
#import "RFBConnection.h"
#import "EncodingReader.h"
#import "ConnectionMetrics.h"
#import "IServerData.h"
#import "ThroughputGraphView.h"

//! Set this to 1 to include the sent data throughput series in the graph.
#define SHOW_SENT_SERIES 0

#define PIXEL_SERIES @"pixels"
#define RECEIVED_SERIES @"received"
#define SENT_SERIES @"sent"

static NSArray * s_pixelSuffixes = nil;

@interface RFBConnectionInfoController ()

- (void)updateTimer:(NSTimer *)theTimer;
- (void)startUpdateTimer;
- (void)stopUpdateTimer;

- (void)showWindow:(id)sender;
- (void)windowWillClose:(NSNotification *)aNotification;

- (void)updatePeakLabel;

@end

@implementation RFBConnectionInfoController

@synthesize controller = _controller;

- (id)initWithController:(RFBConnectionController *)theController
{
    if (self = [self initWithWindowNibName:@"OptionPanel"])
    {
        _controller = theController;
        _metrics = [theController.connection.metrics retain];
        _metrics.delegate = self;
        
        // Create the array of suffixes used for pixel throughput.
        if (!s_pixelSuffixes)
        {
            s_pixelSuffixes = [[NSArray alloc] initWithObjects:NSLocalizedString(@" pix/s", nil), NSLocalizedString(@"Kpix/s", nil), NSLocalizedString(@"Mpix/s", nil), NSLocalizedString(@"Gpix/s", nil), nil];
        }
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_metrics release];
    [super dealloc];
}

- (void)windowDidLoad
{
    // Set the info window's title.
    [[self window] setTitle:[NSString stringWithFormat:NSLocalizedString(@"%@ Info", nil), _controller.realDisplayName]];
    [(NSPanel *)[self window] setBecomesKeyOnlyIfNeeded:YES];
    
    // Set the background color of the graph.
    graph.backgroundColor = [[NSColor blackColor] colorWithAlphaComponent:0.45];
    
    // Creates the series for the throughput graph.
    GraphSeries * series;
    
#if SHOW_SENT_SERIES
    series = [graph addSeriesWithName:SENT_SERIES];
    series.color = [NSColor yellowColor];
#endif
    
    series = [graph addSeriesWithName:PIXEL_SERIES];
    series.color = [NSColor redColor];
    
    series = [graph addSeriesWithName:RECEIVED_SERIES];
    series.color = [NSColor greenColor];
    
    // Fill in the server info section.
    RFBConnection * connection = _controller.connection;
    FrameBuffer * frameBuffer = connection.frameBuffer;
    
    NSString * address = [NSString stringWithFormat:NSLocalizedString(@"ServerHostPort", nil), connection.host, [connection.server port]];
    [serverAddressField setStringValue:address];
    [protocolVersionField setStringValue:connection.protocol.serverVersion];
    [screenSizeField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"ScreenSize", nil), (int)[frameBuffer size].width, (int)[frameBuffer size].height]];
    [bitsPerPixelField setStringValue:[NSString stringWithFormat:@"%d", frameBuffer->pixelFormat.bitsPerPixel]];
    [byteOrderField setStringValue:[frameBuffer serverIsBigEndian] ? NSLocalizedString(@"big-endian", nil) : NSLocalizedString(@"little-endian", nil)];

    // Fill in the statistics section and start updating it periodically.
    [self updateStatistics];
    [self startUpdateTimer];
}

- (void)updateStatistics
{
    [bytesReceivedField setStringValue:[NSString stringFromByteQuantity:_metrics.bytesReceived suffix:nil]];
    [bytesSentField setStringValue:[NSString stringFromByteQuantity:_metrics.bytesSent suffix:nil]];
    [compressionRatioField setStringValue:[NSString stringWithFormat:@"%.2f", _metrics.compressionRatio]];
    [rectangleCountField setStringValue:[NSString stringWithFormat:@"%d", _metrics.totalRects]];
    [updateRequestCountField setStringValue:[NSString stringWithFormat:@"%d", _metrics.totalUpdateRequests]];
    [dataThroughputField setStringValue:[NSString stringFromByteQuantity:_metrics.throughput suffix:NSLocalizedString(@"/s", nil)]];
    [peakDataThroughputField setStringValue:[NSString stringFromByteQuantity:_metrics.peakThroughput suffix:NSLocalizedString(@"/s", nil)]];
    [pixelThroughputField setStringValue:[NSString stringFromQuantity:_metrics.pixelThroughput withUnits:s_pixelSuffixes suffix:nil]];
    [peakPixelThroughputField setStringValue:[NSString stringFromQuantity:_metrics.peakPixelThroughput withUnits:s_pixelSuffixes suffix:nil]];
}

- (void)updateTimer:(NSTimer *)theTimer
{
    [self updateStatistics];
}

- (void)startUpdateTimer
{
    if (!_updateTimer)
    {
        _updateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateTimer:) userInfo:nil repeats:YES] retain];
    }
}

- (void)stopUpdateTimer
{
    [_updateTimer invalidate];
    [_updateTimer release];
    _updateTimer = nil;
}

- (void)showWindow:(id)sender
{
    [super showWindow:sender];
    
    [self startUpdateTimer];    
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    [self stopUpdateTimer];
}

//! @brief Updates the graph peak value label to match current peak values.
- (void)updatePeakLabel
{
    // Get pixel throughput peak.
    GraphSeries * series = [graph seriesWithName:PIXEL_SERIES];
    BOOL pixelIsVisible = !series.isHidden;
    NSString * pixelPeakString = [NSString stringFromQuantity:series.peak withUnits:s_pixelSuffixes suffix:nil];
    
    // Get data throughput peak.
    series = [graph seriesWithName:RECEIVED_SERIES];
    BOOL dataIsVisible = !series.isHidden;
    NSString * bitsPeakString = [NSString stringFromByteQuantity:series.peak suffix:NSLocalizedString(@"/s", nil)];
    
    // Set the peak label value. Each peak value string has the foreground color of the graph series.
    NSMutableAttributedString * peakString;
    if (pixelIsVisible || dataIsVisible)
    {
        peakString = [[[NSMutableAttributedString alloc] initWithString:@"Peak: "] autorelease];
        NSDictionary * attrs;
        if (pixelIsVisible)
        {
            attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor redColor], NSForegroundColorAttributeName, nil, nil];
            [peakString appendAttributedString:[[[NSAttributedString alloc] initWithString:pixelPeakString attributes:attrs] autorelease]];
        }
        if (dataIsVisible)
        {
            if (pixelIsVisible)
            {
                [peakString appendAttributedString:[[[NSAttributedString alloc] initWithString:@", "] autorelease]];
            }
            
            attrs = [NSDictionary dictionaryWithObjectsAndKeys:[NSColor greenColor], NSForegroundColorAttributeName, nil, nil];
            [peakString appendAttributedString:[[[NSAttributedString alloc] initWithString:bitsPeakString attributes:attrs] autorelease]];
        }
    }
    else
    {
        peakString = [[[NSMutableAttributedString alloc] initWithString:@""] autorelease];
    }
    
    [graphPeakLabel setAttributedStringValue:peakString];
}

//! The metrics object sends this message to us when it has 
- (void)metricsDidUpdate:(ConnectionMetrics *)metrics
{
    // Update pixel series.
    GraphSeries * series = [graph seriesWithName:PIXEL_SERIES];
    [series insertValue:metrics.pixelThroughput redraw:NO];
    
    // Update bit throughput series.
    series = [graph seriesWithName:RECEIVED_SERIES];
    [series insertValue:metrics.throughput redraw:NO];
    
#if SHOW_SENT_SERIES
    // Update sent data series.
    series = [graph seriesWithName:SENT_SERIES];
    [series insertValue:metrics.sentThroughput redraw:NO];
#endif
    
    [graph setNeedsDisplay:YES];
    [self updatePeakLabel];
}

//! @brief One of the series checkboxes was clicked.
- (IBAction)seriesToggled:(id)sender
{
    GraphSeries * series = nil;
    if (sender == pixelSeriesCheckbox)
    {
        series = [graph seriesWithName:PIXEL_SERIES];
    }
    else if (sender == receivedSeriesCheckbox)
    {
        series = [graph seriesWithName:RECEIVED_SERIES];
    }
    
    if (series)
    {
        series.isHidden = !series.isHidden;
        [graph setNeedsDisplay:YES];
        [self updatePeakLabel];
    }
}

@end
