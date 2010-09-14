/* Copyright (c) 2007, Robert Chin

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of
the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Growl/GrowlDefines.h>
#import "GrowlerObject.h"
#import "RSSItem.h"
#import "RSSGrowlerController.h"
#import "RSSFeed.h"

NSString *kNewRSSEntryKey = @"New RSS entry";
NSString *kNewRSSEmptyKey = @"RSS feeds with no name";

@implementation GrowlerObject

-(id)initWithController:(RSSGrowlerController *)aController
{
	if((self = [super init])){
		controller = aController;
		rssItemKeyed = [NSMutableDictionary new];
		[GrowlApplicationBridge setGrowlDelegate:self];
	}
	
	return self;
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[rssItemKeyed release];
	[super dealloc];
}

- (NSString *) applicationNameForGrowl
{
	return @"RSS Growler";
}

-(void)reregister
{
	[GrowlApplicationBridge reregisterGrowlNotifications];
}

- (NSDictionary *) registrationDictionaryForGrowl
{
	NSMutableArray *registerArray;
	if([[RGDefaults objectForKey:kGrowlListSeparately] boolValue]){
		registerArray = [NSMutableArray arrayWithObject:kNewRSSEmptyKey];
		id e = [[controller rssFeeds] objectEnumerator];
		RSSFeed *feed;
		while(feed = [e nextObject]){
			id name = [feed name];
			if(name)
				[registerArray addObject:name];
		}
	} else
		registerArray = [NSMutableArray arrayWithObject:kNewRSSEntryKey];
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
		registerArray, GROWL_NOTIFICATIONS_ALL,
		registerArray, GROWL_NOTIFICATIONS_DEFAULT,
		nil];
}

- (void) growlNotificationWasClicked:(id)clickContext
{
	RSSItem *item = [rssItemKeyed objectForKey:clickContext];
	if(item){
		if([[RGDefaults objectForKey:kGrowlClickAction] boolValue])
			[item openFeed:self];
		[rssItemKeyed removeObjectForKey:clickContext];
	}
}

- (void) growlNotificationTimedOut:(id)clickContext
{
	RSSItem *item = [rssItemKeyed objectForKey:clickContext];
	if(item){
		[rssItemKeyed removeObjectForKey:clickContext];
	}
}

-(void)postNewRSSItem:(RSSItem *)rssItem
{
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	NSString *uuidString = (NSString *)CFUUIDCreateString(NULL, uuid);
	[rssItemKeyed setObject:rssItem forKey:uuidString];
	CFRelease(uuid);

	NSString *notificationName = kNewRSSEntryKey;
	if([[RGDefaults objectForKey:kGrowlListSeparately] boolValue]){
		notificationName = [[rssItem valueForKey:@"feed"] name];
		if(!notificationName)
			notificationName = kNewRSSEmptyKey;
	}
	
	[GrowlApplicationBridge
	notifyWithTitle:[rssItem growlerTitle]
		description:[rssItem growlerDescription]
   notificationName:notificationName
		   iconData:nil
		   priority:0
		   isSticky:[controller pinGrowlNotification]
	   clickContext:uuidString];
	CFRelease(uuidString);
}

@end
