//
//  CustomOutlineView.m
//  SDef Editor
//
//  Created by Grayfox on 09/01/05.
//  Copyright 2005 Shadow Lab. All rights reserved.
//

#import "CustomOutlineView.h"

@interface NSObject (CustomOutlineViewDelegate)
- (void)deleteSelectionInOutlineView:(NSOutlineView *)aView;
@end

@implementation CustomOutlineView

- (IBAction)deleteSelection:(id)sender {
  if ([[self delegate] respondsToSelector:@selector(deleteSelectionInOutlineView:)]) {
    [[self delegate] deleteSelectionInOutlineView:self];
  } else {
    NSBeep();
  }
}

- (void)keyDown:(NSEvent *)theEvent {
  switch ([theEvent keyCode]) {
    case 0x033: //kVirtualDeleteKey:
    case 0x075: //kVirtualForwardDeleteKey:
      [self deleteSelection:nil];
      break;
    case 0x024: //kVirtualReturnKey:
    case 0x04C: //kVirtualEnterKey:
      if ([self target] && [self doubleAction] && [[self target] respondsToSelector:[self doubleAction]]) {
        [[self target] performSelector:[self doubleAction] withObject:self];
      }
      break;
    default:
      [super keyDown:theEvent];
  }
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent {
  int row;
  if ( (row = [self rowAtPoint:[self convertPoint:[theEvent locationInWindow] fromView:nil]]) != -1) {
    [self selectRow:row byExtendingSelection:NO];
    [self displayIfNeeded];
    return [super menuForEvent:theEvent];
  }
  return nil;
}

@end
