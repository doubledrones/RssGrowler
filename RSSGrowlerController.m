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

#import "RSSGrowlerController.h"
#import "GrowlerObject.h"
#import "RSSFeed.h"
#import "RSSItem.h"
#import "Rss_Growler_AppDelegate.h"

NSString *kCheckIntervalTime = @"Check Interval";
NSString *kShowTopEntriesCount = @"Show Top Entries Count";
NSString *kMaxEntryHistory = @"Maximum Entry History Count";
NSString *kHideTopFromHistory = @"Hide Top Entries From History";
NSString *kGrowlClickAction = @"Growl Click Action";
NSString *kGrowlListSeparately = @"Growl List Feeds Separately";
NSString *kEnablePageCaching = @"Enable Target Page Cache";
NSString *kEnableMenuSubLinks = @"Enable SubLinks in Menu";

@implementation RSSGrowlerController

+(id)defaultsDictionary
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithDouble:1800.0],		kCheckIntervalTime,
		[NSNumber numberWithInt:10],			kShowTopEntriesCount,
		[NSNumber numberWithInt:100],			kMaxEntryHistory,
		[NSNumber numberWithBool:YES],			kHideTopFromHistory,
		[NSNumber numberWithBool:NO],			kGrowlClickAction,
		[NSNumber numberWithBool:NO],			kGrowlListSeparately,
		[NSNumber numberWithBool:NO],			kEnablePageCaching,
		[NSNumber numberWithBool:YES],			kEnableMenuSubLinks,
		nil];
}

+(void)initialize
{
	[RGDefaults registerDefaults:[self defaultsDictionary]];
}

-(void)awakeFromNib
{
	growlerObject = [[GrowlerObject alloc] initWithController:self];
	[self activateStatusMenu];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateMenus:) name:@"updateMenus" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedContextChanged:) name:NSManagedObjectContextObjectsDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(postNewRSSItem:) name:@"newRssItem" object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(defaultsChanged:) name:NSUserDefaultsDidChangeNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:growlerObject selector:@selector(reregister) name:@"feedNameChanged" object:nil];
	
	[self checkFeeds:self];
	[manageWindow setLevel:NSFloatingWindowLevel];
	[prefWindow setLevel:NSFloatingWindowLevel];
	[self recreateTimerAndUpdate];
	
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *cachesFolder = [[NSApp delegate] cachesFolder];
	NSSet *cachedIDs = [self allCachedIDs];
	NSMutableSet *contents = [NSMutableSet setWithArray:[manager directoryContentsAtPath:cachesFolder]];
	[contents minusSet:cachedIDs];

	id e = [contents objectEnumerator];
	id anObject;
	while(anObject = [e nextObject]){
		NSString *file = [cachesFolder stringByAppendingPathComponent:anObject];
		[manager removeFileAtPath:file handler:nil];
	}
}

-(void)defaultsChanged:(NSNotification *)aNotification
{
	[growlerObject reregister];
	[self recreateTimerAndUpdate];
}

-(void)recreateTimerAndUpdate
{
	[checkFeedsTimer invalidate];
	checkFeedsTimer = [NSTimer scheduledTimerWithTimeInterval:MAX([[RGDefaults objectForKey:kCheckIntervalTime] doubleValue], 30.0)
													   target:self
													 selector:@selector(checkFeeds:)
													 userInfo:nil
													  repeats:YES];
	[self updateMenus:nil];
}

-(NSArray *)rssFeeds
{
	NSManagedObjectContext *moc = [appDelegate managedObjectContext];
		
	NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"RSSFeed" inManagedObjectContext:moc];
	NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
	[request setEntity:entityDescription];

	NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
	[request setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
	[sortDescriptor release];

	NSError *error = nil;
	NSArray *array = [moc executeFetchRequest:request error:&error];
	if(error)
		[[NSAlert alertWithError:error] runModal];
	return array;
}

-(NSSet *)allCachedIDs
{
	NSMutableSet *allCachedIDs = [NSMutableSet set];
	id e = [[self rssFeeds] objectEnumerator];
	id anObject;
	while(anObject = [e nextObject]){
		[allCachedIDs unionSet:[anObject cachedIDs]];
	}
	
	return allCachedIDs;
}

-(void)activateStatusMenu
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem retain];
	
	[statusItem setImage:[NSImage imageNamed:@"menuicon"]];
	[statusItem setAlternateImage:[NSImage imageNamed:@"menuicon_sel"]];
    [statusItem setHighlightMode:YES];
    [statusItem setMenu:[self feedsMenu]];
}

-(NSMenu *)feedsMenu
{
	NSMenu *menu = [[NSMenu alloc] init];
	NSArray *rssArray = [self rssFeeds];
	id e = [rssArray objectEnumerator];
	id feed;
	NSMutableArray *topArray = [NSMutableArray array];
	int topCount = [[[NSUserDefaults standardUserDefaults] objectForKey:kShowTopEntriesCount] intValue];
	while(feed = [e nextObject]){
		[topArray addObjectsFromArray:[feed firstFeedItems:topCount]];
	}
	[topArray sortUsingSelector:@selector(dateCompare:)];

	unsigned count = [topArray count];
	unsigned maxNum = (unsigned)[[RGDefaults objectForKey:kShowTopEntriesCount] intValue];
	if(count > maxNum){
		NSRange removeRange = NSMakeRange(maxNum, count - maxNum);
		[topArray removeObjectsInArray:[topArray subarrayWithRange:removeRange]];
	}
	
	NSSet *topSet = [NSSet setWithArray:topArray];
	
	e = [topArray objectEnumerator];
	while(feed = [e nextObject]){
		[feed cachePage];
		[menu addItem:[feed menuItem]];
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	
	e = [rssArray objectEnumerator];
	while(feed = [e nextObject]){
		[menu addItem:[feed feedMenuItem:topSet]];
	}

	{
		[menu addItem:[NSMenuItem separatorItem]];
		NSMenuItem *manageItem = [[NSMenuItem alloc] initWithTitle:@"Manage Subscriptions..." action:@selector(makeKeyAndOrderFront:) keyEquivalent:@""];
		[manageItem setTarget:manageWindow];
		[menu addItem:[manageItem autorelease]];
		NSMenuItem *prefItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..." action:@selector(makeKeyAndOrderFront:) keyEquivalent:@""];
		[prefItem setTarget:prefWindow];
		[menu addItem:[prefItem autorelease]];
		NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About" action:@selector(makeKeyAndOrderFront:) keyEquivalent:@""];
		[aboutItem setTarget:aboutWindow];
		[menu addItem:[aboutItem autorelease]];
		NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@""];
		[quitItem setTarget:self];
		[menu addItem:[quitItem autorelease]];
	}
	return [menu autorelease];	
}

-(void)checkFeeds:(id)sender
{
	id e = [[self rssFeeds] objectEnumerator];
	id anObject;
	while(anObject = [e nextObject]){
		[anObject checkFeed];
	}
}

-(void)managedContextChanged:(NSNotification *)notification
{
	if([[[notification userInfo] objectForKey:NSDeletedObjectsKey] count] > 0)
		[self updateMenus:self];
}

-(IBAction)updateMenus:(id)sender
{
    [statusItem setMenu:[self feedsMenu]];
}

-(void)postNewRSSItem:(NSNotification *)notification
{
	[growlerObject postNewRSSItem:[[notification userInfo] objectForKey:@"RSSItem"]];
}

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[checkFeedsTimer invalidate];
	[statusItem release];
	[growlerObject release];
	[super dealloc];
}

-(void)quit:(id)sender
{
	[NSApp terminate:sender];
}

@end
