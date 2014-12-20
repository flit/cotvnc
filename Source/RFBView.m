/* Copyright (C) 1998-2000  Helmut Maierhofer <helmut.maierhofer@chello.at>
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

#import "RFBView.h"
#import "EventFilter.h"
#import "RFBConnection.h"
#import "FrameBuffer.h"
#import "RectangleList.h"

@implementation RFBView

@synthesize eventFilter = _eventFilter;
@synthesize delegate = _delegate;
@synthesize frameBuffer = fbuf;

+ (NSCursor *)_cursorForName: (NSString *)name
{
	static NSDictionary *sMapping = nil;
	if ( ! sMapping )
	{
		NSBundle *mainBundle = [NSBundle mainBundle];
		NSDictionary *entries = [NSDictionary dictionaryWithContentsOfFile: [mainBundle pathForResource: @"cursors" ofType: @"plist"]];
		NSParameterAssert( entries != nil );
		sMapping = [[NSMutableDictionary alloc] init];
		NSEnumerator *cursorNameEnumerator = [entries keyEnumerator];
		NSDictionary *cursorName;
		
		while ( cursorName = [cursorNameEnumerator nextObject] )
		{
			NSDictionary *cursorEntry = [entries objectForKey: cursorName];
			NSString *localPath = [cursorEntry objectForKey: @"localPath"];
			NSString *path = [mainBundle pathForResource: localPath ofType: nil];
			NSImage *image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
			
			int hotspotX = [[cursorEntry objectForKey: @"hotspotX"] intValue];
			int hotspotY = [[cursorEntry objectForKey: @"hotspotY"] intValue];
			NSPoint hotspot = {hotspotX, hotspotY};
			
			NSCursor *cursor = [[[NSCursor alloc] initWithImage: image hotSpot: hotspot] autorelease];
			[(NSMutableDictionary *)sMapping setObject: cursor forKey: cursorName];
		}
	}
	
	return [sMapping objectForKey: name];
}

- (id)initWithFrame:(NSRect)frameRect
{
    if (self = [super initWithFrame:frameRect])
    {
        // Indicate that this view can draw on a background thread.
        [self setCanDrawConcurrently:YES];
    }
    
    return self;
}

- (void)dealloc
{
    [fbuf release];
	[_remoteCursor release];
    [super dealloc];
}

- (void)setCursorTo: (NSString *)name
{
	// Don't allow overriding a remote cursor.
	if (_remoteCursor)
	{
		return;
	}
	
	if (!name)
	{
		name = @"rfbCursor";
	}

	// The cursor doesn't need to be retained an extra time; it is already
	// retained by being stored in the name dict.
	_cursor = [[self class] _cursorForName: name];
    [[self window] invalidateCursorRectsForView: self];
}

- (void)setRemoteCursor:(NSCursor *)newCursor
{
	NSCursor * prev = _remoteCursor;
	_remoteCursor = [newCursor retain];
	[prev release];
	
	_cursor = _remoteCursor;

	if (!newCursor)
	{
		// Pass nil to set to default cursor.
		[self setCursorTo:nil];
	}
	else
	{
		// Force the window to rebuild its cursor rects. This will cause our new cursor to
        // be set.
        [[self window] performSelectorOnMainThread:@selector(resetCursorRects) withObject:nil waitUntilDone:NO];
	}
}

- (void)resetCursorRects
{
    [self addCursorRect:[self visibleRect] cursor: _cursor];
}

- (void)setFrameBuffer:(id)aBuffer;
{
    NSRect f = [self frame];
    
    [fbuf autorelease];
    fbuf = [aBuffer retain];
    f.size = [aBuffer size];
    [self setFrame:f];
}

- (void)setDelegate:(RFBConnectionController *)delegate
{
    _delegate = delegate;
    
	[self setCursorTo: nil];
	[self setPostsFrameChangedNotifications: YES];
	[[NSNotificationCenter defaultCenter] addObserver: _delegate selector: @selector(viewFrameDidChange:) name: NSViewFrameDidChangeNotification object: self];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return NO;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)wantsDefaultClipping
{
    return NO;
}

- (void)drawRect:(NSRect)destRect
{
    NSRect b = [self bounds];

#if 1
    NSRect r = destRect;
    r.origin.y = b.size.height - NSMaxY(r);
    [fbuf drawRect:r at:destRect.origin];
#else    
    const NSRect * rects;
    int rectCount;
    [self getRectsBeingDrawn:&rects count:&rectCount];
    
    // Draw each of the individual dirty rects making up destRect instead of drawing the whole thing.
    for (int i=0; i < rectCount; ++i)
    {
        NSRect r = rects[i];
        r.origin.y = b.size.height - NSMaxY(r);
        [fbuf drawRect:r at:rects[i].origin];
    }
#endif
}

- (void)displayFromBuffer:(NSRect)aRect
{
    NSRect b = [self bounds];
    NSRect r = aRect;

    r.origin.y = b.size.height - NSMaxY(r);

	// Try to draw immediately instead of going through the normal update mechanism.
    if ([self canDraw])
    {
        [self displayRect:r];
    }
	else
	{
		// Can't lock focus, but we don't want to miss this update, so mark the
		// rectangle as invalid so it will be redrawn from the main event loop.
		[self setNeedsDisplayInRect:aRect];
	}
}

- (void)drawRectList:(id)aList
{
	unsigned count = [aList rectCount];
	unsigned i;
	for (i=0; i < count; ++i)
	{
		[self displayFromBuffer:[aList rectAtIndex:i]];
	}
}

- (void)mouseDown:(NSEvent *)theEvent
{  [_eventFilter mouseDown: theEvent];  }

- (void)rightMouseDown:(NSEvent *)theEvent
{  [_eventFilter rightMouseDown: theEvent];  }

- (void)otherMouseDown:(NSEvent *)theEvent
{  [_eventFilter otherMouseDown: theEvent];  }

- (void)mouseUp:(NSEvent *)theEvent
{  [_eventFilter mouseUp: theEvent];  }

- (void)rightMouseUp:(NSEvent *)theEvent
{  [_eventFilter rightMouseUp: theEvent];  }

- (void)otherMouseUp:(NSEvent *)theEvent
{  [_eventFilter otherMouseUp: theEvent];  }

- (void)mouseEntered:(NSEvent *)theEvent
{
	[[self window] setAcceptsMouseMovedEvents: YES];
}

- (void)mouseExited:(NSEvent *)theEvent
{
	[[self window] setAcceptsMouseMovedEvents: NO];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	[_eventFilter mouseMoved: theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	[_eventFilter mouseDragged: theEvent];
	
	// Pass the drag event to the delegate as a mouse moved event, if it wants them.
	if ([_delegate wantsMouseMovedOnDrag])
	{
		[_delegate mouseMoved:theEvent];
	}
}

- (void)rightMouseDragged:(NSEvent *)theEvent
{
	[_eventFilter rightMouseDragged: theEvent];
	
	// Pass the drag event to the delegate as a mouse moved event, if it wants them.
	if ([_delegate wantsMouseMovedOnDrag])
	{
		[_delegate mouseMoved:theEvent];
	}
}

- (void)otherMouseDragged:(NSEvent *)theEvent
{
	[_eventFilter otherMouseDragged: theEvent];
	
	// Pass the drag event to the delegate as a mouse moved event, if it wants them.
	if ([_delegate wantsMouseMovedOnDrag])
	{
		[_delegate mouseMoved:theEvent];
	}
}

// jason - this doesn't work, I think because the server I'm testing against doesn't support
// rfbButton4Mask and rfbButton5Mask (8 & 16).  They're not a part of rfbProto, so that ain't
// too surprising.
// 
// Later note - works fine now, maybe more servers have added support since I wrote the original
// comment
- (void)scrollWheel:(NSEvent *)theEvent
{  [_eventFilter scrollWheel: theEvent];  }

- (void)keyDown:(NSEvent *)theEvent
{  [_eventFilter keyDown: theEvent];  }

- (void)keyUp:(NSEvent *)theEvent
{  [_eventFilter keyUp: theEvent];  }

- (void)flagsChanged:(NSEvent *)theEvent
{  [_eventFilter flagsChanged: theEvent];  }

- (void)swipeWithEvent:(NSEvent *)event
{
//    NSLog(@"swipe event: %@", event);
    
    // The deltaX of the swipe event will be -1 or 1 for left and right swipes, respectively.
    // Same for deltaY and up or down swipes.
    float dx = [event deltaX];
    float dy = [event deltaY];
    if (dx < 0.0)
    {
        // Swipe left
        [NSApp sendAction:@selector(showPreviousConnection:) to:nil from:self];
    }
    else if (dx > 0.0)
    {
        // Swipe right
        [NSApp sendAction:@selector(showNextConnection:) to:nil from:self];
    }
    else if (dy < 0.0 || dy > 0.0)
    {
        // Swipe up or down
        [NSApp sendAction:@selector(toggleFullscreenMode:) to:nil from:self];
    }
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender {}

- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender
{
    return NSDragOperationGeneric;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {}

- (unsigned int)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return NSDragOperationGeneric;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    return [_delegate pasteFromPasteboard:[sender draggingPasteboard]];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    return YES;
}

@end
