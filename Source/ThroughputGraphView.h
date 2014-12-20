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

enum
{
    //! @brief Do not use a peak group.
    kNoPeakGroup = -1
};

@class GraphSeries;

/*!
 * @brief Draws a graph of throughput.
 *
 * The graph works and looks very much like the network and disk operation graphs in the
 * Activity Monitor.app main window. 
 */
@interface ThroughputGraphView : NSView
{
    NSMutableDictionary * _series;  //!< Dictionary of series.
    NSColor * _backgroundColor; //!< Color used to fill the graph's background.
    float * _peakGroups;    //!< Peak values shared between series.
    unsigned _peakGroupCount;   //!< Number of peak groups.
}

@property(nonatomic, retain) NSColor * backgroundColor;
@property(readonly) float * peakGroups;

//! @brief
- (GraphSeries *)addSeriesWithName:(NSString *)seriesName;

//! @brief
- (GraphSeries *)seriesWithName:(NSString *)seriesName;

//! @brief
- (void)setPeakGroupCount:(unsigned)count;

@end

/*!
 * @brief One series of a graph.
 *
 * Normally you will not need to create instances of this class directly. Instead, use the
 * -addSeriesWithName: method of ThroughputGraphView to create a new series.
 */
@interface GraphSeries : NSObject
{
    ThroughputGraphView * _graph;   //!< The parent graph that draws this series.
    NSColor * _color;   //!< Line color for this series.
    unsigned _historyCount; //!< Number of entries in the history array.
    float * _history;   //!< Recent values.
    float _peak;    //!< Peak value out of history entries.
    unsigned _peakGroup;    //!< Either #kNoPeakGroup or a peak group number.
    BOOL _isHidden;    //!< Whether the series is visible or hidden.
}

@property(nonatomic, assign) ThroughputGraphView * graph;
@property(nonatomic, retain) NSColor * color;
@property(assign) float peak;
@property(assign) float * history;
@property(assign) unsigned historyCount;
@property(assign) unsigned peakGroup;
@property(assign) BOOL isHidden;

//! @brief Designated initializer.
- (id)initWithGraph:(ThroughputGraphView *)theGraph;

//! @brief Insert a new value into the history.
- (void)insertValue:(float)newValue redraw:(BOOL)doRedraw;

@end

