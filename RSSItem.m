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

#import "RSSItem.h"
#import "RSSFeed.h"
#import "Rss_Growler_AppDelegate.h"
#import "SubLink.h"
#import "RSSGrowlerController.h"

@implementation RSSItem

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[webView release];
	[super dealloc];
}

-(unsigned)hash
{
	return [[self guid] hash];
}

-(BOOL)isEqual:(id)anObject
{
	if([anObject class] == [self class])
		return [[self guid] isEqual:[anObject guid]];
	return NO;
}

-(void)setText:(NSString *)string
{
	NSAttributedString *as = [[NSAttributedString alloc] initWithHTML:[string dataUsingEncoding:NSUnicodeStringEncoding]
												   documentAttributes:nil];
	NSString *textString = [as string];
	[self willChangeValueForKey:@"text"];
    [self setPrimitiveValue:textString forKey:@"text"];
    [self didChangeValueForKey:@"text"];
	[self createSubLinksFromString:textString];
	[as release];
}

-(NSDate *)date
{
	[self willAccessValueForKey:@"date"];
	NSDate *value = [self primitiveValueForKey:@"date"];
	[self didAccessValueForKey:@"date"];
	return value;	
}

-(NSString *)guid
{
	[self willAccessValueForKey:@"guid"];
    NSString *value = [self primitiveValueForKey:@"guid"];
    [self didAccessValueForKey:@"guid"];
    return value;	
}

-(NSString *)growlerTitle
{
	if([[self valueForKey:@"feed"] isTracFeed]){
		NSString *growler = [[[self valueForKey:@"title"] componentsSeparatedByString:@":"] objectAtIndex:0];
		NSString *author = [self valueForKey:@"author"];
		if(author)
			growler = [NSString stringWithFormat:@"%@: %@", growler, author];
		return growler;
	}
	else
		return [self valueForKey:@"title"];
}

-(NSString *)growlerDescription
{
	return [self valueForKey:@"text"];
}

-(void)cachePage
{
	if([[RGDefaults objectForKey:kEnablePageCaching] boolValue] && ![self valueForKey:@"cachedPath"] && !cachingPage){
		cachingPage = YES;
		NSString *url = [self valueForKey:@"url"];
		if(url){
			NSURL *realURL = [NSURL URLWithString:url];
			if(realURL){
				NSURLRequest *request = [NSURLRequest requestWithURL:realURL];
				if(!webView){
					webView = [[WebView alloc] initWithFrame:NSMakeRect(0,0,200,200)];
					[webView setFrameLoadDelegate:self];
					[[webView mainFrame] loadRequest:request];
				}
			}
		}
	}
}

-(void)removePageCache
{
	NSString *cachedPath = [self valueForKey:@"cachedPath"];
	[self setValue:nil forKey:@"cachedPath"];
	if(webView){
		[webView release];
		webView = nil;
	}
	[[NSFileManager defaultManager] removeFileAtPath:cachedPath handler:nil];
}

-(NSString *)cachedID
{
	return [[self valueForKey:@"cachedPath"] lastPathComponent];
}

-(NSMenuItem *)menuItem
{
	NSString *title = [self valueForKey:@"title"];
	if([[self valueForKey:@"feed"] isTracFeed]){
		NSRange revRange = [title rangeOfString:@"Revision "];
		NSMutableString *newStr = [NSMutableString stringWithString:title];
		[newStr replaceCharactersInRange:revRange withString:@""];
		title = newStr;
#if 0
		NSArray *comps = [newStr componentsSeparatedByString:@": "];
		int count = [comps count];
		NSString *sec = [[comps subarrayWithRange:NSMakeRange(1, count - 1)] componentsJoinedByString:@": "];
		NSString *author = [[[self valueForKey:@"author"] componentsSeparatedByString:@"@"] objectAtIndex:0];
		if(author)
			title = [NSString stringWithFormat:@"%@: [%@] %@", [comps objectAtIndex:0], author, sec];
		else
			title = [NSString stringWithFormat:@"%@: %@", [comps objectAtIndex:0], sec];
#endif
	}
	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
													  action:@selector(openFeed:)
											   keyEquivalent:@""];
	[menuItem setTarget:self];
	if([[RGDefaults objectForKey:kEnableMenuSubLinks] boolValue]){
		NSSet *subLinks = [self valueForKey:@"subLinks"];
		if([subLinks count] > 0){
			NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
			id e = [subLinks objectEnumerator];
			id subLink;
			while(subLink = [e nextObject]){
				[menu addItem:[subLink subLinkMenuItem]];
			}
			[menuItem setSubmenu:[menu autorelease]];
		}}
	return [menuItem autorelease];
}

-(void)openFeed:(id)sender
{
	NSString *cachedPath = [self valueForKey:@"cachedPath"];
	if(cachedPath && [[NSFileManager defaultManager] fileExistsAtPath:cachedPath])
		[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:cachedPath]];
	else
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[self valueForKey:@"url"]]];
}

-(NSComparisonResult)dateCompare:(RSSItem *)item
{
	return [[item date] compare:[self date]];
}

#pragma mark -
#pragma mark SubLinks

-(void)addSubLinkEntry:(SubLink *)subLink
{
    NSSet *changedObjects = [[NSSet alloc] initWithObjects:&subLink count:1];
    [self willChangeValueForKey:@"subLinks"
				withSetMutation:NSKeyValueUnionSetMutation
				   usingObjects:changedObjects];
    [[self primitiveValueForKey: @"subLinks"] addObject:subLink];
    [self didChangeValueForKey:@"subLinks"
			   withSetMutation:NSKeyValueUnionSetMutation
				  usingObjects:changedObjects];
    [changedObjects release];
}

-(void)createRdarLinksFromString:(NSString *)string
{
	while(1){
		NSRange rdarRange = [string rangeOfString:@"rdar://"];
		if(rdarRange.location == NSNotFound)
			return;
		
		NSRange lineRange = [string lineRangeForRange:rdarRange];
		NSString *rdar = [string substringWithRange:lineRange];
		NSString *link = nil;
		NSString *descr = nil;
		string = [string substringFromIndex:lineRange.location + lineRange.length];
		
		NSRange regularRange = [rdar rangeOfString:@"<rdar://"];
		NSString *substr = nil;
		NSRange endRange;
		if(regularRange.location != NSNotFound){
			substr = [rdar substringFromIndex:regularRange.location];
			endRange = [substr rangeOfString:@">"];
		} else {
			regularRange = [rdar rangeOfString:@"rdar://"];
			substr = [rdar substringFromIndex:regularRange.location];
			endRange = [substr rangeOfString:@" "];
		}
		link = [substr substringWithRange:NSMakeRange(1, endRange.location - 1)];
		descr = [substr substringWithRange:NSMakeRange(endRange.location + endRange.length, [substr length] - (endRange.location + endRange.length))];
		
		SubLink *subLink = [NSEntityDescription insertNewObjectForEntityForName:@"SubLink"
														 inManagedObjectContext:[self managedObjectContext]];
		[subLink setValue:link forKeyPath:@"link"];
		[subLink setValue:descr forKeyPath:@"text"];
		[self addSubLinkEntry:subLink];
	}
}

-(void)createURLLinksFromString:(NSString *)string
{
	while(1){
		NSRange rdarRange = [string rangeOfString:@"http://"];
		if(rdarRange.location == NSNotFound)
			return;
		
		NSRange lineRange = [string lineRangeForRange:rdarRange];
		NSString *rdar = [string substringWithRange:lineRange];
		NSString *link = nil;
		string = [string substringFromIndex:lineRange.location + lineRange.length];
		
		NSRange regularRange = [rdar rangeOfString:@"<http://"];
		NSString *substr = nil;
		NSRange endRange;
		if(regularRange.location != NSNotFound){
			substr = [rdar substringFromIndex:regularRange.location];
			endRange = [substr rangeOfString:@">"];
		} else {
			regularRange = [rdar rangeOfString:@"http://"];
			substr = [rdar substringFromIndex:regularRange.location];
			endRange = [substr rangeOfString:@" "];
		}
		link = [substr substringWithRange:NSMakeRange(1, endRange.location - 1)];
		
		SubLink *subLink = [NSEntityDescription insertNewObjectForEntityForName:@"SubLink"
														 inManagedObjectContext:[self managedObjectContext]];
		[subLink setValue:link forKeyPath:@"link"];
		[self addSubLinkEntry:subLink];
	}	
}

-(void)createSubLinksFromString:(NSString *)string
{
	[self createRdarLinksFromString:string];
	[self createURLLinksFromString:string];
}

#pragma mark -
#pragma mark WebView Resources Load Delegate

-(void)webViewFailedWithError:(NSError *)error
{
    // release the connection, and the data object
	if(error){
		NSLog([NSString stringWithFormat:
			@"RSSItem Page Caching: %@ %@", [error localizedDescription],
			[[error userInfo] objectForKey:NSErrorFailingURLStringKey]]);
	}
}

-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	[self webViewFailedWithError:error];
}

-(void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	[self webViewFailedWithError:error];
}

-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	if([[RGDefaults objectForKey:kEnablePageCaching] boolValue]){
		WebArchive *webArchive = [[[webView mainFrame] dataSource] webArchive];
		NSString *cachesFolder = [[NSApp delegate] cachesFolder];
		NSFileManager *fileManager = [NSFileManager defaultManager];
		if ( ![fileManager fileExistsAtPath:cachesFolder isDirectory:NULL] ) {
			[fileManager createDirectoryAtPath:cachesFolder attributes:nil];
		}
		
		NSString *cachedPath = [self valueForKey:@"cachedPath"];
		if(!cachedPath){
			CFUUIDRef uuid = CFUUIDCreate(NULL);
			NSString *string = (NSString *)CFUUIDCreateString(NULL, uuid);
			CFRelease(uuid);
			NSString *cachePath = [cachesFolder stringByAppendingPathComponent:string];
			[string release];
			cachedPath = [cachePath stringByAppendingPathExtension:@"webarchive"];
			[self setValue:cachedPath forKey:@"cachedPath"];
		}
		NSURL *cacheURL = [NSURL fileURLWithPath:cachedPath];
		
		[[webArchive data] writeToURL:cacheURL atomically:NO];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];
	}
}

-(void)webView:(WebView *)sender
	  resource:(id)identifier
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
fromDataSource:(WebDataSource *)dataSource
{
    if ([challenge previousFailureCount] == 0) {
        NSURLCredential *newCredential;
        newCredential=[NSURLCredential credentialWithUser:[[self valueForKey:@"feed"] login]
                                                 password:[[self valueForKey:@"feed"] password]
                                              persistence:NSURLCredentialPersistenceForSession];
        [[challenge sender] useCredential:newCredential forAuthenticationChallenge:challenge];
    } else {
        [[challenge sender] cancelAuthenticationChallenge:challenge];
        // inform the user that the user name and password
        // in the preferences are incorrect
		NSLog(@"RSSItem Page Caching: Invalid Username or Password");
    }
}


@end
