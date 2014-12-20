//
//  NSString_ByteString.m
//  Chicken of the VNC
//
//  Created by Chris Reed on 12/8/09.
//  Copyright 2009 Immo Software. All rights reserved.
//

#import "NSString_ByteString.h"


@implementation NSString (ByteString)

+ (NSString *)stringFromByteQuantity:(double)amount suffix:(NSString *)suffix
{
    static NSArray * byteSuffixes = nil;
    if (!byteSuffixes)
    {
        byteSuffixes = [[NSArray alloc] initWithObjects:NSLocalizedString(@" bytes", nil), NSLocalizedString(@"KB", nil), NSLocalizedString(@"MB", nil), NSLocalizedString(@"GB", nil), nil];
    }
    return [self stringFromQuantity:amount withUnits:byteSuffixes suffix:suffix];
}

+ (NSString *)stringFromBitQuantity:(double)amount suffix:(NSString *)suffix
{
    static NSArray * bitSuffixes = nil;
    if (!bitSuffixes)
    {
        bitSuffixes = [[NSArray alloc] initWithObjects:NSLocalizedString(@" bits", nil), NSLocalizedString(@"Kb", nil), NSLocalizedString(@"Mb", nil), NSLocalizedString(@"Gb", nil), nil];
    }
    return [self stringFromQuantity:amount withUnits:bitSuffixes suffix:suffix];
}

+ (NSString *)stringFromQuantity:(double)amount withUnits:(NSArray *)units suffix:(NSString *)suffix
{
    if (!suffix)
    {
        suffix = @"";
    }
    
    if (amount < 1024)
    {
        return [NSString stringWithFormat:@"%u%@%@", (unsigned)amount, [units objectAtIndex:0], suffix];
    }
    else if (amount < (1024*1024))
    {
        return [NSString stringWithFormat:@"%.2f%@%@", amount / 1024, [units objectAtIndex:1], suffix];
    }
    else if (amount < (1024*1024*1024))
    {
        return [NSString stringWithFormat:@"%.2f%@%@", amount / (1024*1024), [units objectAtIndex:2], suffix];
    }
    else
    {
        return [NSString stringWithFormat:@"%.2f%@%@", amount / (1024*1024*1024), [units objectAtIndex:3], suffix];
    }
}

@end
