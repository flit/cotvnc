//
//  AppDelegate.h
//  Chicken of the VNC
//
//  Created by Jason Harris on 8/18/04.
//  Copyright 2004 Geekspiff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "RFBConnectionController.h"

@interface AppDelegate : NSObject
{
	IBOutlet NSTextField *mInfoVersionNumber;
}

- (IBAction)showPreferences: (id)sender;
- (IBAction)showNewConnectionDialog:(id)sender;
- (IBAction)showConnectionDialog: (id)sender;
- (IBAction)showListenerDialog: (id)sender;
- (IBAction)showProfileManager: (id)sender;
- (IBAction)showHelp: (id)sender;
- (IBAction)showNextConnection:(id)sender;
- (IBAction)showPreviousConnection:(id)sender;

- (void)switchConnectionFrom:(RFBConnectionController *)fromConnection to:(RFBConnectionController *)toConnection direction:(TransitionDirection_t)direction;

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;

@end
