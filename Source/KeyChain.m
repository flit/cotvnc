//
//  KeyChain.m
//  Fire
//
//  Created by Colter Reed on Thu Jan 24 2002.
//  Copyright (c) 2002 Colter Reed. All rights reserved.
//  Released under GPL.  You know how to get a copy.
//

#import "KeyChain.h"

static KeyChain* defaultKeyChain = nil;

@interface KeyChain ()

-(SecKeychainItemRef)_genericPasswordReferenceForService:(NSString *)service account:(NSString*)account;

@end

@implementation KeyChain

+ (KeyChain*) defaultKeyChain
{
	return ( defaultKeyChain ? defaultKeyChain : [[[self alloc] init] autorelease] );
}

- (id)init
{
    if (self = [super init])
    {
        maxPasswordLength = 127;
    }
    return self;
}

- (void)setGenericPassword:(NSString*)password forService:(NSString *)service account:(NSString*)account
{
    if ([service length] == 0 || [account length] == 0)
    {
        return;
    }
    
    // Delete a previous password for this service and account.
    [self removeGenericPasswordForService:service account:account];
    
    // Insert the new password if it is non-empty.
    if (password && [password length])
    {
        SecKeychainAddGenericPassword(NULL, [service lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [service UTF8String], [account lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [account UTF8String], [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [password UTF8String], NULL);
    }
}

- (NSString*)genericPasswordForService:(NSString *)service account:(NSString*)account
{
    NSString *string = @"";
    
    if ([service length] == 0 || [account length] == 0)
    {
        return @"";
    }

    UInt32 length;
    void * passwordData;
    if (SecKeychainFindGenericPassword(NULL, [service lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [service UTF8String], [account lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [account UTF8String], &length, &passwordData, NULL) == noErr)
    {
        string = [[[NSString alloc] initWithBytes:passwordData length:length encoding:NSUTF8StringEncoding] autorelease];
        SecKeychainItemFreeContent(NULL, passwordData);
    }
    return string;
}

- (void)removeGenericPasswordForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref = [self _genericPasswordReferenceForService:service account:account];
    if (itemref)
    {
        SecKeychainItemDelete(itemref);
    }
}

- (void)setMaxPasswordLength:(unsigned)length
{
    if (![self isEqual:defaultKeyChain])
    {
        maxPasswordLength = length;
    }
}

- (unsigned)maxPasswordLength
{
    return maxPasswordLength;
}

- (SecKeychainItemRef)_genericPasswordReferenceForService:(NSString *)service account:(NSString*)account
{
    SecKeychainItemRef itemref = NULL;
    
    SecKeychainFindGenericPassword(NULL, [service lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [service UTF8String], [account lengthOfBytesUsingEncoding:NSUTF8StringEncoding], [account UTF8String], NULL, NULL, &itemref);
    
    return itemref;
}

@end
