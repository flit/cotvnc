//
//  NSString_ByteString.h
//  Chicken of the VNC
//
//  Created by Chris Reed on 12/8/09.
//  Copyright 2009 Immo Software. All rights reserved.
//

#import <Cocoa/Cocoa.h>

/*!
 * @brief Category on NSString for generating strings from byte quantities.
 */
@interface NSString (ByteString)

//! @brief Creates a new string from a number of bytes.
//!
//! The resulting string will have an appropriate suffix, such as "KB", "MB", or "GB".
+ (NSString *)stringFromByteQuantity:(double)amount suffix:(NSString *)suffix;

//! @brief Creates a stirng from a bits quanity;
+ (NSString *)stringFromBitQuantity:(double)amount suffix:(NSString *)suffix;

//! @brief Generic form.
+ (NSString *)stringFromQuantity:(double)amount withUnits:(NSArray *)units suffix:(NSString *)suffix;

@end
