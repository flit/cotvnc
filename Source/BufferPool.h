/*
 * Copyright (C) 2009 Chris Reed
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

#import <Cocoa/Cocoa.h>

/*!
 * @brief One buffer in the pool.
 */
struct _BufferInfo
{
    uint8_t * data;
    size_t length;
    struct _BufferInfo * next;
    struct _BufferInfo * prev;
};

typedef struct _BufferInfo BufferInfo_t;

/*!
 * @brief A linked list of buffers.
 */
@interface BufferList : NSObject
{
    BufferInfo_t * _head;
    BufferInfo_t * _tail;
    int _count;
}

@property int count;
@property BufferInfo_t * head;
@property BufferInfo_t * tail;

- (void)addBuffer:(BufferInfo_t *)buffer;
- (void)removeBuffer:(BufferInfo_t *)buffer;


@end

//! @brief Option flag masks for acquiring a buffer.
enum _BufferOptions
{
    kBufferOptionAllocate = 1,  //!< Allocate a new buffer if none are available.
    kBufferOptionGrow = 2,      //!< Grow a small buffer to match the requested size.
    kBufferOptionWait = 4,      //!< Wait for a buffer to become available.
};

/*!
 * @brief Manages a cyclic pool of variable sized buffers.
 *
 * @todo Retire buffers not used in a while, to allow the pool size to grow and shrink over
 *      time, as connections are opened and closed.
 */
@interface BufferPool : NSObject
{
    BufferList * _freeBuffers;  //!< The list of buffers available for callers to use.
    BufferList * _activeBuffers;    //!< The list of buffers currently in use.
}

//! @brief Designated initializer.
- (id)init;

//! @brief Get an unused buffer of at least @a length bytes.
- (uint8_t *)acquireBufferWithLength:(size_t)length options:(uint32_t)options;

//! @brief Return a buffer to the pool.
- (void)releaseBuffer:(const uint8_t *)buf;

@end

