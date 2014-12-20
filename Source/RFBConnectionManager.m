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

#import "KeyChain.h"
#import "RFBConnectionManager.h"
#import "RFBConnection.h"
#import "PrefController.h"
#import "ProfileManager.h"
#import "Profile.h"
#import "rfbproto.h"
#import "vncauth.h"
#import "ServerDataViewController.h"
#import "ServerFromPrefs.h"
#import "ServerFromRendezvous.h"
#import "ServerStandAlone.h"
#import "ServerDataManager.h"
#import "RFBConnectionController.h"

id g_sharedConnectionManager = nil;

@interface RFBConnectionManager ()

- (void)connectSelectedServer:(id)sender;

@end

@implementation RFBConnectionManager

+ (id)sharedManager
{ 
	if ( ! g_sharedConnectionManager )
	{
		g_sharedConnectionManager = [[self alloc] initWithWindowNibName: @"ConnectionDialog"];
		NSParameterAssert( g_sharedConnectionManager != nil );
		
		[g_sharedConnectionManager wakeup];
		
		[[NSNotificationCenter defaultCenter] addObserver:g_sharedConnectionManager
												 selector:@selector(applicationWillTerminate:)
													 name:NSApplicationWillTerminateNotification object:NSApp];
	}
	return g_sharedConnectionManager;
}

//! Terminate all connections. We do this explicitly, even though NSApp will close all open
//! windows for us, to prevent an issue caused by the order of objects being released. Because
//! we get this app termination notification before all windows are closed, the connections
//! are released when we release the connections list due to releasing ourself. That leaves only
//! each connections' auto reconnect timer holding a retain on its connection. When the
//! connection's window is closed, it releases the timer, which releases the connection, which
//! wants to remove itself from the connections list, so bang!. Thus we have this solution, for
//! the time being. There's got to be a nicer way.
- (void)applicationWillTerminate:(NSNotification *)notification
{
    _isTerminating = YES;
    
    // We don't just iterate over the connection list because each connection will remove
    // itself from the connection list, thus mutating the array while enumerating.
    RFBConnectionController * connection = [connections lastObject];
    while ([connections count])
    {
        [connection terminateConnection:nil];
        connection = [connections lastObject];
    }

	[self release];
}

- (void)reloadServerArray
{
    NSEnumerator *serverEnumerator = [[ServerDataManager sharedInstance] getServerEnumerator];
	id<IServerData> server;
	
	[mOrderedServerNames removeAllObjects];
	while ( server = [serverEnumerator nextObject] )
	{
		[mOrderedServerNames addObject:[server name]];
	}
	
	[mOrderedServerNames sortUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (void)wakeup
{
	// make sure our window is loaded
	@try
    {
		[self window];
		[self setWindowFrameAutosaveName: @"login"];
	}
	@catch (NSException * e)
    {
		NSLog(@"exception = %@", e);
	}
//	mDisplayGroups = NO;
	mLaunchedByURL = NO;
	
    // The .nib shows the server pane by default.
    _isServerPaneVisible = YES;
    
	mOrderedServerNames = [[NSMutableArray alloc] init];
	[self reloadServerArray];
	
	mServerCtrler = [[ServerDataViewController alloc] init];
	[mServerCtrler setConnectionDelegate:self];

    sigblock(sigmask(SIGPIPE));
    connections = [[NSMutableArray alloc] init];
    [[ProfileManager sharedManager] wakeup];
    
	NSBox *serverCtrlerBox = [mServerCtrler box];
	[serverCtrlerBox retain];
	[serverCtrlerBox removeFromSuperview];
	
    // figure out whether the size has changed in order to ease localization
//    NSSize originalSize = [serverDataBoxLocal frame].size;
//    NSSize newSize = [serverCtrlerBox frame].size;
//    NSSize deltaSize = NSMakeSize( newSize.width - originalSize.width, newSize.height - originalSize.height );
    
	// I'm hardcoding the border so that I can use a real border at design time so it can be seen easily
	[serverDataBoxLocal setBorderType:NSNoBorder];
//    [serverDataBoxLocal setFrameSize: newSize];
	[serverDataBoxLocal setContentView:serverCtrlerBox];
	[serverCtrlerBox release];
	
    // resize our window if necessary
//    NSWindow *window = [serverDataBoxLocal window];
//    NSRect oldFrame = [window frame];
//    NSSize newFrameSize = {oldFrame.size.width + deltaSize.width, oldFrame.size.height + deltaSize.height };
//    NSRect newFrame = { oldFrame.origin, newFrameSize };
//    NSView *contentView = [window contentView];
//    BOOL didAutoresize = [contentView autoresizesSubviews];
//    [contentView setAutoresizesSubviews: NO];
//    [window setFrame: newFrame display: NO];
//    [contentView setAutoresizesSubviews: didAutoresize];

    [serverList setDoubleAction:@selector(connectSelectedServer:)];
    [serverList setTarget:self];

	[self useRendezvous: [[PrefController sharedController] usesRendezvous]];
    
    // Restore the server pane to the way it was in the last session.
    _isServerPaneVisible = [[NSUserDefaults standardUserDefaults] boolForKey:@"isServerPaneVisible"];
    
    // Hide the server pane if it was not visible last session. The window is already the correct
    // size, we just have to adjust the server list width and server editor pane position.
    if (!_isServerPaneVisible)
    {
        NSRect windowFrame = [[self window] frame];
        
        NSRect newListFrame = [serverListBox frame];
        newListFrame.size.width = windowFrame.size.width;
        
        NSRect newEditorFrame = [serverDataBoxLocal frame];
        newEditorFrame.origin.x = NSMaxX(newListFrame) + 20.0;
        
        [serverListBox setFrame:newListFrame];
        [serverDataBoxLocal setFrame:newEditorFrame];
        
        [toggleServerEditButton setImage:[NSImage imageNamed:@"NSGoRightTemplate"]];
    }
}

- (BOOL)runFromCommandLine
{
    NSProcessInfo *procInfo = [NSProcessInfo processInfo];
    NSArray *args = [procInfo arguments];
    int i, argCount = [args count];
    NSString *arg;
	
	ServerFromPrefs* cmdlineServer = [[[ServerFromPrefs alloc] init] autorelease];
	Profile* profile = nil;
	ProfileManager *profileManager = [ProfileManager sharedManager];
	
	// Check our arguments.  Args start at 0, which is the application name
	// so we start at 1.  arg count is the number of arguments, including
	// the 0th argument.
    for (i = 1; i < argCount; i++)
	{
		arg = [args objectAtIndex:i];
		
		if ([arg hasPrefix:@"-psn"])
		{
			// Called from the finder.  Do nothing.
			continue;
		} 
		else if ([arg hasPrefix:@"--PasswordFile"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			NSString *passwordFile = [args objectAtIndex:++i];
			char *decrypted_password = vncDecryptPasswdFromFile((char*)[passwordFile UTF8String]);
			if (decrypted_password == NULL)
			{
				NSLog(@"Cannot read password from file.");
				exit(1);
			} 
			else
			{
				[cmdlineServer setPassword: [NSString stringWithCString:decrypted_password encoding:NSASCIIStringEncoding]];
				free(decrypted_password);
			}
		}
		else if ([arg hasPrefix:@"--FullScreen"])
			[cmdlineServer setFullscreen: YES];
		else if ([arg hasPrefix:@"--ViewOnly"])
			[cmdlineServer setViewOnly: YES];
		else if ([arg hasPrefix:@"--Display"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			int display = [[args objectAtIndex:++i] intValue];
			[cmdlineServer setDisplay: display];
		}
		else if ([arg hasPrefix:@"--Profile"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			NSString *profileName = [args objectAtIndex:++i];
			if ( ! [profileManager profileWithNameExists: profileName] )
			{
				NSLog(@"Cannot find a profile with the given name: \"%@\".", profileName);
				exit(1);
			}
			profile = [profileManager profileNamed: profileName];
		}
		else if ([arg hasPrefix:@"-"])
			[self cmdlineUsage];
		else if ([arg hasPrefix:@"-?"] || [arg hasPrefix:@"-help"] || [arg hasPrefix:@"--help"])
			[self cmdlineUsage];
		else
		{
			[cmdlineServer setHostAndPort: arg];
			
			mRunningFromCommandLine = YES;
		} 
    }
	
	if ( mRunningFromCommandLine )
	{
		if ( nil == profile )
			profile = [profileManager defaultProfile];	
		[self createConnectionWithServer:cmdlineServer profile:profile];
		return YES;
	}
	return NO;
}

- (void)runNormally
{
//    NSString* lastHostName = [[PrefController sharedController] lastHostName];

//	if( nil != lastHostName )
//	    [serverList setStringValue: lastHostName];
//	[self selectedHostChanged];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver: self 
		   selector: @selector(updateProfileList:) 
			   name: ProfileAddDeleteNotification 
			 object: nil];
	[nc addObserver: self 
		   selector: @selector(serverListDidChange:) 
			   name: ServerListChangeMsg 
			 object: nil];
	
	// So we can tell when the serverList finished changing
	[nc addObserver:self 
		   selector: @selector(cellTextDidEndEditing:) 
			   name: NSControlTextDidEndEditingNotification 
			 object: serverList];
	[nc addObserver:self 
		   selector: @selector(cellTextDidBeginEditing:) 
			   name: NSControlTextDidBeginEditingNotification 
			 object: serverList];

	[self showConnectionDialog: nil];
}

- (void)cmdlineUsage
{
    fprintf(stderr, "\nUsage: Chicken of the VNC [options] [host:port]\n\n");
    fprintf(stderr, "options:\n\n");
    fprintf(stderr, "--PasswordFile <password-file>\n");
    fprintf(stderr, "--Profile <profile-name>\n");
    fprintf(stderr, "--Display <display-number>\n");
    fprintf(stderr, "--FullScreen\n");
	fprintf(stderr, "--ViewOnly\n");
    exit(1);
}

- (void)showNewConnectionDialog:(id)sender
{
	ServerDataViewController* viewCtrlr = [[ServerDataViewController alloc] initWithReleaseOnCloseOrConnect];
	[viewCtrlr setConnectionDelegate:[RFBConnectionManager sharedManager]];
	
	ServerStandAlone* server = [[[ServerStandAlone alloc] init] autorelease];
	
	[viewCtrlr setServer:server];
	[[viewCtrlr window] makeKeyAndOrderFront:self];
}

- (void)showConnectionDialog: (id)sender
{
	[[self window] makeFirstResponder: serverList];
	[[self window] makeKeyAndOrderFront:self];
}

- (void)dealloc
{
	[[NSUserDefaults standardUserDefaults] synchronize];
    [connections release];
	[mServerCtrler release];
	[mOrderedServerNames release];
    [super dealloc];
}

- (id<IServerData>)selectedServer
{
	return [[ServerDataManager sharedInstance] getServerWithName:[mOrderedServerNames objectAtIndex:[serverList selectedRow]]];
}

- (void)selectedHostChanged
{	
	NSParameterAssert( mServerCtrler != nil );

	id<IServerData> selectedServer = [self selectedServer];
	[mServerCtrler setServer:selectedServer];
	
	
	[serverDeleteBtn setEnabled: [selectedServer doYouSupport:DELETE]];
}

- (NSString*)translateDisplayName:(NSString*)aName forHost:(NSString*)aHost
{
	/* change */
    NSDictionary* hostDictionaryList = [[PrefController sharedController] hostInfo];
    NSDictionary* hostDictionary = [hostDictionaryList objectForKey:aHost];
    NSDictionary* names = [hostDictionary objectForKey:@"NameTranslations"];
    NSString* news;
	
    if((news = [names objectForKey:aName]) == nil) {
        news = aName;
    }
    return news;
}

- (void)setDisplayNameTranslation:(NSString*)translation forName:(NSString*)aName forHost:(NSString*)aHost
{
    PrefController* prefController = [PrefController sharedController];
    NSMutableDictionary* hostDictionaryList, *hostDictionary, *names;

    hostDictionaryList = [[[prefController hostInfo] mutableCopy] autorelease];
    if(hostDictionaryList == nil) {
        hostDictionaryList = [NSMutableDictionary dictionary];
    }
    hostDictionary = [[[hostDictionaryList objectForKey:aHost] mutableCopy] autorelease];
    if(hostDictionary == nil) {
        hostDictionary = [NSMutableDictionary dictionary];
    }
    names = [[[hostDictionary objectForKey:@"NameTranslations"] mutableCopy] autorelease];
    if(names == nil) {
        names = [NSMutableDictionary dictionary];
    }
    [names setObject:translation forKey:aName];
    [hostDictionary setObject:names forKey:@"NameTranslations"];
    [hostDictionaryList setObject:hostDictionary forKey:aHost];
    [prefController setHostInfo:hostDictionaryList];
}

- (void)removeConnection:(id)aConnection
{
    // Don't retain and autorelease the connection object if it isn't in our array of
    // objects. This prevents a problem where the connection controller calls removeConnection:
    // as a result of terminating itself in its dealloc method. It would be bad if we were to
    // autorelease the connection again in this case. This can only happen if the
    // connection list array doesn't contain the connection (thus retaining it).
    if ([connections containsObject:aConnection])
    {
        [aConnection retain];
        [connections removeObject:aConnection];
        [aConnection autorelease];
    }
    
    if (mRunningFromCommandLine)
    {
		[NSApp terminate:self];
    }
	else if (0 == [connections count] && !_isTerminating)
    {
		[self showConnectionDialog:nil];
    }
}

//! @brief Open a connection to the selected server.
//!
//! This method is invoked when a cell is double-clicked in the server list table.
- (void)connectSelectedServer:(id)sender
{
    [self connect:[self selectedServer]];
}

- (bool)connect:(id<IServerData>)server;
{
    Profile* profile = [[ProfileManager sharedManager] profileNamed:[server lastProfile]];
	bool bRetVal = [self createConnectionWithServer:server profile:profile];
	return bRetVal;
}

- (void)connection:(RFBConnectionController *)connection didCompleteWithStatus:(BOOL)status
{
    if (status)
	{
        // Add the new connection to the list.
        [connections addObject:connection];
        
        // Hide the connection manager window.
        if (connection.server == [self selectedServer])
        {
            [[self window] orderOut:self];
        }
    }

    // Release the connection object. It's either just been added to our list, or it failed
    // and needs to go away.
    [connection autorelease];
}

//! Do the work of creating a new connection and add it to the list of connections.
- (BOOL)createConnectionWithServer:(id<IServerData>)server profile:(Profile *)someProfile
{
    RFBConnectionController * theConnection = [[RFBConnectionController alloc] initWithServer:server profile:someProfile owner:self];
    if (!theConnection)
    {
        return NO;
    }
    
    // Start connecting.
    [theConnection connectWithCompletionTarget:self];
    
    return YES;
}

//! Used to create a connection from the listening socket.
- (BOOL)createConnectionWithFileHandle:(NSFileHandle*)file server:(id<IServerData>)server profile:(Profile *)someProfile
{
    RFBConnectionController * theConnection = [[RFBConnectionController alloc] initWithFileHandle:file server:server profile:someProfile owner:self];
    if (!theConnection)
    {
        return NO;
    }
    
    // Start connecting.
    [theConnection connectWithCompletionTarget:self];
    
    return YES;
}

- (IBAction)addServer:(id)sender
{
	ServerDataManager *serverDataManager = [ServerDataManager sharedInstance];
	id<IServerData> newServer = [serverDataManager createServerByName:NSLocalizedString(@"RFBDefaultServerName", nil)];
	NSString *newName = [newServer name];
	NSParameterAssert( newName != nil );
	
	[self reloadServerArray];
	
	int index = 0;
	NSString *name;
	for ( name in mOrderedServerNames )
	{
		if ( name && [name isEqualToString: newName] )
		{
			[serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection: NO];
			[serverList editColumn: 0 row: index withEvent: nil select: YES];
			break;
		}
		index++;
	}
    
    // Make sure the edit page is visible.
    if (!_isServerPaneVisible)
    {
        [self toggleServerEditPane:nil];
    }
}

- (IBAction)deleteSelectedServer:(id)sender
{
	[[ServerDataManager sharedInstance] removeServer:[self selectedServer]];
	
	[self reloadServerArray];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
//jshprefs    [self savePrefs];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    // Bring the connection manager to front if there are no other windows open.
    if ([[NSApp windows] count] == 0)
    {
        [[self window] makeKeyAndOrderFront:self];
    }
}

- (void)cellTextDidEndEditing:(NSNotification *)notif {
    [self selectedHostChanged];
}

- (void)cellTextDidBeginEditing:(NSNotification *)notif {
    [self selectedHostChanged];
}

// Jason added the following for full-screen windows
- (void)makeAllConnectionsWindowed
{
	RFBConnectionController *thisConnection;
    for (thisConnection in connections)
    {
		if (thisConnection.isFullscreen)
        {
			[thisConnection makeConnectionWindowed: self];
        }
    }
}

- (RFBConnectionController *)connectionForWindow:(NSWindow *)theWindow
{
	if (!theWindow)
	{
		return nil;
	}
	
	RFBConnectionController * thisConnection;
    for (thisConnection in connections)
	{
		if (thisConnection.window == theWindow)
		{
			return thisConnection;
		}
	}
	
	// No matching connection for the window.
	return nil;
}

- (RFBConnectionController *)nextConnection:(RFBConnectionController *)theConnection
{
	if (!theConnection)
	{
		return nil;
	}
	
	NSUInteger index = [connections indexOfObject:theConnection];
	if (index == NSNotFound)
	{
		return nil;
	}
	return [connections objectAtIndex:((++index) % [connections count])];
}

- (RFBConnectionController *)previousConnection:(RFBConnectionController *)theConnection
{
	if (!theConnection)
	{
		return nil;
	}
	
	NSUInteger index = [connections indexOfObject:theConnection];
	if (index == NSNotFound)
	{
		return nil;
	}
	
	// Decrement the index.
	if (index == 0)
	{
		index = [connections count] - 1;
	}
	else
	{
		--index;
	}
	return [connections objectAtIndex:index];
}

- (NSArray *)connections
{
	return connections;
}

- (BOOL)haveMultipleConnections
{
    return [connections count] > 1;
}

- (BOOL)haveAnyConnections
{
    return [connections count] > 0;
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if( serverList == aTableView )
	{
		return [mOrderedServerNames count];
	}
	
	return 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if( serverList == aTableView )
	{
        id colIdent = [aTableColumn identifier];
        if ([colIdent isEqualToString:@"servers"])
        {
            return [mOrderedServerNames objectAtIndex:rowIndex];
        }
        else if ([colIdent isEqualToString:@"type"])
        {
            id<IServerData> server = [[ServerDataManager sharedInstance] getServerWithName:[mOrderedServerNames objectAtIndex:rowIndex]];
            
            if ([server isKindOfClass:[ServerFromRendezvous class]])
            {
                return [NSImage imageNamed:@"NSBonjour"];
            }
            else
            {
                return nil;
            }
        }
	}
	
	return NULL;	
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
	return NO;	
}

- (void)afterSort:(id<IServerData>)server
{
	[self reloadServerArray];
	
	int index = 0;
	NSString *name;
	for ( name in mOrderedServerNames )
	{
		if ( name && [name isEqualToString: [server name]] )
		{
			[serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection: NO];
			break;
		}
		index++;
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSTableView *view = [aNotification object];
	if( serverList == view )
	{
		[self selectedHostChanged];
	}
}

- (void)updateProfileList:(NSNotification*)notification
{
	[mServerCtrler updateView: notification];
}

- (void)serverListDidChange:(NSNotification*)notification
{
	[self reloadServerArray];
	[serverList reloadData];
    [self selectedHostChanged];
}

// The user edited the name of a server. We want to try to keep the same server selected even if
// it moves around in the list due to sorting.
- (void)serverNameDidChange:(id<IServerData>)server
{
	[self reloadServerArray];
	[serverList reloadData];
    [self afterSort:server];
}

- (void)useRendezvous:(BOOL)useRendezvous
{
	[[ServerDataManager sharedInstance] useRendezvous: useRendezvous];
	
	NSParameterAssert( [[ServerDataManager sharedInstance] getUseRendezvous] == useRendezvous );
}

- (void)setFrontWindowUpdateInterval: (NSTimeInterval)interval
{
	RFBConnectionController *thisConnection;
	NSWindow *keyWindow = [NSApp keyWindow];
	
    for (thisConnection in connections)
    {
		if (thisConnection.window == keyWindow)
        {
			[thisConnection.connection setFrameBufferUpdateSeconds: interval];
			break;
		}
	}
}

- (void)setOtherWindowUpdateInterval: (NSTimeInterval)interval
{
	RFBConnectionController *thisConnection;
	NSWindow *keyWindow = [NSApp keyWindow];
	
    for (thisConnection in connections)
    {
		if (thisConnection.window != keyWindow)
        {
			[thisConnection.connection setFrameBufferUpdateSeconds: interval];
		}
	}
}

- (BOOL)launchedByURL
{
	return mLaunchedByURL;
}

- (void)setLaunchedByURL:(bool)launchedByURL
{
	mLaunchedByURL = launchedByURL;
}

- (NSString *)windowFrameAutosaveName
{
    return @"vnc_login";
}

- (IBAction)toggleServerEditPane:(id)sender
{
    NSWindow * window = [self window];
    NSView * contentView = [window contentView];
    NSRect oldFrame = [window frame];
    NSSize newFrameSize;
    NSRect newFrame = oldFrame;
    NSImage * newToggleImage;

    if (_isServerPaneVisible)
    {
        // Hide the server edit pane.
        newFrameSize = NSMakeSize([serverListBox frame].size.width, oldFrame.size.height);
        newFrame.size = newFrameSize;
        
        newToggleImage = [NSImage imageNamed:@"NSGoRightTemplate"];
    }
    else
    {
        // Show the server edit pane.
        newFrameSize = NSMakeSize(NSMaxX([serverDataBoxLocal frame]) + 20.0, oldFrame.size.height);
        newFrame.size = newFrameSize;
        
        newToggleImage = [NSImage imageNamed:@"NSGoLeftTemplate"];
    }
    
    [contentView setAutoresizesSubviews: NO];
    
    // Animate the window resize.
    const float kAnimationDuration = 0.1;
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kAnimationDuration];
    
    [[window animator] setFrame: newFrame display: NO];
    
    [NSAnimationContext endGrouping];
    
    // Wait until the animation is over.
    //! \todo Figure out the preferred way to wait until an animation is finished.
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:kAnimationDuration + 0.1]];

    [contentView setAutoresizesSubviews: YES];
    
    [toggleServerEditButton setImage:newToggleImage];
    
    // Update flag and save current pane state into prefs.
    _isServerPaneVisible = !_isServerPaneVisible;
    [[NSUserDefaults standardUserDefaults] setBool:_isServerPaneVisible forKey:@"isServerPaneVisible"];
}

@end
