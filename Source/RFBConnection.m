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

#import <unistd.h>
#import <libc.h>
#import <sys/socket.h>
#import <CoreAudio/HostTime.h>
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
#import "KeyCodes.h"
#import "RFBConnectionController.h"
#import "ConnectionMetrics.h"
#import "BufferPool.h"

//! Maximum number of bytes to read at once.
#define READ_BUF_LEN (256*1024)

NSString * const kRFBConnectionException = @"kRFBConnectionException";

//! Buffer pool shared by all connections.
BufferPool * g_sharedBuffers = nil;

@interface RFBConnection ()

- (void)perror:(NSString*)theAction call:(NSString*)theFunction errorCode:(int)errorCode errorString:(const char *)errorstr error:(NSError **)error;

- (void)_queueUpdateRequest;

- (void)handleBlockException:(NSException *)e;

- (void)readerThread:(NSFileHandle *)fileHandle;

@end

@implementation RFBConnection

@synthesize controller = _controller;
@synthesize eventFilter = _eventFilter;
@synthesize frameBuffer = frameBuffer;
@synthesize server = server_;
@synthesize profile = _profile;
@synthesize connectionHandle = socketHandler;
@synthesize protocol = rfbProtocol;
@synthesize metrics = _metrics;
@synthesize host;
@synthesize isTerminating = terminating;
@synthesize isConnected = _isConnected;
@synthesize sendClientPasteboardUpdates = _sendClientPasteboardUpdates;
@synthesize didAuthenticate = _didAuthenticate;

+ (void)initialize
{
    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithFloat: 0.0], @"FrameBufferUpdateSeconds", nil];
	
	[standardUserDefaults registerDefaults: dict];
}

// mark refactored init methods
- (void)_prepareWithServer:(id<IServerData>)server profile:(Profile*)p
{
    server_ = [server retain];
    _profile = [p retain];
    
    // Set this to true until the thread actually starts.
    _readerThreadDidExit = YES;

    // Set the host string.
    host = [server host];
    if (host == nil)
    {
        host = [DEFAULT_HOST retain];
    }
    else
    {
        [host retain];
    }

    // Create our protocol handler. It sets itself as the current reader.
    rfbProtocol = [[RFBProtocol alloc] initTarget:self];
    
    // Create the metrics object.
    _metrics = [[ConnectionMetrics alloc] init];
    
    // Create the write lock.
    _writeLock = [[NSRecursiveLock alloc] init];
    [_writeLock setName:[NSString stringWithFormat:@"%@ write lock", host]];
    
    // Create the received data condition.
    _receivedDataCondition = [[NSCondition alloc] init];
    
    // Create the operation queue used to process incoming data.
    _processQueue = dispatch_queue_create([[NSString stringWithFormat:@"com.geekspiff.cotvnc.process.%@", host] UTF8String], NULL);
    _drawQueue = dispatch_queue_create([[NSString stringWithFormat:@"com.geekspiff.cotvnc.draw.%@", host] UTF8String], NULL);
    
    // Create the global buffer pool if it doesn't exist yet.
    if (!g_sharedBuffers)
    {
        g_sharedBuffers = [[BufferPool alloc] init];
    }
}

- (id)initWithServer:(id<IServerData>)server profile:(Profile*)p
{
    if (self = [super init])
    {
        [self _prepareWithServer:server profile:p];
	}
    return self;
}

- (id)initWithFileHandle:(NSFileHandle*)file server:(id<IServerData>)server profile:(Profile*)p
{
    if (self = [super init])
    {
        [self _prepareWithServer:server profile:p];
        socketHandler = [file retain];
	}
    return self;
}

- (void)dealloc
{
    NSLog(@"RFBConnection dealloc");
	[self terminateConnection: nil]; // just in case it didn't already get called somehow

    [socketHandler release];
    [_eventFilter release];
    [(id)server_ release];
    [rfbProtocol release];
    [frameBuffer release];
    [_profile release];
    [host release];
    [_metrics release];
    [_writeLock release];
    [_receivedDataCondition release];
    dispatch_release(_processQueue);
    dispatch_release(_drawQueue);
    [super dealloc];
}

//! @brief Creates an error object for a connection failure.
- (void)perror:(NSString*)theAction call:(NSString*)theFunction errorCode:(int)errorCode errorString:(const char *)errorstr error:(NSError **)error
{
    if (error)
    {
        NSString* s = [NSString stringWithFormat:@"%@: %s (%d)", theFunction, errorstr, errorCode];
        
        NSDictionary * info = [NSDictionary dictionaryWithObjectsAndKeys:
            theAction, NSLocalizedDescriptionKey,
            s, NSLocalizedFailureReasonErrorKey,
            nil, nil];
        
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errorCode userInfo:info];
    }
}

//! The reader thread is created after opening a connection to the server.
//!
- (BOOL)connectReturningError:(NSError **)error
{
    // Clear result error, assuming there won't be one.
    *error = NULL;
    
    // Open the socket if we don't already have one.
    if (!socketHandler)
    {
        NSString *actionStr;
        NSString *cause = nil;

        // Fill in hints structure for getaddrinfo.
        struct addrinfo hints = {0};
        hints.ai_flags = AI_NUMERICSERV;
        hints.ai_family = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        
        // Convert port number to a string.
        char portString[8];
        snprintf(portString, sizeof(portString), "%d", [server_ port]);
        
        // Perform the name lookup.
        struct addrinfo * res0;
        int result = getaddrinfo([host UTF8String], portString, &hints, &res0);
        if (result)
        {
            switch (result)
            {
                case EAI_NONAME:
                    actionStr = NSLocalizedString( @"NoNamedServer", nil );
                    break;
                default:
                    actionStr = NSLocalizedString( @"OpenConnection", nil );
            }
            
            [self perror: [NSString stringWithFormat:actionStr, host] call:@"getaddrinfo()" errorCode:result errorString:gai_strerror(result) error:error];
            return NO;
        }
        
        // Iterate over result addresses and try to connect. Exit the loop on the first successful
        // connection.
        int sock = -1;
        struct addrinfo * res;
        for (res = res0; res; res = res->ai_next)
        {
            // Create the socket.
            sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
            if (sock < 0)
            {
                cause = @"socket()";
                continue;
            }

            // Attempt to connect.
            if (connect(sock, res->ai_addr, res->ai_addrlen) < 0)
            {
                cause = @"connect()";
                close(sock);
                sock = -1;
                continue;
            }

            // Exit the loop for the first successful connection.
            break;
        }
        
        // Check if we were able to open a connection.
        if (sock < 0)
        {
            switch (errno)
            {
                case EADDRNOTAVAIL:
                    actionStr = NSLocalizedString( @"NoNamedServer", nil );
                    break;
                default:
                    actionStr = NSLocalizedString( @"NoConnection", nil );
            }
            [self perror: [NSString stringWithFormat:actionStr, host] call:cause errorCode:errno errorString:strerror(errno) error:error];
            freeaddrinfo(res0);
            return NO;
        }

        // Free the result list.
        freeaddrinfo(res0);
        
        // Disable SIGPIPE for this socket. This will cause write() to return an EPIPE error if the
        // other side has disappeared instead of our process receiving a SIGPIPE.
        int set = 1;
        if (setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int)) < 0)
        {
            actionStr = NSLocalizedString( @"OpenConnection", nil );
            [self perror:actionStr call:@"setsockopt()" errorCode:errno errorString:strerror(errno) error:error];
            close(sock);
            return NO;
        }
        
        // Create the file handle from the socket.
        socketHandler = [[NSFileHandle alloc] initWithFileDescriptor:sock closeOnDealloc:YES];
        
        // We're connected now.
        _isConnected = YES;
    }

#if DUMP_CONNECTION_TO_FILE
    _dump_fd = open("data.txt", O_WRONLY | O_CREAT | O_TRUNC | O_NONBLOCK, 0777);
    if (_dump_fd < 0)
    {
        _dump_fd = 0;
        NSLog(@"failed to open dump file (errno = %d)", errno);
    }
#endif

    // Lock the condition variable.
    [_receivedDataCondition lock];

	// Spawn I/O thread.
    _readerThreadDidExit = NO;
    _didReceiveData = NO;
	[NSThread detachNewThreadSelector:@selector(readerThread:) toTarget:self withObject:socketHandler];
    
    // Block until the condition variable is signalled.
    while (!_didReceiveData && !terminating)
    {
        [_receivedDataCondition wait];
    }
    
    [_receivedDataCondition unlock];
    
    return _didReceiveData && !terminating;
}

- (void)ringBell
{
    NSBeep();
}

- (void)setReader:(ByteReader*)aReader
{
    currentReader = aReader;
	[frameBuffer setCurrentReaderIsTight: currentReader && [currentReader isKindOfClass: [TightEncodingReader class]]];
    [aReader resetReader];
}

- (void)setReaderWithoutReset:(ByteReader*)aReader
{
    currentReader = aReader;
}

//! \note This method must be executed on a different thread than the reader thread.
//!
- (void)connectionHasTerminated
{
    NSLog(@"RFBConnection connectionHasTerminated");
    if (_isConnected)
    {
        // Close the connection socket, thus causing the reader thread to exit if it hasn't
        // already noticed the terminating flag.
        NSLog(@"closing socket");
        [socketHandler closeFile];
        
        // No longer connected to the server.
        _isConnected = NO;
        
        // Stop computing metrics.
        [_metrics connectionDidClose];
        
        // Wait for the reader thread to exit.
        while (!_readerThreadDidExit)
        {
            // Run the run loop for a bit to process events.
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        NSLog(@"reader thread did exit");

#if DUMP_CONNECTION_TO_FILE
        // Close the dump file.
        if (_dump_fd)
        {
            close(_dump_fd);
        }
#endif
    }
}

//! We pass the termination request up to our controller object, which will present the
//! user with any necessary alert or dialog. Then any further communication with the server
//! is prevented, queues are flushed, and the remote keyboard is restored to normal.
- (void)terminateConnection:(NSString*)aReason
{
    if (!terminating)
	{
        terminating = YES;
        NSLog(@"RFBConnection terminating connection:%@!", aReason);

        // Stop buffer updates and flush the event queue.
        [self cancelFrameBufferUpdateRequest];
        [rfbProtocol stopUpdate];
        [self releaseAllModifierKeys];
        [self clearAllEmulationStates];
        [_eventFilter synthesizeRemainingEvents];
        [_eventFilter sendAllPendingQueueEntriesNow];
        
        // Tell controller to terminate, but do it on the main thread.
        if (!_controller.isTerminating)
        {
            [_controller performSelectorOnMainThread:@selector(terminateConnection:) withObject:aReason waitUntilDone:NO];
        }
    }
}

//! We receive this message from the RFBProtocol instance when handshaking and authentication
//! has successfully completed. We're given the full size of the remote display and the chosen
//! pixel format so that we can create the frame buffer to hold the remote screen contents.
//! This is also an opportune time to do anything to finish setting up the connection, now that
//! we know the connection is good.
//!
//! @param aSize The size of the remote display.
//! @param pixf The pixel format used to send buffer updates. Our frame buffer has to translate
//!     from this format to the local pixel format.
- (void)setDisplaySize:(NSSize)aSize andPixelFormat:(rfbPixelFormat*)pixf
{
    // Authentication has succeeded when we get this message.
    _didAuthenticate = YES;

    // Create a new framebuffer the size of the remote screen. The prefs controller tells us
    // what class of frame buffer to instantiate based on the local screen depth.
    Class frameBufferClass = [[PrefController sharedController] defaultFrameBufferClass];
    frameBuffer = [[frameBufferClass alloc] initWithSize:aSize andFormat:pixf];
	[frameBuffer setServerMajorVersion: rfbProtocol.serverMajorVersion minorVersion: rfbProtocol.serverMinorVersion];
    _metrics.bytesPerPixel = [frameBuffer bytesPerPixel];
    
    // Set the framebuffer in the protocol object. This in turn sets the framebuffer in the
    // FrameBufferUpdateReader instance it owns.
    [rfbProtocol setFrameBuffer:frameBuffer];
    
    // Set the protocol in the event filter.
    _eventFilter.protocol = rfbProtocol;
    
    // Determine whether we should send client cut messages based on the server version. If the
    // server is Apple VNC then we don't send the messages since they seem to cause the server
    // much trouble. We set this before setting the frame buffer in the controller so the
    // controller can send the clipboard update immediately and not have to wait until the next
    // window key notification.
    _sendClientPasteboardUpdates = !rfbProtocol.isAppleVNCServer;
        
    // Send a full, non-incremental update request to get the entire screen contents.
    [rfbProtocol requestFullFrameBufferUpdate];
    
    // Set the framebuffer in our controller, which will set it in the RFB view and adjust the
    // window and view sizes. The controller takes the remote screen size from the frame buffer's
    // size. The controller will show the window, which will cause an incremental update request
    // to be queued.
    [_controller setFrameBuffer:frameBuffer];
    [_controller startReconnectTimer];
}

- (void)setDisplayName:(NSString*)aName
{
    [_controller setDisplayName:aName];
}

- (NSSize)displaySize
{
    return [frameBuffer size];
}

- (NSRect)displayRect
{
    NSRect r = { { 0, 0 }, [frameBuffer size] };
    return r;
}

- (void)handleBlockException:(NSException *)e
{
    NSString * reason;
    if ([[e name] isEqualToString:kRFBConnectionException])
    {
        reason = [e reason];
    }
    else
    {
        NSLog(@"got unknown exception in block: %@", e);
        reason = [NSString stringWithFormat:NSLocalizedString(@"UnexpectedException", nil), e];
    }
    
    // Execute the terminate method on the main thread so it can wait for us to exit.
    [self performSelectorOnMainThread:@selector(terminateConnection:) withObject:reason waitUntilDone:NO];
}

- (void)drawRectFromBuffer:(NSRect)aRect
{
    dispatch_async(_drawQueue,
        ^{
            NSAutoreleasePool * pool;
            
            @try
            {
                pool = [[NSAutoreleasePool alloc] init];
                
                [_controller.rfbView displayFromBuffer:aRect];
            }
            @catch (NSException * e)
            {
               [self handleBlockException:e];
            }
            @finally
            {
                [pool release];
            }
        });
}

- (void)drawRectList:(id)aList
{
    dispatch_async(_drawQueue,
        ^{
            NSAutoreleasePool * pool;
            
            @try
            {
                pool = [[NSAutoreleasePool alloc] init];
                
                [_controller.rfbView drawRectList:aList];
            }
            @catch (NSException * e)
            {
               [self handleBlockException:e];
            }
            @finally
            {
                [pool release];
            }
        });
}

//! Used to postpone drawing until all the rectangles within one update are
//! decoded and blitted into the frame buffer. Once processing of the update
//! is finished, FrameBufferUpdateReader will call -flushWindow. That method
//! re-enables flushing and flushes immediately.
- (void)pauseDrawing
{
    [_controller pauseDrawing];
}

//! Enables window flushing and flushes all drawing immediately. This method
//! also queues another update request from the server.
- (void)flushDrawing
{
    dispatch_async(_drawQueue,
        ^{
            NSAutoreleasePool * pool;
            
            @try
            {
                pool = [[NSAutoreleasePool alloc] init];
                
                [_controller flushDrawing];
            }
            @catch (NSException * e)
            {
               [self handleBlockException:e];
            }
            @finally
            {
                [pool release];
            }
        });
}

#if DUMP_CONNECTION_TO_FILE
- (void)dumpData:(const void *)data length:(uint32_t)length prefix:(const char *)prefix
{
    if (_dump_fd)
    {
        const uint8_t * byte = (const uint8_t *)data;
        uint32_t remaining = length;
        unsigned prefixLength = strlen(prefix);
        
        while (remaining)
        {
            // Print 16 bytes into a string.
            char lineBytes[128] = {0};
            int lineOffset = 0;
            for (; remaining && lineOffset < 16; byte++, lineOffset++, remaining--)
            {
                const char * lastCharString = (lineOffset < 15 && remaining > 1) ? " " : "\n";
                sprintf(&lineBytes[lineOffset * 3], "%02x%s", *byte, lastCharString);
            }
            
            // Form the full line and write it to the dump file.
            write(_dump_fd, prefix, prefixLength);
            write(_dump_fd, lineBytes, strlen(lineBytes));
        }
    }
}
#endif

- (void)readerThread:(NSFileHandle *)fileHandle
{
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	uint8_t * buf = 0;
	int fd = [fileHandle fileDescriptor];
    NSString * reason;
    
    // Set the thread name.
    [[NSThread currentThread] setName:[NSString stringWithFormat:@"reader:%@", host]];
    
	@try
	{
        _readerThreadDidExit = NO;
        
		// Loop until the connection is closed.
		while (!terminating)
		{
            socklen_t optionLength;
            int socketError = 0;
            ssize_t length = 0;
            
			// Create an autorelease pool for this loop iteration.
			if (pool)
			{
				[pool release];
			}
			pool = [[NSAutoreleasePool alloc] init];
            
            // Wait until there is data available to read. If the socket is closed intentionally
            // from our side, we'll get an EBADF error back from select().
            assert(fd < FD_SETSIZE);
            fd_set readSet;
            fd_set errorSet;
            FD_ZERO(&readSet);
            FD_SET(fd, &readSet);
            FD_COPY(&readSet, &errorSet);
            int nReady = select(fd + 1, &readSet, NULL, &errorSet, NULL);
            
            // Signal the connect thread if this is the first bit of data we've received. We also
            // need to signal the condition if we get an error, so the connect thread doesn't get
            // stuck.
            if (!_didReceiveData)
            {
                [_receivedDataCondition lock];
                _didReceiveData = YES;
                [_receivedDataCondition signal];
                [_receivedDataCondition unlock];
            }

            // Handle error from select().
            if (nReady < 0)
            {
                // Get error from select().
                NSLog(@"error %d from select()", errno);
                socketError = errno;
                goto handle_err;
            }
            assert(nReady == 1);
            
            // Check for an error on the socket.
            if (FD_ISSET(fd, &errorSet))
            {
                // Get the socket error number.
                optionLength = sizeof(socketError);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &optionLength) != 0)
                {
                    // Got an error from getsockopt().
                    NSLog(@"error %d from getsockopt(SO_ERROR)", errno);
                    socketError = errno;
                }
                
                goto handle_err;
            }

            // Get number of available bytes.
            int availableCount;
            optionLength = sizeof(availableCount);
            if (getsockopt(fd, SOL_SOCKET, SO_NREAD, &availableCount, &optionLength) != 0)
            {
                // Got an error from getsockopt().
                NSLog(@"error %d from getsockopt(SO_NREAD)", errno);
                socketError = errno;
                goto handle_err;
            }
//            NSLog(@"[%@] availableCount = %d", host, availableCount);
            
            // Grab a buffer to hold the available data.
            buf = [g_sharedBuffers acquireBufferWithLength:availableCount options:kBufferOptionAllocate];
            
            // Read data from the socket.
            length = read(fd, buf, availableCount);
            
            // Check for an error.
            if (length < 0)
            {
                socketError = errno;
            }
            // The connection was closed if we get an empty read back.
            else if (length == 0)
            {
                @throw [NSException exceptionWithName:kRFBConnectionException reason:NSLocalizedString(@"ServerClosed", nil) userInfo:nil];
            }
            
            // Handle any error that occurred while reading from the socket.
handle_err: if (socketError)
            {
				// If the read timed out, just loop and start again.
				if (errno == ETIMEDOUT)
				{
					continue;
				}
                else if (errno == EBADF && terminating)
                {
                    // The socket was closed because we're terminating, so we don't want to
                    // treat it as an error. Just exit.
                    NSLog(@"socket was closed, exiting reader thread");
                    return;
                }
				
				reason = [NSString stringWithFormat:NSLocalizedString(@"ReadError", nil), errno, [NSString stringWithUTF8String:strerror(errno)]];
				NSLog(@"%@", reason);

                @throw [NSException exceptionWithName:kRFBConnectionException reason:reason userInfo:nil];
			}
			
            // Update metrics.
            if (_metrics)
            {
                [_metrics addBytesReceived:length];
            }
            
#if DUMP_CONNECTION_TO_FILE
            // Write incoming data to the dump file.
            [self dumpData:buf length:length prefix:"<-- "];
#endif
            
            // Put a block to process this chunk of data into this connection's serial dispatch queue.
            dispatch_async(_processQueue,
                ^{
                    NSAutoreleasePool * pool;
                    
                    @try
                    {
                        pool = [[NSAutoreleasePool alloc] init];
                        
                        // Let the current reader object eat up the bytes in this read.
                        uint8_t * bytes = buf;
                        uint32_t remaining = length;
                        while (remaining && !terminating)
                        {
                            unsigned consumed = [currentReader readBytes:bytes length:remaining];
                            remaining -= consumed;
                            bytes += consumed;
                        }
                    }
                    @catch (NSException * e)
                    {
                       [self handleBlockException:e];
                    }
                    @finally
                    {
                        [g_sharedBuffers releaseBuffer:buf];
                        [pool release];
                    }
                });
            
		}
	}
	@catch (NSException * e)
	{
        if ([[e name] isEqualToString:kRFBConnectionException])
        {
            reason = [e reason];
        }
        else
        {
            NSLog(@"got unknown exception in io thread: %@", e);
            reason = [NSString stringWithFormat:NSLocalizedString(@"UnexpectedException", nil), e];
        }
        
        // Execute the terminate method on the main thread so it can wait for us to exit.
        [self performSelectorOnMainThread:@selector(terminateConnection:) withObject:reason waitUntilDone:NO];
	}
	@finally
	{
		if (pool)
		{
			[pool release];
		}
		
		// Make sure the input data buffer gets freed.
//		if (buf)
//		{
//			free(buf);
//		}
        
        // Tell anyone who wants to know that we've finished executing.
        _readerThreadDidExit = YES;
	}
}

- (void)writeBytes:(unsigned char*)bytes length:(unsigned int)length
{
#if DUMP_CONNECTION_TO_FILE
    // Write outgoing data to the dump file.
    [self dumpData:bytes length:length prefix:"--> "];
#endif
            
    int fd = [socketHandler fileDescriptor];
    while (length && !terminating)
	{
        ssize_t result = write(fd, bytes, length);
        if (result >= 0)
		{
            length -= result;
			bytes += result;
            [_metrics addBytesSent:result];
        }
		else
		{
            NSString *reason;
            
            if (errno == EAGAIN)
			{
                continue;
            }
            else if (errno == EPIPE)
			{
				reason = NSLocalizedString( @"ServerClosed", nil );
            }
			else
            {
                reason = NSLocalizedString( @"ServerError", nil );
                reason = [NSString stringWithFormat: reason, strerror(errno)];
            }
            
            // Terminate the connection directly instead of raising an exception, since threads
            // other than the reader thread call this method.
            [self terminateConnection:reason];
        }
    }
}

- (BOOL)lockForWriting
{
    return [_writeLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
}

- (void)unlockWriteLock
{
    [_writeLock unlock];
}

- (void)_queueUpdateRequest
{
    if (!updateRequested)
    {
        updateRequested = TRUE;

		if (_hasMaximumFrameBufferUpdates)
        {
            // If running updates at the maximum rate, request immediately.
			[self requestFrameBufferUpdate: nil];
		}
        else if (!_frameUpdateTimer)
        {
            // Otherwise we create a repeating timer (if the timer is not already created) that
            // will request updates every time it fires. When -setFrameBufferUpdateSeconds: is
            // received the timer is invalidated and potentially recreated at the new frequency.
            _frameUpdateTimer = [[NSTimer timerWithTimeInterval: _frameBufferUpdateSeconds target: self selector: @selector(requestFrameBufferUpdate:) userInfo: nil repeats: YES] retain];
            
            // Add the timer to the main run loop. It is important that this is done explicitly,
            // since this method can run on a different thread from the main thread, such as when
            // a connection is being opened.
            [[NSRunLoop mainRunLoop] addTimer:_frameUpdateTimer forMode:NSRunLoopCommonModes];
        }
    }
}

- (void)queueUpdateRequest
{
	if (!_hasManualFrameBufferUpdates)
    {
		[self _queueUpdateRequest];
    }
}

- (void)requestFrameBufferUpdate:(id)sender
{
	if (terminating)
    {
        return;
    }
    
    updateRequested = FALSE;
	[rfbProtocol requestIncrementalFrameBufferUpdateForVisibleRect];
}

- (void)cancelFrameBufferUpdateRequest
{
	[_frameUpdateTimer invalidate];
	[_frameUpdateTimer release];
	_frameUpdateTimer = nil;
    updateRequested = FALSE;
}

- (float)frameBufferUpdateSeconds
{
	return _frameBufferUpdateSeconds;
}

- (void)setFrameBufferUpdateSeconds: (float)seconds
{
	_frameBufferUpdateSeconds = seconds;
    _hasMaximumFrameBufferUpdates = _frameBufferUpdateSeconds < 0.0001;
	_hasManualFrameBufferUpdates = _frameBufferUpdateSeconds >= [[PrefController sharedController] maxPossibleFrameBufferUpdateSeconds];
    
    // Cancel the update request timer and recreate it.
	[self cancelFrameBufferUpdateRequest];
    [self queueUpdateRequest];	
}

- (void)clearAllEmulationStates
{
	[_eventFilter clearAllEmulationStates];
	_lastMask = 0;
}

- (void)releaseAllModifierKeys
{
	[rfbProtocol sendModifier:NSShiftKeyMask pressed:NO];
	[rfbProtocol sendModifier:NSControlKeyMask pressed:NO];
	[rfbProtocol sendModifier:NSAlternateKeyMask pressed:NO];
	[rfbProtocol sendModifier:NSCommandKeyMask pressed:NO];
}

//! @todo Should this logic be moved into the EventFilter class?
//!
- (void)mouseAt:(NSPoint)thePoint buttons:(unsigned int)mask
{
    NSSize s = [frameBuffer size];
	
    // Limit the point to the remote screen size.
    thePoint.x = MIN(MAX(thePoint.x, 0), s.width - 1);
    thePoint.y = MIN(MAX(thePoint.y, 0), s.height - 1);
    
    // Only send to the server if something has changed.
    if (!NSEqualPoints(_mouseLocation, thePoint) || _lastMask != mask)
    {
        //NSLog(@"here %d", mask);
        _mouseLocation = thePoint;
		_lastMask = mask;
        
        // Flip the y coordinate.
        thePoint.y = s.height - thePoint.y;
        
        // Send the mouse update.
        [rfbProtocol sendMouse:thePoint mask:mask];
    
//        [self queueUpdateRequest];
    }
}

//! @brief Sends one of the special keys or key combinations.
//!
//! The protocol object is used to send the actual raw keycode events.
- (void)sendSpecialKey:(int)keyType
{
    switch (keyType)
    {
        case kCommandOptionEscapeKeyCombination:
            [rfbProtocol sendRawKey:kAltKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kMetaKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kEscapeKeyCode pressed:YES];

            [rfbProtocol sendRawKey:kEscapeKeyCode pressed:NO];
            [rfbProtocol sendRawKey:kMetaKeyCode pressed:NO];
            [rfbProtocol sendRawKey:kAltKeyCode pressed:NO];
            break;

        case kControlAltDeleteKeyCombination:
            [rfbProtocol sendRawKey:kControlKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kAltKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kDeleteKeyCode pressed:YES];

            [rfbProtocol sendRawKey:kDeleteKeyCode pressed:NO];
            [rfbProtocol sendRawKey:kAltKeyCode pressed:NO];
            [rfbProtocol sendRawKey:kControlKeyCode pressed:NO];
            break;

        case kPauseKey:
            [rfbProtocol sendRawKey:kPauseKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kPauseKeyCode pressed:NO];
            break;

        case kBreakKey:
            [rfbProtocol sendRawKey:kBreakKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kBreakKeyCode pressed:NO];
            break;

        case kPrintKey:
            [rfbProtocol sendRawKey:kPrintKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kPrintKeyCode pressed:NO];
            break;

        case kExecuteKey:
            [rfbProtocol sendRawKey:kExecuteKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kExecuteKeyCode pressed:NO];
            break;

        case kInsertKey:
            [rfbProtocol sendRawKey:kInsertKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kInsertKeyCode pressed:NO];
            break;

        case kDeleteKey:
            [rfbProtocol sendRawKey:kDeleteKeyCode pressed:YES];
            [rfbProtocol sendRawKey:kDeleteKeyCode pressed:NO];
            break;
            
        default:
            NSLog(@"unknown key type: %d", keyType);
    }
}

- (void)setRemoteCursor:(NSCursor *)remoteCursor
{
	[_controller.rfbView setRemoteCursor:remoteCursor];
}
	
@end
