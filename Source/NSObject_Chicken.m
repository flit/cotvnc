//
//  NSObject_Chicken.m
//  Chicken of the VNC
//
//  Created by Jason Harris on 8/20/04.
//  Copyright 2004 Geekspiff. All rights reserved.
//

#import "NSObject_Chicken.h"


@implementation NSObject (Chicken)

- (id)deepMutableCopy
{
	BOOL isArray = [self isKindOfClass: [NSArray class]];
	id dest;
	if ( isArray )
	{
		dest = [[NSMutableArray alloc] init];
	}
	else
	{
		dest = [[NSMutableDictionary alloc] init];
	}
	
	NSEnumerator *keyEnumerator = isArray ? 
									[(NSArray *)self objectEnumerator] : 
									[(NSDictionary *)self keyEnumerator];
	NSString *key;
	
	while ( key = [keyEnumerator nextObject] )
	{
		id object = isArray ? key : [(NSDictionary *)self objectForKey: key];
		id newObject = object;
		BOOL releaseNewObject = NO;
		
		if ( [object isKindOfClass: [NSDictionary class]] || [object isKindOfClass: [NSArray class]] )
		{
			newObject = [object deepMutableCopy];
			releaseNewObject = YES;
		}
		
		if ( isArray )
		{
			[dest addObject: newObject];
		}
		else
		{
			[dest setObject: newObject forKey: key];
		}
		
		if (releaseNewObject)
		{
			[newObject release];
		}
	}
	return dest;
}

@end
