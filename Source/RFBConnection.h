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

#import <AppKit/AppKit.h>
#import "ByteReader.h"
#import "FrameBuffer.h"
#import "Profile.h"
#import "rfbproto.h"
#import "RFBProtocol.h"
#import "AppDelegate.h"

//! Set to 1 to write an I/O to a file.
#define DUMP_CONNECTION_TO_FILE 0

@class RFBConnectionController;
@class EventFilter;
@class ConnectionMetrics;
@protocol IServerData;

//! Host to use if none is specified.
#define	DEFAULT_HOST	@"localhost"

//! @brief Exception to signal a failure during communications.
extern NSString * const kRFBConnectionException;

//! @brief Types of special keys and key combinations.
enum
{
    kCommandOptionEscapeKeyCombination,
    kControlAltDeleteKeyCombination,
    kPauseKey,
    kBreakKey,
    kPrintKey,
    kExecuteKey,
    kInsertKey,
    kDeleteKey
};

/*!
 * @brief Manages communications with the remote server.
 *
 * Handles all of the network related tasks with talking to the server, from opening the
 * connection to reading and writing data. Also provides an interface for performing remote
 * operations such as sending mouse and keyboard events. The actual message content is
 * handled by an RFBProtocol instance.
 *
 * Each connection object works together with the RFBConnectionController instance associated
 * with it to operate the local display of the remote screen.
 *
 * @sa RFBConnectionController
 * @sa RFBProtocol
 */
@interface RFBConnection : ByteReader
{
    RFBConnectionController * _controller;
    FrameBuffer * frameBuffer;
    RFBProtocol * rfbProtocol;
    NSFileHandle * socketHandler;
	EventFilter * _eventFilter;
    id<IServerData> server_;
    Profile *_profile;
    id currentReader;
    BOOL _isConnected;
    BOOL _didReceiveData;   //!< Set to YES after receiving the first byte from the server.
    BOOL terminating;
    BOOL _readerThreadDidExit;   //!< True when the reader thread has exited.
    NSPoint	_mouseLocation;
	unsigned int _lastMask;
    BOOL updateRequested;	//!< Has someone already requested an update?
    NSString *host;
	float _frameBufferUpdateSeconds;
	NSTimer *_frameUpdateTimer;
    BOOL _hasMaximumFrameBufferUpdates;
	BOOL _hasManualFrameBufferUpdates;
    BOOL _sendClientPasteboardUpdates;  //!< Whether we should send client cut messages.
    ConnectionMetrics * _metrics;   //!< Metrics computer.
    NSRecursiveLock * _writeLock;    //!< Lock to protect writing from multiple threads so messages aren't mixed.
    BOOL _didAuthenticate; //!< Indicates that authentication has succeeded.
    dispatch_queue_t _processQueue; //!< Serial dispatch queue to process incoming data.
    dispatch_queue_t _drawQueue;    //!< Serial dispatch queue to draw from the framebuffer.
    NSCondition * _receivedDataCondition;   //!< Signalled when we first receive data from the server.
    
#if DUMP_CONNECTION_TO_FILE
    int _dump_fd;   //!< File descriptor for data log.
#endif
}

@property(nonatomic, assign) RFBConnectionController * controller;

@property(nonatomic, retain) EventFilter * eventFilter;
@property(nonatomic, retain) FrameBuffer * frameBuffer;
@property(nonatomic, retain) id<IServerData> server;
@property(nonatomic, retain) Profile * profile;
@property(nonatomic, readonly) NSFileHandle * connectionHandle;
@property(nonatomic, readonly) RFBProtocol * protocol;
@property(nonatomic, retain) ConnectionMetrics * metrics;

@property(readonly) BOOL isConnected;
@property(readonly) BOOL didAuthenticate;
@property(readonly) BOOL isTerminating;
@property(nonatomic, retain) NSString * host;
@property(readonly) NSSize displaySize; //!< The full size of the remote display.
@property(readonly) NSRect displayRect; //!< Rect with origin 0,0 and size \a displaySize.
@property(readonly) BOOL sendClientPasteboardUpdates;

- (id)initWithServer:(id<IServerData>)server profile:(Profile*)p;
- (id)initWithFileHandle:(NSFileHandle*)file server:(id<IServerData>)server profile:(Profile*)p;

//! @brief Initiate the connection; start talking to the server.
- (BOOL)connectReturningError:(NSError **)error;

- (void)terminateConnection:(NSString*)aReason;
- (void)connectionHasTerminated;

- (void)setDisplaySize:(NSSize)aSize andPixelFormat:(rfbPixelFormat*)pixf;
- (void)setDisplayName:(NSString*)aName;
- (void)ringBell;

- (void)drawRectFromBuffer:(NSRect)aRect;
- (void)drawRectList:(id)aList;
- (void)pauseDrawing;
- (void)flushDrawing;
- (void)queueUpdateRequest;
- (void)requestFrameBufferUpdate:(id)sender;
- (void)cancelFrameBufferUpdateRequest;
- (float)frameBufferUpdateSeconds;
- (void)setFrameBufferUpdateSeconds: (float)seconds;

- (void)clearAllEmulationStates;
- (void)releaseAllModifierKeys;
- (void)mouseAt:(NSPoint)thePoint buttons:(unsigned int)mask;
- (void)sendSpecialKey:(int)keyType;

- (BOOL)lockForWriting;
- (void)unlockWriteLock;
- (void)writeBytes:(unsigned char*)bytes length:(unsigned int)length;

- (void)setRemoteCursor:(NSCursor *)remoteCursor;

@end
