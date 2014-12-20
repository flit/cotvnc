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

#import "BufferPool.h"

@implementation BufferList

@synthesize count = _count;
@synthesize head = _head;
@synthesize tail = _tail;

//! @brief Append a buffer to the end of the list.
- (void)addBuffer:(BufferInfo_t *)buffer
{
    assert(buffer);

    _count++;
    
    // Handle an empty list.
    if (!_tail)
    {
        _head = buffer;
        _tail = buffer;
        buffer->next = NULL;
        buffer->prev = NULL;
        return;
    }
    
    buffer->next = NULL;
    buffer->prev = _tail;
    _tail->next = buffer;
    _tail = buffer;
}

//! @brief Remove a buffer from a list.
//! @pre The buffer must already be linked into the list.
- (void)removeBuffer:(BufferInfo_t *)buffer
{
    assert(buffer);
    
    // Update head and tail pointers.
    if (buffer == _head)
    {
        _head = buffer->next;
    }
    if (buffer == _tail)
    {
        _tail = buffer->prev;
    }
    
    _count--;
    
    // Unlink the buffer.
    if (buffer->prev)
    {
        buffer->prev->next = buffer->next;
    }
    if (buffer->next)
    {
        buffer->next->prev = buffer->prev;
    }
    
    // Clear the buffer's links.
    buffer->next = NULL;
    buffer->prev = NULL;
}

@end

@implementation BufferPool

- (id)init
{
    if ((self = [super init]))
    {
        _freeBuffers = [[BufferList alloc] init];
        _activeBuffers = [[BufferList alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    BufferInfo_t * cursor;
    BufferInfo_t * temp;
    
    // Free all active buffers.
    cursor = _activeBuffers.head;
    while (cursor)
    {
        temp = cursor->next;
        free(cursor->data);
        free(cursor);
        cursor = temp;
    }
    
    // Free all free buffers.
    cursor = _freeBuffers.head;
    while (cursor)
    {
        temp = cursor->next;
        free(cursor->data);
        free(cursor);
        cursor = temp;
    }
    
    [super dealloc];
}

- (uint8_t *)acquireBufferWithLength:(size_t)length options:(uint32_t)options
{
    @synchronized(self)
    {
        // Scan the free list for a buffer of the required size.
        BufferInfo_t * cursor = _freeBuffers.head;
        while (cursor)
        {
            if (cursor->length >= length)
            {
                // Move this buffer to the active list.
                [_freeBuffers removeBuffer:cursor];
                [_activeBuffers addBuffer:cursor];
                return cursor->data;
            }
            
            cursor = cursor->next;
        }
        
        // If we exit the loop, then we didn't find a matching buffer.
        if (options | kBufferOptionAllocate)
        {
            // Allocate the buffer descriptor.
            BufferInfo_t * newBuffer = (BufferInfo_t *)malloc(sizeof(BufferInfo_t));
            assert(newBuffer);
            
            // Allocate the buffer itself and fill in the descriptor.
            newBuffer->length = length;
            newBuffer->data = (uint8_t *)malloc(length);
            if (!newBuffer->data)
            {
                NSLog(@"%s: failed to allocate buffer (len=%lu) (%d active, %d free)", __func__, length, _activeBuffers.count, _freeBuffers.count);
            }
            assert(newBuffer->data);
            
            // Insert the new buffer into the list of active buffers.
            [_activeBuffers addBuffer:newBuffer];
            
            if (_activeBuffers.count > 5000)
            {
                NSLog(@"too many buffers have been allocated!");
            }
            
            return newBuffer->data;
        }
    }
        
    return NULL;
}

- (void)releaseBuffer:(const uint8_t *)buf
{
    @synchronized(self)
    {
        // Search the active buffer list for the data pointer.
        BufferInfo_t * cursor = _activeBuffers.head;
        while (cursor)
        {
            if (cursor->data == buf)
            {
                // We found it; move this buffer back to the free list.
                [_activeBuffers removeBuffer:cursor];
                [_freeBuffers addBuffer:cursor];
                return;
            }
            
            cursor = cursor->next;
        }
        
        // We exited the loop, meaning that the given buffer pointer wasn't one of the buffers
        // managed by this buffer pool.
        NSLog(@"%s: buffer 0x%08x not owned by pool 0x%08x", __func__, (unsigned int)buf, (unsigned int)self);
    }
}

@end

