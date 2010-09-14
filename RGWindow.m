//
//  RGWindow.m
//  Rss Growler
//
//  Created by Robert Chin on 6/2/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "RGWindow.h"


@implementation RGWindow

- (void)close
{
	[self makeFirstResponder:nil];
	[super close];
}

@end
