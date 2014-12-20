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

#import "FrameBuffer.h"
@class EventFilter, RFBConnectionController;

/*!
 * \brief View that draws the remote screen.
 *
 * The view must have its delegate, event filter, and frame buffer all set before it is
 * truly initialized.
 */
@interface RFBView : NSView
{
    RFBConnectionController *_delegate;
	EventFilter *_eventFilter;
    NSCursor *_cursor;	//!< Not retained.
	NSCursor * _remoteCursor;	//!< Retained.
    FrameBuffer *fbuf;
}

+ (NSCursor *)_cursorForName: (NSString *)name;

//! Filter which transforms local events into messages to the remote server.
@property(nonatomic, assign) EventFilter * eventFilter;

//! The parent connection that owns this view.
@property(nonatomic, assign) RFBConnectionController * delegate;

//! The framebuffer that is drawn into this view.
@property(nonatomic, retain) FrameBuffer * frameBuffer;

- (void)drawRect:(NSRect)aRect;
- (void)displayFromBuffer:(NSRect)aRect;
- (void)drawRectList:(id)aList;

- (void)setCursorTo: (NSString *)name;
- (void)setRemoteCursor:(NSCursor *)newCursor;

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;
- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender;
- (void)draggingExited:(id <NSDraggingInfo>)sender;
- (unsigned int)draggingUpdated:(id <NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;

@end
