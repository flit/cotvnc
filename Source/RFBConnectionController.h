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
#import "ByteReader.h"
#import "FrameBuffer.h"
#import "Profile.h"

@class EventFilter;
@class RFBView;
@class RFBConnectionManager;
@class RFBConnection;
@class RFBConnectionInfoController;
@protocol IServerData;
@protocol RFBConnectionCompleting;

// jason added the following constants for fullscreen display
#define kTrackingRectThicknessFullscreen	60.0
#define kTrackingRectThicknessWindowed		60.0
#define kAutoscrollInterval			0.05

//! \brief Autoscroll direction bitmasks.
enum AutoscrollBitmasks
{
	kAutoscrollNone = 0,
	kAutoscrollLeft = 1,
	kAutoscrollRight = 2,
	kAutoscrollUp = 4,
	kAutoscrollDown = 8
};

//! \brief Transitions used for next/prev connection.
enum TransitionDirection
{
    kTransitionLeftToRight, //!< Move new connection onto screen from the left.
    kTransitionRightToLeft  //!< Move new connection onto screen from the right.
};

//! \brief Type for the transition direction.
typedef enum TransitionDirection TransitionDirection_t;

/*!
 * \brief Manages the UI part of an individual connection.
 *
 * One of the most important methods during connection establishment is -setFrameBuffer:. It
 * is sent from the connection object once basic information has been exchanged with the server
 * and the connection was able to create the frame buffer. This method is responsible for
 * sizing the window and view and showing the window, among other things.
 *
 * \sa RFBConnection
 */
@interface RFBConnectionController : NSObject <NSWindowDelegate>
{
    // From RFBConnection.nib
    IBOutlet RFBView * rfbView;
    IBOutlet NSWindow * window;
    IBOutlet NSScrollView * scrollView;

    // From SetTitle.nib
    IBOutlet id newTitleField;
    IBOutlet NSPanel *newTitlePanel;
    
    // From OpeningConnection.xib
    IBOutlet NSPanel * _openingConnectionPanel;
    IBOutlet id _cancelButton;
    IBOutlet id _openingConnectionText;
    IBOutlet id _openingConnectionProgress;
    
    NSTimer * _connectTimer;
    BOOL _didConnect;
    RFBConnectionManager * _manager;
    RFBConnection * _connection;    //!< Underlying connection object.
    Profile *_profile;              //!< The profile used for the connection.
    EventFilter * _eventFilter;
    id<IServerData> _server;    //!< Information about the remote server.
    NSString *titleString;
    BOOL terminating;
    NSSize _maxSize;
    BOOL horizontalScroll;
    BOOL verticalScroll;
    NSString *realDisplayName;
    NSTimer *_reconnectTimer;
	BOOL _autoReconnect;
	BOOL _isFullscreen;
	NSRect _windowedFrame;
	unsigned int _styleMask;
	NSTrackingArea * _leftTrackingArea;
	NSTrackingArea * _topTrackingArea;
	NSTrackingArea * _rightTrackingArea;
	NSTrackingArea * _bottomTrackingArea;
	NSTrackingArea * _leftTopTrackingArea;
	NSTrackingArea * _rightTopTrackingArea;
	NSTrackingArea * _leftBottomTrackingArea;
	NSTrackingArea * _rightBottomTrackingArea;
	NSTrackingArea * _currentTrackingArea;
	unsigned _autoscrollDirection;	//!< Mask of current direction being scrolled.
	NSTimer *_autoscrollTimer;
	NSTrackingRectTag _mouseMovedTrackingTag;
	float _autoscrollIncrement;	//!< Amount to autoscroll each step.
	BOOL _wantsMouseMovedOnDrag;
    int _generalPasteboardChangeCount;  //!< Last known change count for the general pasteboard.
    RFBConnectionInfoController * _infoWindow;  //!< Window controller for the connection info window.
}

@property(nonatomic, retain) NSWindow * window;
@property(nonatomic, retain) NSScrollView * scrollView;
@property(nonatomic, retain) RFBView * rfbView;

@property(nonatomic, readonly) RFBConnectionManager * manager;
@property(nonatomic, retain) RFBConnection * connection;
@property(nonatomic, retain) Profile * profile;
@property(nonatomic, retain) id<IServerData> server;
@property(nonatomic, retain) EventFilter * eventFilter;

@property(readonly) BOOL isTerminating;
@property(readonly) BOOL isFullscreen;
@property(readonly) BOOL isViewOnly;
@property(readonly) BOOL isConnectionShared;
@property(readonly) NSRect visibleRect;
@property(nonatomic, readonly) NSString * realDisplayName;

//! \brief Tells view whether to pass mouse moved events to us.
@property(readonly) BOOL wantsMouseMovedOnDrag;

- (id)initWithServer:(id<IServerData>)server profile:(Profile*)p owner:(id)owner;
- (id)initWithFileHandle:(NSFileHandle*)file server:(id<IServerData>)server profile:(Profile*)p owner:(id)owner;

//! \brief Initiate the connection; start talking to the server.
- (void)connectWithCompletionTarget:(id<RFBConnectionCompleting>)target;

//! \brief The connection sends this once the framebuffer has been created so we can finish setting up windows and views.
- (void)setFrameBuffer:(FrameBuffer *)framebuffer;

//! \brief Close the connection.
- (void)terminateConnection:(NSString*)aReason;

- (void)paste:(id)sender;
- (BOOL)pasteFromPasteboard:(NSPasteboard*)pb;
- (void)updateRemotePasteboard;

- (void)openNewTitlePanel:(id)sender;
- (void)setNewTitle:(id)sender;
- (void)setDisplayName:(NSString*)aName;

- (IBAction)openOptions:(id)sender;

- (IBAction)cancelConnect:(id)sender;

- (void)pauseDrawing;
- (void)flushDrawing;

- (void)windowDidBecomeKey:(NSNotification *)aNotification;
- (void)windowDidResignKey:(NSNotification *)aNotification;
- (void)windowDidDeminiaturize:(NSNotification *)aNotification;
- (void)windowDidMiniaturize:(NSNotification *)aNotification;
- (void)windowWillClose:(NSNotification *)aNotification;
- (void)windowDidResize:(NSNotification *)aNotification;
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedFrameSize;

- (IBAction)toggleFullscreenMode: (id)sender;
- (IBAction)makeConnectionWindowed: (id)sender;
- (IBAction)makeConnectionFullscreen: (id)sender;

- (IBAction)manuallyUpdateFrameBuffer: (id)sender;

- (IBAction)releaseAllModifierKeys:(id)sender;

//! \brief Replaces the current fullscreen connection with the receiver.
- (void)takeFullscreenFromConnection:(RFBConnectionController *)fromConnection direction:(TransitionDirection_t)direction;

- (void)installMouseMovedTrackingRect;
- (void)installFullscreenTrackingRects;
- (void)removeFullscreenTrackingRects;
- (void)removeMouseMovedTrackingRect;
- (float)trackingRectThickness;
- (void)mouseEntered:(NSEvent *)theEvent;
- (void)mouseExited:(NSEvent *)theEvent;
- (void)mouseMoved:(NSEvent *)theEvent;
- (void)beginFullscreenScrolling;
- (void)endFullscreenScrolling;
- (void)scrollFullscreenView: (NSTimer *)timer;

// For autoReconnect
- (void)resetReconnectTimer;
- (void)startReconnectTimer;
- (void)reconnectTimerTimeout:(id)sender;

- (IBAction)forceReconnect:(id)sender;

- (void)sendCmdOptEsc: (id)sender;
- (void)sendCtrlAltDel: (id)sender;
- (void)sendPauseKeyCode: (id)sender;
- (void)sendBreakKeyCode: (id)sender;
- (void)sendPrintKeyCode: (id)sender;
- (void)sendExecuteKeyCode: (id)sender;
- (void)sendInsertKeyCode: (id)sender;
- (void)sendDeleteKeyCode: (id)sender;

@end

/*!
 * \brief Protocol for handling connection notifications.
 */
@protocol RFBConnectionCompleting

- (void)connection:(RFBConnectionController *)connection didCompleteWithStatus:(BOOL)status;

@end

