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

#include <unistd.h>
#include <libc.h>
#include <CoreAudio/HostTime.h>
#import "RFBConnectionController.h"
#import "RFBConnection.h"
#import "EncodingReader.h"
#import "EventFilter.h"
#import "FrameBuffer.h"
#import "FrameBufferUpdateReader.h"
#import "FullscreenWindow.h"
#import "IServerData.h"
#import "KeyEquivalentManager.h"
#import "NLTStringReader.h"
#import "PrefController.h"
#import "RectangleList.h"
#import "RFBConnectionManager.h"
#import "RFBHandshaker.h"
#import "RFBProtocol.h"
#import "RFBServerInitReader.h"
#import "RFBView.h"
#import "TightEncodingReader.h"
#import "RFBConnectionInfoController.h"

//! \brief Very simple view that always fills itself with black.
@interface BlackView : NSView
{
}
@end

@implementation BlackView

- (BOOL)isOpaque
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor blackColor] set];
    [NSBezierPath fillRect:dirtyRect];
}

@end

@interface RFBConnectionController ()

- (void)finishInitWithServer:(id<IServerData>)server profile:(Profile*)p owner:(id)owner;
- (void)completeConnectionWithTarget:(id<RFBConnectionCompleting>)theTarget;
- (void)connectThread:(id)target;
- (void)connectTimer:(NSTimer *)theTimer;
- (void)reconnect;

@end

@implementation RFBConnectionController

@synthesize rfbView, scrollView, window;
@synthesize manager = _manager;
@synthesize connection = _connection;
@synthesize profile = _profile;
@synthesize server = _server;
@synthesize eventFilter = _eventFilter;
@synthesize isTerminating = terminating;
@synthesize isFullscreen = _isFullscreen;
@synthesize wantsMouseMovedOnDrag = _wantsMouseMovedOnDrag;
@synthesize realDisplayName;

- (void)finishInitWithServer:(id<IServerData>)server profile:(Profile*)p owner:(id)owner
{
    // Loads nibs.
    [NSBundle loadNibNamed:@"RFBConnection.nib" owner:self];
    [NSBundle loadNibNamed:@"SetTitle.nib" owner:self];
    [NSBundle loadNibNamed:@"OpeningConnection.nib" owner:self];

    // Init some variables.
    _server = [(id)server retain];
    _profile = [p retain];
    _manager = owner;
    _isFullscreen = NO;
	
    // Create the event filter and connect it up between the connection and view.
	_eventFilter = [[EventFilter alloc] init];
    [_eventFilter setController:self];
	[_eventFilter setConnection:_connection];
    [_eventFilter setView:rfbView];
    _connection.eventFilter = _eventFilter;

    // Set the view's event filter and delegate. Setting the delegate adds us as an observer for
    // viewFrameDidChange notifications on the view.
    rfbView.eventFilter = _eventFilter;
    rfbView.delegate = self;

	// We support dragging strings and file (names) into the view.
	//! \todo Should the view itself be registering drag types?
    [rfbView registerForDraggedTypes:[NSArray arrayWithObjects:NSStringPboardType, NSFilenamesPboardType, nil]];
}

- (id)initWithServer:(id<IServerData>)server profile:(Profile*)p owner:(id)owner
{
    if (self = [super init])
    {
        _connection = [[RFBConnection alloc] initWithServer:server profile:p];
        _connection.controller = self;
    
        [self finishInitWithServer:server profile:p owner:owner];
	}
    return self;
}

- (id)initWithFileHandle:(NSFileHandle*)file server:(id<IServerData>)server profile:(Profile*)p owner:(id)owner
{
    if (self = [super init])
    {
        _connection = [[RFBConnection alloc] initWithFileHandle:file server:server profile:p];
        _connection.controller = self;
        
        [self finishInitWithServer:server profile:p owner:owner];
	}
    return self;
}

- (void)dealloc
{
    NSLog(@"RFBConnectionController dealloc");
    
    // Just in case.
    [self terminateConnection:nil];
    
    // Remove all tracking rects.
    [self removeMouseMovedTrackingRect];
    [self removeFullscreenTrackingRects];
    
    [_infoWindow close];
    [_infoWindow release];

	[newTitlePanel orderOut:self];
    [_openingConnectionPanel orderOut:self];
	[window close];

    [_eventFilter release];
    [_connection release];
    [_profile release];
    [_server release];
    [realDisplayName release];
    [titleString release];
    
    [super dealloc];
}

//! Performs post-connection tasks such as informing the connection completion target of the
//! connection status.
- (void)completeConnectionWithTarget:(id<RFBConnectionCompleting>)theTarget
{
    if (theTarget)
    {
        [theTarget connection:self didCompleteWithStatus:_didConnect];
    }
}

//! This thread is used to open the connection to a remote server in the background, so the
//! main thread is not blocked. In most cases, this thread exists for a very short time.
//! When the connect method returns, we post a method call back on the main thread to tell the
//! connection completion target the connection status. Finally, the connect timer is
//! invalidated to prevent showing the open connection panel, if it hasn't already been shown.
//! The panel is then hidden if it was shown.
- (void)connectThread:(id)target
{
    NSAutoreleasePool * pool;
    
    @try
    {
        pool = [[NSAutoreleasePool alloc] init];
        
        // Set our thread name.
        [[NSThread currentThread] setName:[NSString stringWithFormat:@"connect:%@", _server.host]];
        
        // Try to connect.
        NSError * error;
        _didConnect = [_connection connectReturningError:&error];
        
        // Invalidate the connect timer.
        [_connectTimer invalidate];
        [_connectTimer release];
        _connectTimer = nil;
        
        // Hide the connect panel.
        [_openingConnectionPanel orderOut:self];

        // Inform our target of the connection status on the main thread. We use a trampoline
        // method since performSelectorOnMainThread only accepts one argument, and it must be an id.
        [self performSelectorOnMainThread:@selector(completeConnectionWithTarget:) withObject:target waitUntilDone:NO];

        // Show an error alert if we got an error back, unless we're terminating (because the user
        // has cancelled the connection).
        if (!_didConnect && error && !terminating)
        {
            NSString *ok = NSLocalizedString( @"Okay", nil );
            NSRunAlertPanel([error localizedDescription], [error localizedFailureReason], ok, NULL, NULL, NULL);
            
            // Terminate ourself.
            [self terminateConnection:nil];
        }
    }
    @catch (id e)
    {
        NSLog(@"Unexpected exception during connect: %@", e);
    }
    @finally
    {
        [pool release];
    }
}

//! This timer fires after a short delay, meaning that opening the connection is taking longer
//! than normal. So we open up the connecting window to give the user something to look at and
//! a way to cancel.
- (void)connectTimer:(NSTimer *)theTimer
{
    // Set up opening connection panel.
    [_openingConnectionText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"OpeningConnectionMessage", nil), _connection.host]];
    [_openingConnectionProgress startAnimation:self];
    [_openingConnectionPanel center];
    [_openingConnectionPanel makeKeyAndOrderFront:self];
    
    // Run the run loop for a short period of time. This keeps the opening connection panel on
    // screen for a minimum amount of time, thus preventing any possible flickering.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
}

- (void)connectWithCompletionTarget:(id<RFBConnectionCompleting>)target
{
    // Create a timer that will fire after a bit and show the opening connection panel. The
    // timer is created before the connect thread is started to prevent a race condition when
    // invalidating the timer.
    _connectTimer = [[NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(connectTimer:) userInfo:nil repeats:NO] retain];

    // Create the thread to open the connection.
    [NSThread detachNewThreadSelector:@selector(connectThread:) toTarget:self withObject:target];
}

- (IBAction)cancelConnect:(id)sender
{
    NSLog(@"cancel connection");
    [_openingConnectionPanel orderOut:self];
    [self terminateConnection:nil];
}

- (void)connectionHasTerminated
{
    NSLog(@"RFBConnectionController connectionHasTerminated");
    
    // Add an extra retain-autorelease to this object so that we're sure it won't be dealloc'd
    // prematurely, while this code is still running. This could happen if the connection failed
    // and this object never got added to the manager's list of connections.
//    [[self retain] autorelease];
    
    // Stop listening to notifications.
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Tell connection to really close things down now.
    [_connection connectionHasTerminated];
    
    // Removing us from the manager will cause us to be autoreleased.
    [_manager removeConnection:self];
}

//! This method is only called if the server supports connection, i.e. that it isn't a
//! ServerFromConnection created from a reverse connection.
- (void)reconnect
{
    NSLog(@"RFBConnectionController reconnecting");
    
    // We're no longer terminating.
    terminating = NO;
    _didConnect = NO;
    
    // Shut down and get rid of the old connection object.
    [_connection connectionHasTerminated];
    [_connection release];
    
    // Create the new connection object.
    _connection = [[RFBConnection alloc] initWithServer:_server profile:_profile];
    _connection.controller = self;
    
    // Update event filter connections.
	[_eventFilter setConnection:_connection];
    _connection.eventFilter = _eventFilter;
    
    [self connectWithCompletionTarget:nil];
}

- (void)connectionTerminatedSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	// One might reasonably argue that this should be handled by the connection manager.
	switch (returnCode)
    {
		case NSAlertDefaultReturn:
			break;
		case NSAlertAlternateReturn:
			[self reconnect];
			return;
		default:
			NSLog(@"Unknown alert returnvalue: %d", returnCode);
	}

    [self connectionHasTerminated];
}

- (void)terminateConnection:(NSString*)aReason
{
    if (terminating)
	{
        return;
    }
    
    terminating = YES;
    NSLog(@"RFBConnectionController terminating connection:%@!", aReason);
    
    // Tell the connection to terminate.
    if (!_connection.isTerminating)
    {
        [_connection terminateConnection:aReason];
    }
    
    // Ignore our timer (It's invalid)
    [self resetReconnectTimer];

    // Stop any autoscrolling.
    [self endFullscreenScrolling];

    // Switch back to windowed mode if we're in full screen.
    if (_isFullscreen)
    {
        [self makeConnectionWindowed: self];
    }
    
    // Remove all tracking rects.
    [self removeMouseMovedTrackingRect];
    [self removeFullscreenTrackingRects];
    
    if (aReason)
    {
        if ( _autoReconnect )
        {
            NSLog(@"Automatically reconnecting to server.  The connection was closed because: \"%@\".", aReason);
            // Just auto-reconnect
            [self reconnect];
        }
        else
        {
            // Ask user what to do next.
            NSString *header = NSLocalizedString( @"ConnectionTerminated", nil );
            NSString *okayButton = NSLocalizedString( @"Okay", nil );
            NSString *reconnectButton =  NSLocalizedString( @"Reconnect", nil );
            
            if ([window isVisible])
            {
                NSBeginAlertSheet(header, okayButton, [_server doYouSupport:CONNECT] ? reconnectButton : nil, nil, window, self, @selector(connectionTerminatedSheetDidEnd:returnCode:contextInfo:), nil, nil, aReason);
            }
            else
            {
                int alertResult = NSRunAlertPanel(header, aReason, okayButton, [_server doYouSupport:CONNECT] ? reconnectButton : nil, NULL, NULL);
                [self connectionTerminatedSheetDidEnd:nil returnCode:alertResult contextInfo:nil];
            }
        }
        
        return;
    }
    else
    {
        [self connectionHasTerminated];
    }
}

//! \note This method operates on window frame sizes, not content frame sizes. So the sizes
//!     must include the window border (title bar, etc.).
- (NSSize)_maxSizeForWindowSize:(NSSize)aSize;
{
    NSRect  winframe;
    NSSize	maxviewsize;
	BOOL usesFullscreenScrollers = [[PrefController sharedController] fullscreenHasScrollbars];
	
    horizontalScroll = verticalScroll = NO;
	if (!_isFullscreen || usesFullscreenScrollers)
    {
        if (aSize.width < _maxSize.width)
        {
            horizontalScroll = YES;
        }
        if (aSize.height < _maxSize.height)
        {
            verticalScroll = YES;
        }
    }
	
	maxviewsize = [NSScrollView frameSizeForContentSize:[rfbView frame].size
							  hasHorizontalScroller:horizontalScroll
								hasVerticalScroller:verticalScroll
										 borderType:NSNoBorder];
    
	if (!_isFullscreen || usesFullscreenScrollers)
    {
        if (aSize.width < maxviewsize.width)
        {
            horizontalScroll = YES;
        }
        if (aSize.height < maxviewsize.height)
        {
            verticalScroll = YES;
        }
    }
    
    aSize = [NSScrollView frameSizeForContentSize:[rfbView frame].size
                            hasHorizontalScroller:horizontalScroll
                              hasVerticalScroller:verticalScroll
                                       borderType:NSNoBorder];

    winframe = [window frame];
    winframe.size = aSize;
    winframe = [NSWindow frameRectForContentRect:winframe styleMask:[window styleMask]];
    return winframe.size;
}

//! Sets the frame buffer in the RFB view. Computes the maximum window size for the main screen.
//! Figures out if scroll bars are necessary. Sets the window title. Then centers and displays
//! the window, making sure the tracking rects are updated.
- (void)setFrameBuffer:(FrameBuffer *)fb
{
    // Set the frame buffer in the remote screen view.
    [rfbView setFrameBuffer:fb];

    // The remote display size is the frame buffer size.
    NSSize displaySize = [fb size];
	NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
    NSRect wf;
    wf.origin.x = wf.origin.y = 0;
    
    // Start with the full scroll view frame size for the remote screen.
    wf.size = [NSScrollView frameSizeForContentSize:[rfbView frame].size hasHorizontalScroller:NO hasVerticalScroller:NO borderType:NSNoBorder];
    
    // Expand to include the window border. Then constrain to the visible screen area, enabling
    // scroll bars as necessary.
    wf = [NSWindow frameRectForContentRect:wf styleMask:[window styleMask]];
	if (NSWidth(wf) > NSWidth(screenRect))
    {
		horizontalScroll = YES;
		wf.size.width = NSWidth(screenRect);
	}
	if (NSHeight(wf) > NSHeight(screenRect))
    {
		verticalScroll = YES;
		wf.size.height = NSHeight(screenRect);
	}
    
    // Save the maximum window frame size for the main screen.
	_maxSize = wf.size;
	
	// According to the Human Interace Guidelines, new windows should be "visually centered"
	// If screenRect is X1,Y1-X2,Y2, and wf is x1,y1 -x2,y2, then
	// the origin (bottom left point of the rect) for wf should be
	// Ox = ((X2-X1)-(x2-x1)) * (1/2)    [I.e., one half screen width less window width]
	// Oy = ((Y2-Y1)-(y2-y1)) * (2/3)    [I.e., two thirds screen height less window height]
	// Then the origin must be offset by the "origin" of the screen rect.
	// Note that while Rects are floats, we seem to have an issue if the origin is
	// not an integer, so we use the floor() function.
	wf.origin.x = floor((NSWidth(screenRect) - NSWidth(wf))/2 + NSMinX(screenRect));
	wf.origin.y = floor((NSHeight(screenRect) - NSHeight(wf))*2/3 + NSMinY(screenRect));
	
    // Set the window's frame to a frame previously saved under this server's name. If no
    // saved frame exists, set the window frame to the maximum size.
	NSString * serverName = [_server name];
	if (![window setFrameUsingName:serverName])
    {
		[window setFrame:wf display:NO];
	}
	[window setFrameAutosaveName:serverName];

    // Scroll the RFB view so its top-left is visible.
	NSClipView * contentView = [scrollView contentView];
    [contentView scrollToPoint: [contentView constrainScrollPoint: NSMakePoint(0.0, displaySize.height - [scrollView contentSize].height)]];
    [scrollView reflectScrolledClipView: contentView];

    // Final preparations, then show the window.
    [window makeFirstResponder:rfbView];
	[self windowDidResize: nil];

    // Switch to fullscreen mode if the user has set the flag in the server prefs. Otherwise just
    // show the window.
    if ([_server fullscreen])
	{
        [self makeConnectionFullscreen: self];
    }
    else
    {
        [window makeKeyAndOrderFront:self];
    }
}

- (BOOL)isConnectionShared
{
    return [_server shared];
}

- (BOOL)isViewOnly
{
	return [_server viewOnly];
}

- (NSRect)visibleRect
{
    return [rfbView bounds];
}

- (void)setDisplayName:(NSString*)aName
{
	[realDisplayName autorelease];
    realDisplayName = [aName retain];
    [titleString autorelease];
    titleString = [[_manager translateDisplayName:realDisplayName forHost:_connection.host] retain];
    [window setTitle:titleString];
}

- (IBAction)setNewTitle:(id)sender
{
    [titleString autorelease];
    titleString = [[newTitleField stringValue] retain];

    [_manager setDisplayNameTranslation:titleString forName:realDisplayName forHost:_connection.host];
    [window setTitle:titleString];
	
	[NSApp endSheet:newTitlePanel];
}

- (IBAction)cancelNewTitle:(id)sender
{
	[NSApp endSheet:newTitlePanel];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	// Make the sheet actually go away.
    [newTitlePanel orderOut:self];
}

- (void)openNewTitlePanel:(id)sender
{
    [newTitleField setStringValue:titleString];
	
	[NSApp beginSheet:newTitlePanel modalForWindow:window modalDelegate:self didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction)openOptions:(id)sender
{
    // Create the info window if it hasn't been opened before.
    if (!_infoWindow)
    {
        _infoWindow = [[RFBConnectionInfoController alloc] initWithController:self];
    }
    
    // Show the info window.
    [_infoWindow showWindow:self];
}

//! Used to postpone drawing until all the rectangles within one update are
//! decoded and blitted into the frame buffer. Once processing of the update
//! is finished, FrameBufferUpdateReader will call -flushWindow. That method
//! re-enables flushing and flushes immediately.
- (void)pauseDrawing
{
//    [window disableFlushWindow];
}

//! Enables window flushing and flushes all drawing immediately. This method
//! also queues another update request from the server.
- (void)flushDrawing
{
	if ([window isFlushWindowDisabled])
	{
		[window enableFlushWindow];
	}
    [window flushWindow];
}

- (void)windowDidDeminiaturize:(NSNotification *)aNotification
{
    // Return to front update frequency.
	[_connection setFrameBufferUpdateSeconds: [[PrefController sharedController] frontFrameBufferUpdateSeconds]];

	[self removeMouseMovedTrackingRect];
	[self installMouseMovedTrackingRect];
	[self removeFullscreenTrackingRects]; // added creed
	[self installFullscreenTrackingRects]; // added creed
}

- (void)windowDidMiniaturize:(NSNotification *)aNotification
{
    // Set the update frequency to that of a background window, but keep updating since the window
    // content is visible on the dock.
	[_connection setFrameBufferUpdateSeconds: [[PrefController sharedController] otherFrameBufferUpdateSeconds]];
    
	[self removeMouseMovedTrackingRect];
	[self removeFullscreenTrackingRects]; // added creed
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    // terminateConnection closes the window, so we have to null it out here
    // The window will autorelease itself when closed.  If we allow terminateConnection
    // to close it again, it will get double-autoreleased.  Bummer.
    window = NULL;
    
    // If we were to call terminateConnection: directly, there is a possibility of a deadlock.
    // The connectionHasTerminated method in RFBConnection waits for the reader thread to exit.
    // But the reader thread could be waiting for the lock on the window to do some drawing.
    // So if connectionHasTerminated is called from this window will close handler (which
    // holds the window lock), you have a deadlock. Posting the terminate message to the main
    // thread (even though we're already on the main thread) will cause it to run outside of
    // the window close handler, after the window lock is released.
    [self performSelectorOnMainThread:@selector(terminateConnection:) withObject:nil waitUntilDone:NO];
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize
{
    NSSize max = [self _maxSizeForWindowSize:proposedFrameSize];

    max.width = (proposedFrameSize.width > max.width) ? max.width : proposedFrameSize.width;
    max.height = (proposedFrameSize.height > max.height) ? max.height : proposedFrameSize.height;
    return max;
}

- (void)windowDidResize:(NSNotification *)aNotification
{
	[scrollView setHasHorizontalScroller:horizontalScroll];
	[scrollView setHasVerticalScroller:verticalScroll];

	// Reconstruct mouse moved tracking rect.
	[self removeMouseMovedTrackingRect];
	[self installMouseMovedTrackingRect];
	
	// Reconstruct autoscroll tracking rects.
	[self removeFullscreenTrackingRects];
	[self installFullscreenTrackingRects];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Catch possible exceptions thrown by protocol code.
    @try
    {
        // Reconstruct mouse moved tracking rect.
        [self removeMouseMovedTrackingRect];
        [self installMouseMovedTrackingRect];
        
        // Reconstruct autoscroll tracking rects.
        [self removeFullscreenTrackingRects];
        [self installFullscreenTrackingRects];
        
        // Switch to foreground update rate. This also queues an update request.
        [_connection setFrameBufferUpdateSeconds: [[PrefController sharedController] frontFrameBufferUpdateSeconds]];
        
        [self updateRemotePasteboard];
    }
    @catch (id e)
    {
        NSLog(@"windowDidBecomeKey: caught exception: %@", e);
        [self terminateConnection:[e description]];
    }
}

- (void)windowDidResignKey:(NSNotification *)aNotification
{
    // Catch possible exceptions thrown by protocol code.
    @try
    {
        [self removeMouseMovedTrackingRect];
        [self removeFullscreenTrackingRects];
        
        // Switch to background update rate.
        [_connection setFrameBufferUpdateSeconds: [[PrefController sharedController] otherFrameBufferUpdateSeconds]];
        
        //Reset keyboard state on remote end
        [_connection clearAllEmulationStates];
        [_connection releaseAllModifierKeys];
    }
    @catch (id e)
    {
        NSLog(@"windowDidResignKey: caught exception: %@", e);
        [self terminateConnection:[e description]];
    }
}

- (void)viewFrameDidChange:(NSNotification *)aNotification
{
	[self removeMouseMovedTrackingRect];
	[self installMouseMovedTrackingRect];
    [window invalidateCursorRectsForView: rfbView];
}

- (IBAction)toggleFullscreenMode: (id)sender
{
	_isFullscreen ? [self makeConnectionWindowed: self] : [self makeConnectionFullscreen: self];
}

//! \brief Removes the scroll view from its window.
- (NSWindow *)removeFromWindow
{
	[self removeMouseMovedTrackingRect];
	[self removeFullscreenTrackingRects]; // added creed
	
	[scrollView retain];
	[scrollView removeFromSuperview];
	
	[window setDelegate: nil];
	NSWindow * saveWindow = window;
	window = nil;
	
	return saveWindow;
}

//! \brief Put the receiver's scroll view in the given window.
//!
//! The receiver's scroll view is placed into \a theWindow, updating the view's frame and
//! all tracking rects. The window is also ordered front and made key. If \a isFullscreen is
//! true, the scroll view is centered in the window. \a isHidden lets the sender control whether
//! the scroll view is made hidden before being added to the window. This is used for fullscreen
//! transition animations.
- (void)placeInWindow:(NSWindow *)theWindow isFullscreen:(BOOL)isFullscreen hidden:(BOOL)isHidden
{
	_isFullscreen = isFullscreen;
	window = theWindow;
    
	[window setDelegate: self];
    
    [scrollView setHidden:isHidden];
    
    // Handle fullscreen separately from a normal window.
    if (isFullscreen)
    {
        // For fullscreen windows, we place the scrollview inside an empty view that is the
        // window's content view. A previously existing content view will be reused if possible.
        // If the remote screen is smaller than the fullscreen window, it is centered within the
        // content view.
        NSView * theContentView = [window contentView];
        NSSize windowSize = [window frame].size;
        NSSize remoteScreenSize = [rfbView frame].size;

        // Create a content view if there isn't already one, or if the content view is not our black view, which will be
        // the case for the default content view when the window is first created.
        NSRect contentFrame;
        if (!theContentView || ![theContentView isKindOfClass:[BlackView class]])
        {
            contentFrame.origin.x = 0;
            contentFrame.origin.y = 0;
            contentFrame.size = windowSize;
            theContentView = [[[BlackView alloc] initWithFrame:contentFrame] autorelease];
            
            [window setContentView:theContentView];
        }
        else
        {
            contentFrame = [theContentView frame];
        }
        
        // Center the scrollview in the content frame if needed.
        NSRect scrollFrame = contentFrame;
        if (remoteScreenSize.width < windowSize.width || remoteScreenSize.height < windowSize.height)
        {
            // The remote screen is smaller, so we want to insert another view as the actual
            // fullscreen window content view, in which the scroll view will be centered.
            
            // Update the scroll view's frame so it will be centered in the content view.
            scrollFrame.size = remoteScreenSize;
            if (NSWidth(scrollFrame) < NSWidth(contentFrame))
            {
                scrollFrame.origin.x = (NSWidth(contentFrame) - NSWidth(scrollFrame)) / 2.0;
            }
            if (NSHeight(scrollFrame) < NSHeight(contentFrame))
            {
                scrollFrame.origin.y = (NSHeight(contentFrame) - NSHeight(scrollFrame)) / 2.0;
            }
        }

        // Add the scrollview to the content view and set its frame.
        [theContentView addSubview:scrollView];
        [scrollView setFrame:scrollFrame];
    }
    else
    {
        // For a normal window, we can just make the scrollview the window's content view.
        // Setting the scroll view to the window's content view will cause the scroll view to be
        // resized to the window's content size.
        [window setContentView: scrollView];
    }
    
    // Release the scrollview that was retained in -removeFromWindow.
	[scrollView release];
	
    // Set h and v scroll bools. The scroll view's scrollbars are updated in windowDidResize: below.
    // This would normally be done by -windowWillResize:toSize:.
	[self _maxSizeForWindowSize: [window frame].size];
	
    // Rebuild all tracking rects.
    [self windowDidResize: nil]; // adds fullscreen tracking rects
    [self viewFrameDidChange: nil];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder: rfbView];
}

//! \brief Put the scroll view into a newly created normal window.
- (void)placeInNewWindow
{
	// Create a new normal window to hold the connection's view.
	NSWindow * newWindow = [[NSWindow alloc] initWithContentRect:[NSWindow contentRectForFrameRect: _windowedFrame styleMask: _styleMask]
										styleMask:_styleMask
										backing:NSBackingStoreBuffered
										defer:NO
										screen:[NSScreen mainScreen]];
	[newWindow setTitle:titleString];
	[self placeInWindow:newWindow isFullscreen:NO hidden:NO];
}

//! Set to 1 to actually capture the display. Set to 0 for debugging fullscreen code.
#define CAPTURE_DISPLAY 1

//! Set to 1 to utilize the new 10.5 fullscreen API of NSView.
#define USE_NEW_FULLSCREEN_API 0

//! Presentation options to use when presenting the fullscreen display.
#define FULLSCREEN_PRESENTATION_OPTIONS (NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar)

//! Presentation options to use when presenting the fullscreen display.
//#define FULLSCREEN_PRESENTATION_OPTIONS (NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar)


- (void)placeInFullscreenWindow
{
    // Save window style and frame before we close it.
    _windowedFrame = [window frame];
    _styleMask = [window styleMask];
    
    // Ensure that all other connections are windowed.
    [_manager makeAllConnectionsWindowed];
    
#if CAPTURE_DISPLAY
    // Grab the main display so no other apps can use it.
    if (CGDisplayCapture( kCGDirectMainDisplay ) != kCGErrorSuccess)
    {
        NSLog( @"Couldn't capture the main display!" );
    }
#endif

    // Pluck the view from the window and close it.
    [[self removeFromWindow] close];
    
    // Create the new fullscreen window.
    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSWindow * fullscreenWindow = [[FullscreenWindow alloc] initWithContentRect:screenRect
                                        styleMask:NSBorderlessWindowMask
                                        backing:NSBackingStoreBuffered
                                        defer:NO
                                        screen:[NSScreen mainScreen]];

#if CAPTURE_DISPLAY
    // Set the fullscreen window to the top window level.
    int windowLevel = CGShieldingWindowLevel();
    [fullscreenWindow setLevel:windowLevel];
#endif
    
    // Now put this connection into the fullscreen window.
    [self placeInWindow:fullscreenWindow isFullscreen:YES hidden:NO];
    
#if USE_NEW_FULLSCREEN_API
    NSDictionary * fullscreenOptions = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO], NSFullScreenModeAllScreens,
        [NSNumber numberWithUnsignedInt:FULLSCREEN_PRESENTATION_OPTIONS], NSFullScreenModeApplicationPresentationOptions,
//        [NSNumber numberWithInt:CGWindowLevelForKey(kCGMaximumWindowLevelKey)], NSFullScreenModeWindowLevel,
        nil, nil];
    [[fullscreenWindow contentView] enterFullScreenMode:[NSScreen mainScreen] withOptions:fullscreenOptions];
    [fullscreenWindow makeKeyWindow];
#endif // USE_NEW_FULLSCREEN_API
}

- (IBAction)makeConnectionWindowed: (id)sender
{
#if USE_NEW_FULLSCREEN_API
    NSDictionary * exitFullscreenOptions = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool:NO], NSFullScreenModeAllScreens,
        [NSNumber numberWithUnsignedInt:NSApplicationPresentationDefault], NSFullScreenModeApplicationPresentationOptions,
        nil, nil];
    [[[self window] contentView] exitFullScreenModeWithOptions:exitFullscreenOptions];
#endif // USE_NEW_FULLSCREEN_API
    
    // Extract the connection view from the fullscreen window.
	[[self removeFromWindow] close];

#if CAPTURE_DISPLAY
	// Release the display so other apps can use it.
	if (CGDisplayRelease(kCGDirectMainDisplay) != kCGErrorSuccess)
	{
		NSLog( @"Couldn't release the main display!" );
	}
#endif
	
	[self placeInNewWindow];
}

- (void)connectionWillGoFullscreen:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode == NSAlertDefaultReturn)
	{
        [self placeInFullscreenWindow];
	}
}

- (IBAction)makeConnectionFullscreen: (id)sender
{
	BOOL displayFullscreenWarning = [[PrefController sharedController] displayFullScreenWarning];

	if (displayFullscreenWarning)
    {
		NSString *header = NSLocalizedString( @"FullscreenHeader", nil );
		NSString *fullscreenButton = NSLocalizedString( @"Fullscreen", nil );
		NSString *cancelButton = NSLocalizedString( @"Cancel", nil );
		NSString *reason = NSLocalizedString( @"FullscreenReason", nil );
		NSBeginAlertSheet(header, fullscreenButton, cancelButton, nil, window, self, nil, @selector(connectionWillGoFullscreen: returnCode: contextInfo: ), nil, reason);
	}
    else
    {
		[self placeInFullscreenWindow]; 
	}
}

//! Does nothing if \a fromConnection is not already in fullscreen mode.
//! Conversely, it does nothing if the receiver is already in fullscreen mode,
//! which should mean \a fromConnection is not.
- (void)takeFullscreenFromConnection:(RFBConnectionController *)fromConnection direction:(TransitionDirection_t)direction
{
	if (!fromConnection.isFullscreen || _isFullscreen)
	{
		return;
	}

// before anim:
    // Save window style and frame before we close it.
    _windowedFrame = [window frame];
    _styleMask = [window styleMask];
    
	// Remove our view from its window and close the window.
	[[self removeFromWindow] close];

    // Get the scroll view from the original connection.
    NSView * fromScrollView = fromConnection.scrollView;

    // Add our view to the fullscreen window, but hidden. Its frame will be in the centered
    // position, which is actually where it will end up after the animation below. Before the
    // animation starts, we move it offscreen.
    NSWindow * fullscreenWindow = fromConnection.window;
	[self placeInWindow:fullscreenWindow isFullscreen:YES hidden:YES];
    
    // Pause update requests so they don't interfere with the animation.
    [_connection.protocol stopUpdate];
    [fromConnection.connection.protocol stopUpdate];
    
// anim prep:
    // Calculate a bunch of rectangles used for the animation.
    NSRect screenFrame = [fullscreenWindow frame];
    NSRect fromScrollFrame = [fromScrollView frame];
    NSRect toScrollFrame = [scrollView frame];
    NSRect fromEndingFrame;
    NSRect toStartingFrame;
    
    if (direction == kTransitionRightToLeft)
    {
        // Right to left transition.
        fromEndingFrame = NSMakeRect(-NSWidth(fromScrollFrame), fromScrollFrame.origin.y, NSWidth(fromScrollFrame), NSHeight(fromScrollFrame));
        toStartingFrame = NSMakeRect(NSWidth(screenFrame), toScrollFrame.origin.y, NSWidth(toScrollFrame), NSHeight(toScrollFrame));
    }
    else
    {
        // Left to right transition.
        fromEndingFrame = NSMakeRect(NSWidth(screenFrame), fromScrollFrame.origin.y, NSWidth(fromScrollFrame), NSHeight(fromScrollFrame));
        toStartingFrame = NSMakeRect(-NSWidth(toScrollFrame), toScrollFrame.origin.y, NSWidth(toScrollFrame), NSHeight(toScrollFrame));
    }

    // Set up the scroll view before the animation. Position it in its starting offscreen position
    // and unhide it.
    [scrollView setFrame:toStartingFrame];
    [scrollView setHidden:NO];

// during anim:
    const float animationDuration = 0.3;

    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:animationDuration];
    
    // Slide out the from scroll view while sliding in our scroll view.
    [[fromScrollView animator] setFrame:fromEndingFrame];
    [[scrollView animator] setFrame:toScrollFrame];
    
    [NSAnimationContext endGrouping];
	
    // Wait until the animation is over.
    //! \todo Figure out the preferred way to wait until an animation is finished.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:animationDuration]];
    
// after anim:
    // Restore update requests.
    [_connection.protocol continueUpdate];
    [fromConnection.connection.protocol continueUpdate];
    
	// Remove the old connection's view from the fullscreen window and put it back in a normal
    // window. This will return the from scrollview to non-hidden.
	[fromConnection removeFromWindow];
	[fromConnection placeInNewWindow];
    
    // Make sure we end up with the fullscreen window key.
    [fullscreenWindow setDelegate:self];
	[fullscreenWindow makeFirstResponder:rfbView];
    [fullscreenWindow makeKeyAndOrderFront:nil];
    [fullscreenWindow resetCursorRects];
}

- (float)trackingRectThickness
{
	return _isFullscreen ? kTrackingRectThicknessFullscreen : kTrackingRectThicknessWindowed;
}

- (void)installMouseMovedTrackingRect
{
	NSView * theView = scrollView; // rfbView
	NSPoint mousePoint = [theView convertPoint: [window convertScreenToBase: [NSEvent mouseLocation]] fromView: nil];
	NSRect trackingRect = [theView bounds]; //[rfbView visibleRect];
	float trackingRectThickness = [self trackingRectThickness];
	NSInsetRect(trackingRect, trackingRectThickness, trackingRectThickness);

	BOOL mouseInVisibleRect = [theView mouse: mousePoint inRect: trackingRect];
	_mouseMovedTrackingTag = [theView addTrackingRect: trackingRect owner: self userData: nil assumeInside: mouseInVisibleRect];
//	NSLog(@"installed mouse moved rect %d", _mouseMovedTrackingTag);

	if (mouseInVisibleRect)
	{
		[window setAcceptsMouseMovedEvents: YES];
	}
}

- (void)installFullscreenTrackingRects
{
	NSRect scrollRect = [scrollView bounds];
	const float minX = NSMinX(scrollRect);
	const float minY = NSMinY(scrollRect);
	const float maxX = NSMaxX(scrollRect);
	const float maxY = NSMaxY(scrollRect);
	const float width = NSWidth(scrollRect);
	const float height = NSHeight(scrollRect);
	float scrollWidth = [NSScroller scrollerWidth];
	NSRect aRect;
	NSView * theView = scrollView;
	float trackingRectThickness = [self trackingRectThickness];
	float hScrollWidth = (horizontalScroll ? scrollWidth : 0.0);
	float vScrollHeight = (verticalScroll ? scrollWidth : 0.0);
	
//	NSLog(@"installing fullscreen tracking rects");

	const NSTrackingAreaOptions trackingOptions = NSTrackingMouseMoved | NSTrackingEnabledDuringMouseDrag | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow;

	aRect = NSMakeRect(minX, minY + trackingRectThickness, trackingRectThickness, height - trackingRectThickness*2 - vScrollHeight);
	_leftTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_leftTrackingArea];
	
	aRect = NSMakeRect(minX + trackingRectThickness, minY, width - trackingRectThickness*2 - hScrollWidth, trackingRectThickness);
	_topTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_topTrackingArea];
	
	aRect = NSMakeRect(maxX - trackingRectThickness - hScrollWidth, minY + trackingRectThickness, trackingRectThickness, height - trackingRectThickness*2 - vScrollHeight);
	_rightTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_rightTrackingArea];
	
	aRect = NSMakeRect(minX + trackingRectThickness, maxY - trackingRectThickness - vScrollHeight, width - trackingRectThickness*2 - hScrollWidth, trackingRectThickness);
	_bottomTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_bottomTrackingArea];
	
	aRect = NSMakeRect(minX, minY, trackingRectThickness, trackingRectThickness);
	_leftTopTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_leftTopTrackingArea];
	
	aRect = NSMakeRect(minX, maxY - trackingRectThickness - vScrollHeight, trackingRectThickness, trackingRectThickness);
	_leftBottomTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_leftBottomTrackingArea];
	
	aRect = NSMakeRect(maxX - trackingRectThickness - hScrollWidth, minY, trackingRectThickness, trackingRectThickness);
	_rightTopTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_rightTopTrackingArea];
	
	aRect = NSMakeRect(maxX - trackingRectThickness - hScrollWidth, maxY - trackingRectThickness - vScrollHeight, trackingRectThickness, trackingRectThickness);
	_rightBottomTrackingArea = [[NSTrackingArea alloc] initWithRect:aRect options:trackingOptions owner:self userInfo:nil];
	[theView addTrackingArea:_rightBottomTrackingArea];
	
//	NSLog(@"(l=%d, t=%d, r=%d, b=%d)", _leftTrackingTag, _topTrackingTag, _rightTrackingTag, _bottomTrackingTag);
}

- (void)removeMouseMovedTrackingRect
{
	if (_mouseMovedTrackingTag != 0)
	{
//		NSLog(@"removing mouse moved rect %d", _mouseMovedTrackingTag);
		[rfbView removeTrackingRect: _mouseMovedTrackingTag];
		_mouseMovedTrackingTag = 0;
		[window setAcceptsMouseMovedEvents: NO];
	}
}

- (void)removeFullscreenTrackingRects
{
	[self endFullscreenScrolling];
	NSView * theView = scrollView;
	if (_leftTrackingArea != 0)
	{
		[theView removeTrackingArea: _leftTrackingArea];
		[_leftTrackingArea release];
		_leftTrackingArea = nil;
	}
	if (_topTrackingArea != 0)
	{
		[theView removeTrackingArea: _topTrackingArea];
		[_topTrackingArea release];
		_topTrackingArea = nil;
	}
	if (_rightTrackingArea != 0)
	{
		[theView removeTrackingArea: _rightTrackingArea];
		[_rightTrackingArea release];
		_rightTrackingArea = nil;
	}
	if (_bottomTrackingArea != 0)
	{
		[theView removeTrackingArea: _bottomTrackingArea];
		[_bottomTrackingArea release];
		_bottomTrackingArea = nil;
	}
	if (_leftTopTrackingArea != 0)
	{
		[theView removeTrackingArea: _leftTopTrackingArea];
		[_leftTopTrackingArea release];
		_leftTopTrackingArea = nil;
	}
	if (_rightTopTrackingArea != 0)
	{
		[theView removeTrackingArea: _rightTopTrackingArea];
		[_rightTopTrackingArea release];
		_rightTopTrackingArea = nil;
	}
	if (_leftBottomTrackingArea != 0)
	{
		[theView removeTrackingArea: _leftBottomTrackingArea];
		[_leftBottomTrackingArea release];
		_leftBottomTrackingArea = nil;
	}
	if (_rightBottomTrackingArea != 0)
	{
		[theView removeTrackingArea: _rightBottomTrackingArea];
		[_rightBottomTrackingArea release];
		_rightBottomTrackingArea = nil;
	}
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	NSTrackingArea * trackingArea = [theEvent trackingArea];
	NSTrackingRectTag trackingNumber = [theEvent trackingNumber];
//	NSLog(@"mouse entered; area=%@, tag = %d", trackingArea, trackingNumber);

	if (trackingNumber == _mouseMovedTrackingTag)
	{
		_wantsMouseMovedOnDrag = NO;
		[window setAcceptsMouseMovedEvents: YES];
	}
	else if (trackingArea == _leftTrackingArea || trackingArea == _rightTrackingArea || trackingArea == _topTrackingArea || trackingArea == _bottomTrackingArea || trackingArea == _leftTopTrackingArea || trackingArea == _leftBottomTrackingArea || trackingArea == _rightTopTrackingArea || trackingArea == _rightBottomTrackingArea)
	{
		[window setAcceptsMouseMovedEvents: YES];
		_currentTrackingArea = trackingArea;
		_wantsMouseMovedOnDrag = YES;
		_autoscrollIncrement = [[PrefController sharedController] fullscreenAutoscrollIncrement];
		
		if (trackingArea == _leftTrackingArea)
		{
			_autoscrollDirection = kAutoscrollLeft;
		}
		else if (trackingArea == _rightTrackingArea)
		{
			_autoscrollDirection = kAutoscrollRight;
		}
		else if (trackingArea == _topTrackingArea)
		{
			_autoscrollDirection = kAutoscrollUp;
		}
		else if (trackingArea == _bottomTrackingArea)
		{
			_autoscrollDirection = kAutoscrollDown;
		}
		else if (trackingArea == _leftTopTrackingArea)
		{
			_autoscrollDirection = kAutoscrollUp | kAutoscrollLeft;
		}
		else if (trackingArea == _rightTopTrackingArea)
		{
			_autoscrollDirection = kAutoscrollUp | kAutoscrollRight;
		}
		else if (trackingArea == _leftBottomTrackingArea)
		{
			_autoscrollDirection = kAutoscrollDown | kAutoscrollLeft;
		}
		else if (trackingArea == _rightBottomTrackingArea)
		{
			_autoscrollDirection = kAutoscrollDown | kAutoscrollRight;
		}
		
		[self beginFullscreenScrolling];
	}
	else
	{
		NSLog(@"mouse entered: unknown tracking tag %d", (int)trackingNumber);
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	NSTrackingArea * trackingArea = [theEvent trackingArea];
	NSTrackingRectTag trackingNumber = [theEvent trackingNumber];
//	NSLog(@"mouse exited, area=%@, tag = %d", trackingArea, trackingNumber);

	_wantsMouseMovedOnDrag = NO;
	if (trackingNumber == _mouseMovedTrackingTag)
	{
		[window setAcceptsMouseMovedEvents: NO];
	}
	else if (trackingArea == _leftTrackingArea || trackingArea == _rightTrackingArea || trackingArea == _topTrackingArea || trackingArea == _bottomTrackingArea || trackingArea == _leftTopTrackingArea || trackingArea == _leftBottomTrackingArea || trackingArea == _rightTopTrackingArea || trackingArea == _rightBottomTrackingArea)
	{
//		[window setAcceptsMouseMovedEvents: NO];
		_currentTrackingArea = nil;
		[self endFullscreenScrolling];
	}
	else
	{
		NSLog(@"mouse exited: unknown tracking tag %d", (int)trackingNumber);
	}
}

//! The purpose of this method is to track the location of the cursor within the autoscroll
//! tracking rects. It computes how far away from the outer edge of the current tracking
//! rect the cursor is. That value is then used to control the autoscroll speed.
//!
//! Unlike -mouseEntered: and -mouseExited:, this method is not invoked automatically
//! by the AppKit. Instead, it is called by the same method in RFBView. This is because
//! mouse moved events messages are not sent for tracking rects by the system.
- (void)mouseMoved:(NSEvent *)theEvent
{
	NSRect scrollRect = [scrollView bounds];
	const float maxX = NSMaxX(scrollRect);
	const float maxY = NSMaxY(scrollRect);
	float scrollWidth = [NSScroller scrollerWidth];
	float trackingRectThickness = [self trackingRectThickness];
	float hScrollWidth = (horizontalScroll ? scrollWidth : 0.0);
	float vScrollHeight = (verticalScroll ? scrollWidth : 0.0);

	// Flip the location to match the tracking rect calculations.
	NSPoint location = [theEvent locationInWindow];
	location.y = maxY - location.y;
	
	// Find how far into the tracking rect the cursor is.
	float inset=0;
	if (_currentTrackingArea == _leftTrackingArea || _currentTrackingArea == _leftTopTrackingArea || _currentTrackingArea == _leftBottomTrackingArea)
	{
		inset = location.x;
	}
	else if (_currentTrackingArea == _rightTrackingArea || _currentTrackingArea == _rightTopTrackingArea || _currentTrackingArea == _rightBottomTrackingArea)
	{
		inset = maxX - hScrollWidth - location.x;
	}
	else if (_currentTrackingArea == _topTrackingArea)
	{
		inset = location.y;
	}
	else if (_currentTrackingArea == _bottomTrackingArea)
	{
		inset = maxY - vScrollHeight - location.y;
	}
	
	// Compute the autoscroll increment based on the inset.
	float maxIncrement = [[PrefController sharedController] fullscreenAutoscrollIncrement];
	_autoscrollIncrement = floor((trackingRectThickness - inset) * maxIncrement / trackingRectThickness);
//	NSLog(@"inset=%g, inc=%g", inset, _autoscrollIncrement);
}

- (void)beginFullscreenScrolling
{
	[self endFullscreenScrolling];
	_autoscrollTimer = [[NSTimer scheduledTimerWithTimeInterval: kAutoscrollInterval
											target: self
										  selector: @selector(scrollFullscreenView:)
										  userInfo: nil repeats: YES] retain];
}

- (void)endFullscreenScrolling
{
	[_autoscrollTimer invalidate];
	[_autoscrollTimer release];
	_autoscrollTimer = nil;
}

- (void)scrollFullscreenView: (NSTimer *)timer
{
	// Bail early if we're not actually scrolling. This shouldn't happen, anyway.
	if (_autoscrollDirection == kAutoscrollNone)
	{
		return;
	}
	
	NSClipView *contentView = [scrollView contentView];
	NSPoint origin = [contentView bounds].origin;
	float autoscrollIncrement = _autoscrollIncrement;

	if (_autoscrollDirection & kAutoscrollLeft)
	{
		origin.x -= autoscrollIncrement;
	}
	if (_autoscrollDirection & kAutoscrollUp)
	{
		origin.y += autoscrollIncrement;
	}
	if (_autoscrollDirection & kAutoscrollRight)
	{
		origin.x += autoscrollIncrement;
	}
	if (_autoscrollDirection & kAutoscrollDown)
	{
		origin.y -= autoscrollIncrement;
	}
	
	[contentView scrollToPoint: [contentView constrainScrollPoint: origin]];
    [scrollView reflectScrolledClipView: contentView];
}

- (BOOL)pasteFromPasteboard:(NSPasteboard*)pb
{
    id types, theType;
	NSString *str;
	
    types = [NSArray arrayWithObjects:NSStringPboardType, NSFilenamesPboardType, nil];
    if((theType = [pb availableTypeFromArray:types]) == nil) {
        NSLog(@"No supported pasteboard type\n");
        return NO;
    }
    str = [pb stringForType:theType];
    if([str isKindOfClass:[NSArray class]]) {
        str = [(id)str objectAtIndex:0];
    }
    
	[_eventFilter pasteString: str];
    return YES;
}

- (void)paste:(id)sender
{
    [self pasteFromPasteboard:[NSPasteboard generalPasteboard]];
}

//! @todo Update this method to work with 10.5 as well. Right now it uses only the 10.6
//!     pasteboard API.
- (void)updateRemotePasteboard
{
    // Don't send any updates if their disabled.
    if (!_connection.sendClientPasteboardUpdates)
    {
        return;
    }
    
    // Only send an update if the pasteboard has changed since last we checked.
    NSPasteboard * pb = [NSPasteboard generalPasteboard];
    int thisChangeCount = [pb changeCount];
    if (thisChangeCount != _generalPasteboardChangeCount)
    {
//        NSLog(@"new pb change count is %d", thisChangeCount);
        _generalPasteboardChangeCount = thisChangeCount;
        
        // Get strings out of the pasteboard.
        NSArray * classes = [NSArray arrayWithObject:[NSString class]];
        NSDictionary * options = [NSDictionary dictionary];
        NSArray * items = [pb readObjectsForClasses:classes options:options];
        
        // If we got back anything, send the first string to the server.
        if (items && [items count])
        {
            NSString * text = [items objectAtIndex:0];
//            NSLog(@"sending client cut text: '%@'", text);
            [_connection.protocol sendClientCutText:text];
        }
    }
}

- (void)sendCmdOptEsc: (id)sender
{
    [_connection sendSpecialKey:kCommandOptionEscapeKeyCombination];
}

- (void)sendCtrlAltDel: (id)sender
{
    [_connection sendSpecialKey:kControlAltDeleteKeyCombination];
}

- (void)sendPauseKeyCode: (id)sender
{
    [_connection sendSpecialKey:kPauseKey];
}

- (void)sendBreakKeyCode: (id)sender
{
    [_connection sendSpecialKey:kBreakKey];
}

- (void)sendPrintKeyCode: (id)sender
{
    [_connection sendSpecialKey:kPrintKey];
}

- (void)sendExecuteKeyCode: (id)sender
{
    [_connection sendSpecialKey:kExecuteKey];
}

- (void)sendInsertKeyCode: (id)sender
{
    [_connection sendSpecialKey:kInsertKey];
}

- (void)sendDeleteKeyCode: (id)sender
{
    [_connection sendSpecialKey:kDeleteKey];
}

- (IBAction)forceReconnect:(id)sender
{
	_autoReconnect = YES;
	[self terminateConnection:@"Forcing Reconnect"];
}

- (void)resetReconnectTimer
{
	[_reconnectTimer invalidate];
	[_reconnectTimer release];
	_reconnectTimer = nil;
}

- (void)startReconnectTimer
{
//	NSLog(@"startReconnectTimer called.\n");
	[self resetReconnectTimer];

    if ( terminating )
        return;
	if ( ! [[PrefController sharedController] autoReconnect] )
		return;
	
	NSTimeInterval timeout = [[PrefController sharedController] intervalBeforeReconnect];
	if ( 0.0 == timeout )
		_autoReconnect = YES;
	else
		_reconnectTimer = [[NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(reconnectTimerTimeout:) userInfo:nil repeats:NO] retain];
}

- (void)reconnectTimerTimeout:(id)sender
{
//	NSLog(@"reconnectTimerTimeout called.\n");
	[self resetReconnectTimer];
	_autoReconnect = YES;
}

- (IBAction)manuallyUpdateFrameBuffer: (id)sender
{
	[_connection.protocol requestFullFrameBufferUpdate];
}

- (IBAction)releaseAllModifierKeys:(id)sender
{
	[_connection releaseAllModifierKeys];
}

@end
