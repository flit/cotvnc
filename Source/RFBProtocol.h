/* RFBProtocol.h created by helmut on Tue 16-Jun-1998 */

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
#import "FrameBufferUpdateReader.h"

#define	MAX_MSGTYPE	rfbServerCutText

@class RFBConnection;
@class NLTStringReader;
@class RFBHandshaker;

/*!
 * \brief Responsible for the RFB protocol at the message level.
 *
 * This class handles incoming messages from the server and routes them to the appropriate
 * ByteReader subclass. The most important of these is the frame buffer update message,
 * handled by FrameBufferUpdateReader. RFBProtocol is itself a ByteReader subclass. Its
 * target object is always the RFBConnection instance.
 *
 * In addition to processing messages from the server, the protocol class handles formatting
 * and sending messages to the server. The most common of these is the frame buffer update
 * request message.
 */
@interface RFBProtocol : ByteReader
{
    RFBConnection * _connection;    //!< Our parent connection instance.
    NSString * serverVersion;
    int serverMajorVersion;
    int serverMinorVersion;
    NLTStringReader * versionReader;
    RFBHandshaker * handshaker;
    id			typeReader;
    id			msgTypeReader[MAX_MSGTYPE + 1];
    BOOL		isStopped;
    BOOL		shouldUpdate;   //!< Whether to request an update after un-stopping.
    BOOL _continueUpdatesWhenComplete;  //!< If true, updates should be continued after the next update completion.
    CARD16		numberOfEncodings;
    CARD32		encodings[16];
    uint16_t _shiftKeyCode;
    uint16_t _controlKeyCode;
    uint16_t _altKeyCode;
    uint16_t _commandKeyCode;
    BOOL _isAppleVNCServer; //!< True if we think the server is Apple VNC (i.e., Apple Remote Desktop).
}

@property(readonly) NSString * serverVersion;
@property(readonly) int serverMinorVersion;
@property(readonly) int serverMajorVersion;
@property(readonly) BOOL isAppleVNCServer;

- (id)initTarget:(id)aTarget;
- (void)setFrameBuffer:(id)aBuffer;

- (void)requestIncrementalFrameBufferUpdateForVisibleRect;
- (void)requestFullFrameBufferUpdate;
- (void)continueUpdate;
- (void)stopUpdate;

- (void)requestUpdate:(NSRect)frame incremental:(BOOL)aFlag;
- (void)setPixelFormat:(rfbPixelFormat*)aFormat;

- (CARD16)numberOfEncodings;
- (CARD32*)encodings;
- (void)changeEncodingsTo:(CARD32*)newEncodings length:(CARD16)l;
- (void)setEncodings;

- (FrameBufferUpdateReader*)frameBufferUpdateReader;

- (void)sendMouse:(NSPoint)thePoint mask:(uint32_t)mask;
- (void)sendModifier:(unsigned int)m pressed: (BOOL)pressed;
- (void)sendKey:(unichar)c pressed:(BOOL)pressed;

//! \brief Sends a key event without translating the keycode.
- (void)sendRawKey:(uint16_t)keycode pressed:(BOOL)isPressed;

//! @brief Sends the client cut text message.
- (void)sendClientCutText:(NSString *)text;

@end

