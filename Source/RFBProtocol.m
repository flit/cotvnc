/* RFBProtocol.m created by helmut on Tue 16-Jun-1998 */

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

#import "RFBProtocol.h"
#import "CARD8Reader.h"
#import "FrameBuffer.h"
#import "FrameBufferUpdateReader.h"
#import "PrefController.h"
#import "Profile.h"
#import "RFBServerInitReader.h"
#import "RFBConnection.h"
#import "ServerCutTextReader.h"
#import "SetColorMapEntriesReader.h"
#import "NLTStringReader.h"
#import "RFBHandshaker.h"
#import "KeyCodes.h"
#import "ConnectionMetrics.h"

@interface RFBProtocol ()

- (void)setServerVersion:(NSString*)aVersion;
- (void)start:(ServerInitMessage*)info;

@end

@implementation RFBProtocol

@synthesize serverVersion, serverMajorVersion, serverMinorVersion;
@synthesize isAppleVNCServer = _isAppleVNCServer;

- (id)initTarget:(id)aTarget
{
    if (self = [super initTarget:aTarget action:NULL])
    {
        // Our target is always the connection object.
        assert([aTarget isKindOfClass:[RFBConnection class]]);
        _connection = aTarget;
        
        // Get key codes from the profile.
        Profile * profile = _connection.profile;
        _shiftKeyCode = [profile shiftKeyCode];
        _controlKeyCode = [profile controlKeyCode];
        _altKeyCode = [profile altKeyCode];
        _commandKeyCode = [profile commandKeyCode];
        
        // Create readers for initial handshaking.
        versionReader = [[NLTStringReader alloc] initTarget:self action:@selector(setServerVersion:)];
        handshaker = [[RFBHandshaker alloc] initTarget:self action:@selector(start:)];
        handshaker.connection = _connection;

        // The RFB protocol starts with the server sending its version.
        [target setReader:versionReader];

        // Create message reader objects.
		typeReader = [[CARD8Reader alloc] initTarget:self action:@selector(receiveType:)];
		msgTypeReader[rfbFramebufferUpdate] = [[FrameBufferUpdateReader alloc] initTarget:self action:@selector(frameBufferUpdateComplete:)];
		msgTypeReader[rfbSetColourMapEntries] = [[SetColorMapEntriesReader alloc] initTarget:self action:@selector(setColormapEntries:)];
		msgTypeReader[rfbBell] = nil;
		msgTypeReader[rfbServerCutText] = [[ServerCutTextReader alloc] initTarget:self action:@selector(serverCutText:)];
	}
    return self;
}

- (void)dealloc
{
    [typeReader release];
    [versionReader release];
    [handshaker release];
    
    int i;
    for(i=0; i<=MAX_MSGTYPE; i++)
    {
        [msgTypeReader[i] release];
    }
    [super dealloc];
}

//! The next action in the open connection sequence is -start:.
- (void)setServerVersion:(NSString*)aVersion
{
    serverVersion = [aVersion copy];
	sscanf([serverVersion UTF8String], rfbProtocolVersionFormat, &serverMajorVersion, &serverMinorVersion);
	
    NSLog(@"Server reports Version %@", aVersion);
    
	// ARD sends this bogus 889 version#, at least for ARD 2.2 they actually comply with version
    // 003.007 so we'll force that.
	if (serverMinorVersion == 889)
    {
		NSLog(@"\tBogus RFB Protocol Version Number from AppleRemoteDesktop, switching to protocol 003.007");
		serverMinorVersion = 7;
        _isAppleVNCServer = YES;
	}
	
    // Next step is the authentication and hello handshake.
    [target setReader:handshaker];
}

//! Tell the connection what the remote display size and name is.
- (void)start:(ServerInitMessage*)info
{
    rfbPixelFormat myFormat;
    memcpy(&myFormat, (rfbPixelFormat*)[info pixelFormatData], sizeof(myFormat));
    [self setPixelFormat:&myFormat];
    [self setEncodings];

    [target setReader:typeReader];
    
    // Let the connection know we're finished handshaking and authentication, and update it with
    // the remote display information.
    [_connection setDisplaySize:[info size] andPixelFormat:&myFormat];
    [_connection setDisplayName:[info name]];
}

- (CARD16)numberOfEncodings
{
    return numberOfEncodings;
}

- (CARD32*)encodings
{
    return encodings;
}

- (void)changeEncodingsTo:(CARD32*)newEncodings length:(CARD16)l
{
    int i;
    rfbSetEncodingsMsg msg;
    CARD32	enc[64];

    if ([_connection lockForWriting])
    {
        numberOfEncodings = l;
        msg.type = rfbSetEncodings;
        msg.nEncodings = htons(l);
        [_connection writeBytes:(unsigned char*)&msg length:sizeof(msg)];
        for(i=0; i<l; i++) {
            encodings[i] = newEncodings[i];
            enc[i] = htonl(encodings[i]);
        }
        [_connection writeBytes:(unsigned char*)&enc length:numberOfEncodings * sizeof(CARD32)];
        [_connection unlockWriteLock];
    }
}

- (void)setEncodings
{
    Profile* profile = [target profile];
    CARD16 i, l = [profile numberOfEnabledEncodings];
    CARD32	enc[64];

    for(i=0; i<l; i++) {
        enc[i] = [profile encodingAtIndex:i];
    }
    [self changeEncodingsTo:enc length:l];
}

- (void)requestUpdate:(NSRect)frame incremental:(BOOL)aFlag
{
    // Update metrics.
    [_connection.metrics addUpdateRequest];
    
    if ([_connection lockForWriting])
    {
        rfbFramebufferUpdateRequestMsg	msg;

        msg.type = rfbFramebufferUpdateRequest;
        msg.incremental = aFlag;
        msg.x = frame.origin.x; msg.x = htons(msg.x);
        msg.y = frame.origin.y; msg.y = htons(msg.y);
        msg.w = frame.size.width; msg.w = htons(msg.w);
        msg.h = frame.size.height; msg.h = htons(msg.h);
        [_connection writeBytes:(unsigned char*)&msg length:sz_rfbFramebufferUpdateRequestMsg];
        
        [_connection unlockWriteLock];
    }
    
    // If not incremental, then we want to hold off on further updates until this update
    // is finished.
    if (!aFlag)
    {
        isStopped = YES;
        _continueUpdatesWhenComplete = YES;
    }
}

- (void)setPixelFormat:(rfbPixelFormat*)aFormat
{
    Profile* profile = [target profile];
    rfbSetPixelFormatMsg	msg;

    msg.type = rfbSetPixelFormat;
    aFormat->trueColour = YES;
    if([profile useServerNativeFormat]) {
        if(!aFormat->redMax || !aFormat->bitsPerPixel) {
            NSLog(@"Server proposes invalid format: redMax = %d, bitsPerPixel = %d, using local format",
                  aFormat->redMax, aFormat->bitsPerPixel);
            [[PrefController sharedController] getLocalPixelFormat:aFormat];
            aFormat->bigEndian = [FrameBuffer bigEndian];
        }
    } else {
       	[profile getPixelFormat:aFormat];
        aFormat->bigEndian = [FrameBuffer bigEndian];
    }

    NSLog(@"Transport Pixelformat:");
    NSLog(@"\ttrueColor = %s", aFormat->trueColour ? "YES" : "NO");
    NSLog(@"\tbigEndian = %s", aFormat->bigEndian ? "YES" : "NO");
    NSLog(@"\tbitsPerPixel = %d", aFormat->bitsPerPixel);
    NSLog(@"\tdepth = %d", aFormat->depth);
    NSLog(@"\tmaxValue(r/g/b) = (%d/%d/%d)", aFormat->redMax, aFormat->greenMax, aFormat->blueMax);
    NSLog(@"\tshift(r/g/b) = (%d/%d/%d)", aFormat->redShift, aFormat->greenShift, aFormat->blueShift);
    
    memcpy(&msg.format, aFormat, sizeof(rfbPixelFormat));
    msg.format.redMax = htons(msg.format.redMax);
    msg.format.greenMax = htons(msg.format.greenMax);
    msg.format.blueMax = htons(msg.format.blueMax);

    if ([_connection lockForWriting])
    {
        [_connection writeBytes:(unsigned char*)&msg length:sz_rfbSetPixelFormatMsg];
        [_connection unlockWriteLock];
    }
}

- (FrameBufferUpdateReader*)frameBufferUpdateReader
{
    return msgTypeReader[rfbFramebufferUpdate];
}

- (void)setFrameBuffer:(id)aBuffer
{
    [msgTypeReader[rfbFramebufferUpdate] setFrameBuffer:aBuffer];
}

- (void)frameBufferUpdateComplete:(id)aReader
{
	[target setReader:self];
//	[target queueUpdateRequest];
    
    if (isStopped && _continueUpdatesWhenComplete)
    {
        _continueUpdatesWhenComplete = NO;
        [self continueUpdate];
    }
}

- (void)requestIncrementalFrameBufferUpdateForVisibleRect
{
    if (isStopped)
    {
        shouldUpdate = YES;
        return;
    }
    
    #define UPDATE_REQUEST_COUNT 1
    for (int i=0; i < UPDATE_REQUEST_COUNT; ++i)
    {
        [self requestUpdate:[_connection.controller visibleRect] incremental:YES];
    }
}

- (void)requestFullFrameBufferUpdate
{
    if (isStopped)
    {
        shouldUpdate = YES;
        return;
    }
    
    [self requestUpdate:[_connection displayRect] incremental:NO];
}

- (void)setColormapEntries:(id)aReader
{
    [target setReader:self];
}

- (void)serverCutText:(NSString*)aText
{
    [target setReader:self];
}

- (void)resetReader
{
    [target setReader:typeReader];
}

- (void)receiveType:(NSNumber*)type
{
    unsigned t = [type unsignedIntValue];

    if(t > MAX_MSGTYPE) {
		NSString *errorStr = NSLocalizedString( @"UnknownMessageType", nil );
		errorStr = [NSString stringWithFormat:errorStr, type];
        @throw [NSException exceptionWithName:kRFBConnectionException reason:errorStr userInfo:nil];
    } else if(t == rfbBell) {
        [target ringBell];
        [target setReader:self];
    } else {
        [target setReader:(msgTypeReader[t])];
    }
}

- (void)continueUpdate
{
    if (isStopped)
    {
        // Don't actually continue updates if we're stopped waiting for the next update to finish.
        if (_continueUpdatesWhenComplete)
        {
            return;
        }
        
        isStopped = NO;
        if (shouldUpdate)
        {
            [self requestIncrementalFrameBufferUpdateForVisibleRect];
            shouldUpdate = NO;
        }
    }
}

- (void)stopUpdate
{
    if(!isStopped) {
        isStopped = YES;
    }
}

- (void)sendMouse:(NSPoint)thePoint mask:(uint32_t)mask
{
    rfbPointerEventMsg msg;
    msg.type = rfbPointerEvent;
    msg.buttonMask = mask;
    msg.x = htons(thePoint.x);
    msg.y = htons(thePoint.y);
    
    if ([_connection lockForWriting])
    {
        [_connection writeBytes:(unsigned char*)&msg length:sizeof(msg)];
        [_connection unlockWriteLock];
    }
}

- (void)sendModifier:(unsigned int)m pressed: (BOOL)pressed
{
/*	NSString *modifierStr =nil;
	switch (m)
	{
		case NSShiftKeyMask:
			modifierStr = @"NSShiftKeyMask";		break;
		case NSControlKeyMask:
			modifierStr = @"NSControlKeyMask";		break;
		case NSAlternateKeyMask:
			modifierStr = @"NSAlternateKeyMask";	break;
		case NSCommandKeyMask:
			modifierStr = @"NSCommandKeyMask";		break;
		case NSAlphaShiftKeyMask:
			modifierStr = @"NSAlphaShiftKeyMask";	break;
	}
	NSLog(@"modifier %@ %s", modifierStr, pressed ? "pressed" : "released"); */
	
    uint16_t kc;
    if( NSShiftKeyMask == m )
        kc = _shiftKeyCode;
	else if( NSControlKeyMask == m )
        kc = _controlKeyCode;
	else if( NSAlternateKeyMask == m )
        kc = _altKeyCode;
	else if( NSCommandKeyMask == m )
        kc = _commandKeyCode;
    else if(NSAlphaShiftKeyMask == m)
        kc = CAPSLOCK;
    else if(NSHelpKeyMask == m)		// this is F1
        kc = F1_KEYCODE;
	else //if (NSNumericPadKeyMask == m) // don't know how to handle, eat it
		return;
	
    [self sendRawKey:kc pressed:pressed];
}

- (void)sendKey:(unichar)c pressed:(BOOL)pressed
{
    uint16_t kc;
	if(c < 256) {
        kc = k_page_0[c & 0xff];
    } else if((c & 0xff00) == 0xf700) {
        kc = k_page_f7[c & 0xff];
    } else {
		kc = c;
    }

/*	unichar _kc = (unichar)kc;
	NSString *keyStr = [NSString stringWithCharacters: &_kc length: 1];
	NSLog(@"key '%@' %s", keyStr, pressed ? "pressed" : "released"); */

    [self sendRawKey:kc pressed:pressed];
}

//! However, the key code is swizzled into network byte order if necessary.
//!
- (void)sendRawKey:(uint16_t)keycode pressed:(BOOL)isPressed
{
    rfbKeyEventMsg msg = {
        .type = rfbKeyEvent,
        .down = isPressed,
        .key = htonl(keycode)
    };

    if ([_connection lockForWriting])
    {
        [_connection writeBytes:(unsigned char*)&msg length:sizeof(msg)];
        [_connection unlockWriteLock];
    }
}

- (void)sendClientCutText:(NSString *)text
{
    NSData * encodedText = [text dataUsingEncoding:NSWindowsCP1252StringEncoding allowLossyConversion:YES];
    unsigned len = [encodedText length];
    rfbClientCutTextMsg msg = { 0 };
    msg.type = rfbClientCutText;
	msg.length = htonl(len);
    
    if ([_connection lockForWriting])
    {
        [_connection writeBytes:(unsigned char *)&msg length:sizeof(msg)];
        [_connection writeBytes:(unsigned char *)[encodedText bytes] length:len];
        [_connection unlockWriteLock];
    }
}

@end

