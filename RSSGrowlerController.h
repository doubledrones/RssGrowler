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

#import <Cocoa/Cocoa.h>

#define RGDefaults		[NSUserDefaults standardUserDefaults]

@class RSSFeed;
@class RSSItem;

extern NSString *kCheckIntervalTime;
extern NSString *kShowTopEntriesCount;
extern NSString *kMaxEntryHistory;
extern NSString *kHideTopFromHistory;
extern NSString *kGrowlClickAction;
extern NSString *kGrowlListSeparately;
extern NSString *kEnablePageCaching;
extern NSString *kEnableMenuSubLinks;

@interface RSSGrowlerController : NSObject {
	NSTimer *checkFeedsTimer;
	NSStatusItem *statusItem;
	id growlerObject;
	IBOutlet id appDelegate;
	IBOutlet id manageWindow;
	IBOutlet id prefWindow;
	IBOutlet id aboutWindow;
}

-(void)defaultsChanged:(NSNotification *)aNotification;
-(void)recreateTimerAndUpdate;
-(NSArray *)rssFeeds;
-(NSSet *)allCachedIDs;
-(void)activateStatusMenu;
-(void)checkFeeds:(id)sender;
-(IBAction)updateMenus:(id)sender;
-(void)postNewRSSItem:(NSNotification *)notification;
-(NSMenu *)feedsMenu;

@end
