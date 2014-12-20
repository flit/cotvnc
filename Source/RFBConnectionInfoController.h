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
#import "ConnectionMetrics.h"

@class RFBConnectionController;
@class ConnectionMetrics;
@class ThroughputGraphView;

/*!
 * @brief Window controller for the connection info window.
 *
 * This controller shows a number of statistics about the connection plus some basic
 * protocol information. It automatically updates the statistics as long as the window
 * is visible. It also manages an animated graph of received data and pixel throughput.
 */
@interface RFBConnectionInfoController : NSWindowController <MetricsDelegate>
{
    //! \name OptionPanel.nib outlets
    //@{
    IBOutlet id serverAddressField;
    IBOutlet id protocolVersionField;
    IBOutlet id screenSizeField;
    IBOutlet id bitsPerPixelField;
    IBOutlet id byteOrderField;
    IBOutlet id bytesReceivedField;
    IBOutlet id bytesSentField;
    IBOutlet id compressionRatioField;
    IBOutlet id rectangleCountField;
    IBOutlet id updateRequestCountField;
    IBOutlet id dataThroughputField;
    IBOutlet id peakDataThroughputField;
    IBOutlet id pixelThroughputField;
    IBOutlet id peakPixelThroughputField;
    IBOutlet ThroughputGraphView * graph;
    IBOutlet id graphPeakLabel;
    IBOutlet id pixelSeriesCheckbox;
    IBOutlet id receivedSeriesCheckbox;
    //@}

    RFBConnectionController * _controller;  //!< Parent controller instance.
    NSTimer * _updateTimer;   //!< Timer used to automatically update the connection info window.
    ConnectionMetrics * _metrics;   //!< The connection's metrics object.
}

//! @brief The connection controller that owns us.
@property(nonatomic, assign) RFBConnectionController * controller;

//! @brief Designated initializer.
- (id)initWithController:(RFBConnectionController *)theController;

//! @brief Updates the statistics section of the info window.
- (void)updateStatistics;

//! @brief One of the series checkboxes was clicked.
- (IBAction)seriesToggled:(id)sender;

@end
