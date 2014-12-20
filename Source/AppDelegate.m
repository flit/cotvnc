//
//  AppDelegate.m
//  Chicken of the VNC
//
//  Created by Jason Harris on 8/18/04.
//  Copyright 2004 Geekspiff. All rights reserved.
//

#import "AppDelegate.h"
#import "KeyEquivalentManager.h"
#import "PrefController.h"
#import "ProfileManager.h"
#import "RFBConnectionManager.h"
#import "ListenerController.h"
#import "RFBConnection.h"

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	// make sure our singleton key equivalent manager is initialized, otherwise, it won't watch the frontmost window
	[[KeyEquivalentManager defaultManager] loadScenarios];
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	RFBConnectionManager *cm = [RFBConnectionManager sharedManager];

	if ( ! [cm runFromCommandLine] && ! [cm launchedByURL] )
		[cm runNormally];
	
	[mInfoVersionNumber setStringValue: [[[NSBundle mainBundle] infoDictionary] objectForKey: @"CFBundleVersion"]];
}


- (IBAction)showPreferences: (id)sender
{
	[[PrefController sharedController] showWindow];
}

- (BOOL) applicationShouldHandleReopen: (NSApplication *) app hasVisibleWindows: (BOOL) visibleWindows
{
	if(!visibleWindows)
	{
		[self showConnectionDialog:nil];
		return NO;
	}
	
	return YES;
}

- (IBAction)showConnectionDialog: (id)sender
{  [[RFBConnectionManager sharedManager] showConnectionDialog: nil];  }

- (IBAction)showNewConnectionDialog:(id)sender
{  [[RFBConnectionManager sharedManager] showNewConnectionDialog: nil];  }

- (IBAction)showListenerDialog: (id)sender
{  [[ListenerController sharedController] showWindow: nil];  }


- (IBAction)showProfileManager: (id)sender
{  [[ProfileManager sharedManager] showWindow: nil];  }


- (IBAction)showHelp: (id)sender
{
	NSString *path = [[NSBundle mainBundle] pathForResource: @"index" ofType: @"html" inDirectory: @"help"];
	[[NSWorkspace sharedWorkspace] openFile: path];
}

- (void)switchConnectionFrom:(RFBConnectionController *)fromConnection to:(RFBConnectionController *)toConnection direction:(TransitionDirection_t)direction
{
	if (fromConnection.isFullscreen)
	{
		// Handle fullscreen connections specially.
		[toConnection takeFullscreenFromConnection:fromConnection direction:direction];
	}
	else
	{
		// Not fullscreen, so just bring the next connection up to the front.
		[toConnection.window makeKeyAndOrderFront:nil];
	}
}

- (IBAction)showNextConnection:(id)sender
{
	RFBConnectionManager * cm = [RFBConnectionManager sharedManager];
	
	// Get the current connection.
	RFBConnectionController * connection = [cm connectionForWindow:[NSApp keyWindow]];
	if (!connection)
	{
		return;
	}
	
	// Get the next connection.
	RFBConnectionController * nextConnection = [cm nextConnection:connection];
	if (!nextConnection)
	{
		return;
	}
	
	// Bring the next connection to the front.
	[self switchConnectionFrom:connection to:nextConnection direction:kTransitionRightToLeft];
}

- (IBAction)showPreviousConnection:(id)sender
{
	RFBConnectionManager * cm = [RFBConnectionManager sharedManager];
	
	// Get the current connection.
	RFBConnectionController * connection = [cm connectionForWindow:[NSApp keyWindow]];
	if (!connection)
	{
		return;
	}
	
	// Get the previous connection.
	RFBConnectionController * prevConnection = [cm previousConnection:connection];
	if (!prevConnection)
	{
		return;
	}
	
	// Bring the previous connection to the front.
	[self switchConnectionFrom:connection to:prevConnection direction:kTransitionLeftToRight];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(showNextConnection:) || [menuItem action] == @selector(showPreviousConnection:))
	{
		RFBConnectionManager * cm = [RFBConnectionManager sharedManager];
		RFBConnectionController * theConnection = [cm connectionForWindow:[NSApp keyWindow]];
		return [cm haveMultipleConnections] && theConnection != nil;
	}
	
	return YES;
}

@end
