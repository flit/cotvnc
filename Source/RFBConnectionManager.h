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
#import "ServerDataViewController.h"
#import "RFBConnectionController.h"

@class Profile, ProfileManager;
@class ServerDataViewController;
@class RFBConnection;
@class RFBConnectionController;
@protocol IServerData;

/*!
 * \brief Manages the list of open connections.
 */
@interface RFBConnectionManager : NSWindowController <ConnectionDelegate, RFBConnectionCompleting>
{
	IBOutlet NSTableView *serverList;
    IBOutlet NSBox * serverListBox;     //!< Box view holding the server list side of the window.
	IBOutlet NSBox *serverDataBoxLocal;
    IBOutlet NSButton *serverDeleteBtn;
    IBOutlet NSButton * toggleServerEditButton;
    NSMutableArray*	connections;
	ServerDataViewController* mServerCtrler;
	BOOL mRunningFromCommandLine;
	BOOL mLaunchedByURL;
	NSMutableArray* mOrderedServerNames;
    BOOL _isTerminating;    //!< True if the application is terminating.
    BOOL _isServerPaneVisible;  //!< True if the server editor pane is visible in the window.
}

+ (id)sharedManager;

- (void)wakeup;
- (BOOL)runFromCommandLine;
- (void)runNormally;

- (void)showNewConnectionDialog: (id)sender;
- (void)showConnectionDialog: (id)sender;

- (void)removeConnection:(id)aConnection;
- (bool)connect:(id<IServerData>)server;
- (void)cmdlineUsage;

- (void)selectedHostChanged;

- (NSString*)translateDisplayName:(NSString*)aName forHost:(NSString*)aHost;
- (void)setDisplayNameTranslation:(NSString*)translation forName:(NSString*)aName forHost:(NSString*)aHost;

- (BOOL)createConnectionWithServer:(id<IServerData>)server profile:(Profile *)someProfile;
- (BOOL)createConnectionWithFileHandle:(NSFileHandle*)file 
    server:(id<IServerData>)server profile:(Profile *)someProfile;

- (IBAction)addServer:(id)sender;
- (IBAction)deleteSelectedServer:(id)sender;

- (void)makeAllConnectionsWindowed;

- (RFBConnectionController *)connectionForWindow:(NSWindow *)theWindow;
- (RFBConnectionController *)nextConnection:(RFBConnectionController *)theConnection;
- (RFBConnectionController *)previousConnection:(RFBConnectionController *)theConnection;

- (NSArray *)connections;
- (BOOL)haveMultipleConnections; // True if there is more than one connection open.
- (BOOL)haveAnyConnections;      // True if there are any connections open.

- (void)serverListDidChange:(NSNotification*)notification;

- (id<IServerData>)selectedServer;

- (void)useRendezvous:(BOOL)useRendezvous;

- (void)setFrontWindowUpdateInterval: (NSTimeInterval)interval;
- (void)setOtherWindowUpdateInterval: (NSTimeInterval)interval;

- (BOOL)launchedByURL;
- (void)setLaunchedByURL:(bool)launchedByURL;

- (IBAction)toggleServerEditPane:(id)sender;

@end
