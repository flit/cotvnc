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

#import "ThroughputGraphView.h"

//! Number to divide graph width by to get the default history entry count.
#define DEFAULT_HISTORY_COUNT_DIVISOR (3.0)

@implementation GraphSeries

@synthesize graph = _graph;
@synthesize color = _color;
@synthesize peak = _peak;
@synthesize history = _history;
@synthesize peakGroup = _peakGroup;
@synthesize isHidden = _isHidden;

- (id)initWithGraph:(ThroughputGraphView *)theGraph
{
    if (self = [super init])
    {
        _graph = theGraph;
        _color = [[NSColor redColor] retain];
        _peakGroup = kNoPeakGroup;
        
        unsigned defaultCount = NSWidth([theGraph bounds]) / DEFAULT_HISTORY_COUNT_DIVISOR;
        [self setHistoryCount:defaultCount];
    }
    
    return self;
}

- (void)dealloc
{
    [_color release];
    [super dealloc];
}

- (unsigned)historyCount
{
    return _historyCount;
}

- (void)setHistoryCount:(unsigned)newCount
{
    if (newCount != _historyCount)
    {
        size_t newSize = sizeof(float) * newCount;
        _history = (float *)realloc(_history, newSize);
        
        // If the history grew, zero out the new entries.
        if (newCount > _historyCount)
        {
            bzero(&_history[_historyCount], newSize - (sizeof(float) * _historyCount));
        }
        
        _historyCount = newCount;
    }
}

//! Keeps the peak value up to date.
//!
- (void)insertValue:(float)newValue redraw:(BOOL)doRedraw
{
    // Shift values down and save the one that dropped off.
    memmove(&_history[1], &_history[0], sizeof(float) * (_historyCount - 1));
    
    // Insert new value.
    _history[0] = newValue;
    _peak = 0.0;
    
    // Update peak value.
    unsigned i;
    for (i = 0; i < _historyCount; ++i)
    {
        float value = _history[i];
        if (value > _peak)
        {
            _peak = value;
        }
    }
    
    if (doRedraw)
    {
        // Force the graph to completely redraw.
        [_graph setNeedsDisplay:YES];
    }
}

@end

@implementation ThroughputGraphView

@synthesize backgroundColor = _backgroundColor;
@synthesize peakGroups = _peakGroups;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        // Create series dict.
        _series = [[NSMutableDictionary dictionary] retain];
        
        // Set background color to black by default.
        _backgroundColor = [[NSColor blackColor] retain];
    }
    return self;
}

- (void)dealloc
{
    if (_peakGroups)
    {
        free(_peakGroups);
    }
    
    [_series release];
    [_backgroundColor release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect myBounds = [self bounds];
    float myWidth = NSWidth(myBounds);
    float myHeight = NSHeight(myBounds);
    
    [NSGraphicsContext saveGraphicsState];
    
    // Draw a black background.
    [_backgroundColor set];
    [NSBezierPath fillRect:[self bounds]];
    
    // Iterate of all of the series attached to this graph.
    float seriesOffset = 0.0;
    NSString * seriesName;
    for (seriesName in _series)
    {
        // Skip the series if it is visible.
        GraphSeries * series = [_series objectForKey:seriesName];
        if (series.isHidden)
        {
            continue;
        }
        
        // Get values from the series.
        float * history = series.history;
        unsigned count = series.historyCount;
        float peak = series.peak;
        
        // Create a new path object.
        NSBezierPath * path = [NSBezierPath bezierPath];
        [path setLineWidth:2.0];
        
        // Draw each of the segments into the path.
        BOOL isFirstPoint = YES;
        float x = seriesOffset;
        int i;
        float xDelta = myWidth / (float)count;
        for (i = count - 1; i >= 0; --i, x += xDelta)
        {
            float value = history[i];
            
            // Scale value to fit in the view.
            value = value * myHeight / peak;
            
            // Add the line segment.
            NSPoint valuePoint = { .x = x, .y = value };
            if (isFirstPoint)
            {
                [path moveToPoint:valuePoint];
                isFirstPoint = NO;
            }
            else
            {
                [path lineToPoint:valuePoint];
            }
        }
        
        [series.color set];
        [path stroke];
        
        // Offset each series a little bit from the previous one.
        seriesOffset += 0.5;
    }
    
    [NSGraphicsContext restoreGraphicsState];
}

- (GraphSeries *)addSeriesWithName:(NSString *)seriesName
{
    // If a series with the given name already exists, just return it.
    GraphSeries * series = [_series objectForKey:seriesName];
    if (series != nil)
    {
        return series;
    }
    
    series = [[[GraphSeries alloc] initWithGraph:self] autorelease];
    [_series setObject:series forKey:seriesName];
    
    return series;
}

- (GraphSeries *)seriesWithName:(NSString *)seriesName
{
    return [_series objectForKey:seriesName];
}

- (void)setPeakGroupCount:(unsigned)count
{
    if (count)
    {
        _peakGroups = (float *)realloc(_peakGroups, sizeof(float) * count);
        assert(_peakGroups);
    }
    else if (_peakGroups)
    {
        free(_peakGroups);
        _peakGroups = NULL;
    }
    
    _peakGroupCount = count;
}

@end


