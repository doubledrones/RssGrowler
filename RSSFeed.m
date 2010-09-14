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

#import "RSSFeed.h"
#import "RSSItem.h"
#import "RSSGrowlerController.h"

@implementation RSSFeed

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[feedData release];
	[connection release];
	[super dealloc];
}

-(void)awakeFromInsert
{
	[self setValue:[NSDate distantPast] forKeyPath:@"lastFetchDate"];
}

-(void)awakeFromFetch
{
	if(![[NSUserDefaults standardUserDefaults] boolForKey:kShowGrowlsOnLaunch])
		[self setValue:[NSDate distantPast] forKeyPath:@"lastFetchDate"];
	
	NSString *generator = [self valueForKey:@"generator"];
	if(generator){
		isTracFeed = ([generator rangeOfString:@"Trac"].location != NSNotFound);
		isTwitterFeed = ([generator rangeOfString:@"Twitter"].location != NSNotFound);
	}
	[self checkFeed];
}

-(void)checkFeed
{
	if(connection){
		[connection cancel];
		[connection release];
	}

	if([self url]){
		if([[self url] rangeOfString:@"twitter.com"].location != NSNotFound){
			[self setValue:@"Twitter" forKey:@"generator"];
			isTwitterFeed = YES;
		}
		
		NSURL *realURL = [NSURL URLWithString:[self url]];
		if(![realURL isFileURL]){
			if([realURL host] == nil)
				return;
		}
		
		if(realURL){
			NSURLRequest *request = [NSURLRequest requestWithURL:realURL
													 cachePolicy:NSURLRequestReloadIgnoringCacheData
												 timeoutInterval:60.0];
			connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
			[feedData release];
			feedData = [[NSMutableData data] retain];
			[self setErrorMessage:nil];
		}
	}
	[self cleanupOldItems];
}

-(void)cleanupOldItems
{
	NSSet *feedEntries = [self feedEntries];
	unsigned count = [feedEntries count];
	unsigned maxNum = (unsigned)[[RGDefaults objectForKey:kMaxEntryHistory] intValue];
	if(count > maxNum){
		NSArray *feedArray = [[feedEntries allObjects] sortedArrayUsingSelector:@selector(dateCompare:)];
		NSRange removeRange = NSMakeRange(maxNum, count - maxNum);
		NSSet *feedEntriesForRemoval = [NSSet setWithArray:[feedArray subarrayWithRange:removeRange]];
		id e = [feedEntriesForRemoval objectEnumerator];
		id item;
		while(item = [e nextObject]){
			[item removePageCache];
		}
		[self removeFeedEntries:feedEntriesForRemoval];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];
	}
}

-(NSSet *)cachedIDs
{
	NSMutableSet *cachedIDs = [NSMutableSet set];
	id e = [[self feedEntries] objectEnumerator];
	id item;
	while(item = [e nextObject]){
		NSString *cachedID = [item cachedID];
		if(cachedID)
			[cachedIDs addObject:cachedID];
	}
	return cachedIDs;
}
-(NSArray *)firstFeedItems:(unsigned)count
{
	if([[self valueForKey:@"showInRecentList"] boolValue]){
		NSArray *feedArray = [[[self feedEntries] allObjects] sortedArrayUsingSelector:@selector(dateCompare:)];
		return [feedArray subarrayWithRange:NSMakeRange(0, MIN(count, [feedArray count]))];
	} else
		return [NSArray array];
}

-(NSMenuItem *)feedMenuItem:(NSSet *)topSet
{
	NSString *menuName = [self name];
	if(!menuName)
		menuName = [self url];
	if(!menuName)
		menuName = @"Feed";
	if(!didConnect)
		menuName = [NSString stringWithFormat:@"-%@", menuName];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:menuName];
	
	NSSet *feedEntries = [self feedEntries];
	if([[RGDefaults objectForKey:kHideTopFromHistory] boolValue]){
		NSMutableSet *feedMut = [NSMutableSet setWithSet:feedEntries];
		[feedMut minusSet:topSet];
		feedEntries = feedMut;
	}
	
	NSArray *feedArray = [[feedEntries allObjects] sortedArrayUsingSelector:@selector(dateCompare:)];
	unsigned maxNum = (unsigned)[[RGDefaults objectForKey:kMaxEntryHistory] intValue];
	id e = [feedArray objectEnumerator];
	id item;
	unsigned count = 0;
	while(item = [e nextObject]){
		if(count++ >= maxNum)
			break;
		[menu addItem:[item menuItem]];
	}

	NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:menuName
													  action:@selector(openFeed:)
											   keyEquivalent:@""];
	[menuItem setTarget:self];
	if([feedEntries count] > 0)
		[menuItem setSubmenu:menu];

	[menu autorelease];
	
	return [menuItem autorelease];
}

-(void)openFeed:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[self valueForKey:@"link"]]];
}

-(NSString *)name
{
	[self willAccessValueForKey:@"name"];
    NSString *value = [self primitiveValueForKey:@"name"];
    [self didAccessValueForKey:@"name"];
    return value;
}

-(void)setName:(NSString *)string
{
	[self willChangeValueForKey:@"name"];
    [self setPrimitiveValue:string forKey:@"name"];
    [self didChangeValueForKey:@"name"];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"feedNameChanged" object:nil];
}

-(NSString *)url
{
	[self willAccessValueForKey:@"url"];
    NSString *value = [self primitiveValueForKey:@"url"];
    [self didAccessValueForKey:@"url"];
    return value;	
}

-(void)setUrl:(NSString *)string
{
	NSString *feedLoc = @"feed";
	if([string hasPrefix:feedLoc]){
		NSMutableString *str = [NSMutableString stringWithString:string];
		[str replaceCharactersInRange:NSMakeRange(0, [feedLoc length]) withString:@"http"];
		string = str;
	}

	[self willChangeValueForKey:@"url"];
    [self setPrimitiveValue:string forKey:@"url"];
    [self didChangeValueForKey:@"url"];
	
	[self checkFeed];
}

-(NSString *)login
{
	[self willAccessValueForKey:@"login"];
    NSString *value = [self primitiveValueForKey:@"login"];
    [self didAccessValueForKey:@"login"];
    return value;
}

-(void)setLogin:(NSString *)string
{
	[self willChangeValueForKey:@"login"];
    [self setPrimitiveValue:string forKey:@"login"];
    [self didChangeValueForKey:@"login"];

	if(![self didConnect])
		[self checkFeed];
}

-(NSString *)password
{
	[self willAccessValueForKey:@"password"];
    NSString *value = [self primitiveValueForKey:@"password"];
    [self didAccessValueForKey:@"password"];
    return value;	
}

-(void)setShowInRecentList:(BOOL)aBool
{
	[self willChangeValueForKey:@"showInRecentList"];
    [self setPrimitiveValue:[NSNumber numberWithBool:aBool] forKey:@"showInRecentList"];
    [self didChangeValueForKey:@"showInRecentList"];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];	
}

-(BOOL)showInRecentList
{
	[self willAccessValueForKey:@"showInRecentList"];
    NSNumber *value = [self primitiveValueForKey:@"showInRecentList"];
    [self didAccessValueForKey:@"showInRecentList"];
    return [value boolValue];
}

-(void)setPassword:(NSString *)string
{
	[self willChangeValueForKey:@"password"];
    [self setPrimitiveValue:string forKey:@"password"];
    [self didChangeValueForKey:@"password"];

	if(![self didConnect])
		[self checkFeed];
}

-(void)setErrorMessage:(NSString *)string
{
	[self willChangeValueForKey:@"errorMessage"];
    [self setPrimitiveValue:string forKey:@"errorMessage"];
    [self didChangeValueForKey:@"errorMessage"];

	if(string){
		if([string isEqualToString:@""])
			[self setDidConnect:YES];
		else
			[self setDidConnect:NO];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];
	}
}

-(BOOL)didConnect
{
	return didConnect;
}

-(BOOL)isTracFeed
{
	return isTracFeed;
}

-(BOOL)isTwitterFeed
{
	return isTwitterFeed;
}

-(void)setDidConnect:(BOOL)aBool
{
	didConnect = aBool;
	[self willChangeValueForKey:@"didConnectString"];
	if([self didConnect])
		[self setPrimitiveValue:@"Yes" forKey:@"didConnectString"];
	else
		[self setPrimitiveValue:@"No" forKey:@"didConnectString"];
    [self didChangeValueForKey:@"didConnectString"];
}

-(NSSet *)feedEntries
{
	[self willAccessValueForKey:@"feedEntries"];
    NSSet *feedEntries = [self primitiveValueForKey:@"feedEntries"];
    [self didAccessValueForKey:@"feedEntries"];
    return feedEntries;	
}

-(void)addFeedEntry:(RSSItem *)item
{
    NSSet *changedObjects = [[NSSet alloc] initWithObjects:&item count:1];
    [self willChangeValueForKey:@"feedEntries"
				withSetMutation:NSKeyValueUnionSetMutation
				   usingObjects:changedObjects];
    [[self primitiveValueForKey: @"feedEntries"] addObject:item];
    [self didChangeValueForKey:@"feedEntries"
			   withSetMutation:NSKeyValueUnionSetMutation
				  usingObjects:changedObjects];
    [changedObjects release];
}

-(void)removeFeedEntry:(RSSItem *)item
{
    NSSet *changedObjects = [[NSSet alloc] initWithObjects:&item count:1];
    [self willChangeValueForKey:@"feedEntries"
				withSetMutation:NSKeyValueMinusSetMutation
				   usingObjects:changedObjects];
    [[self primitiveValueForKey: @"feedEntries"] removeObject: item];
    [self didChangeValueForKey:@"feedEntries"
			   withSetMutation:NSKeyValueMinusSetMutation
				  usingObjects:changedObjects];
    [changedObjects release];
}

-(void)removeFeedEntries:(NSSet *)feedEntriesToRemove
{
    [self willChangeValueForKey:@"feedEntries"
				withSetMutation:NSKeyValueMinusSetMutation
				   usingObjects:feedEntriesToRemove];
    [[self primitiveValueForKey:@"feedEntries"] minusSet:feedEntriesToRemove];
    [self didChangeValueForKey:@"feedEntries"
			   withSetMutation:NSKeyValueMinusSetMutation
				  usingObjects:feedEntriesToRemove];
}

-(void)parseDocument:(NSXMLDocument *)document
{
	NSXMLNode *rootNode = [document rootElement];
	if([[rootNode name] isEqualToString:@"rss"] || [[rootNode name] isEqualToString:@"rdf:RDF"]){
		NSArray *children = [rootNode children];
		id e = [children objectEnumerator];
		id anObject;
		while(anObject = [e nextObject]){
			if([[anObject name] isEqualToString:@"channel"]){
				[self parseChannel:anObject];
			}
		}
		if([[rootNode name] isEqualToString:@"rdf:RDF"])
			[self parseItems:rootNode];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:@"updateMenus" object:nil];	
}

-(void)parseChannel:(NSXMLNode *)channel
{
	NSArray *children = [channel children];
	id e = [children objectEnumerator];
	id anObject;
	while(anObject = [e nextObject]){
		NSString *name = [anObject name];
		NSString *value = [anObject objectValue];
		if([name isEqualToString:@"title"]){
			if(![self name] || [[self name] isEqualToString:@""])
				[self setName:value];
		}
		if([name isEqualToString:@"link"]){
			[self setPrimitiveValue:value forKey:@"link"];
		}
		if([name isEqualToString:@"generator"]){
			[self setValue:value forKey:@"generator"];
			isTracFeed = ([value rangeOfString:@"Trac"].location != NSNotFound);
			isTwitterFeed = ([value rangeOfString:@"Twitter"].location != NSNotFound);
		}
	}
	[self parseItems:channel];
}

-(void)parseItems:(NSXMLNode *)node
{
	NSArray *children = [node children];
	NSEnumerator *e = [children objectEnumerator];
	NSDate *newestDate = nil;
	id anObject;
	while(anObject = [e nextObject]){
		NSString *name = [anObject name];
		if([name isEqualToString:@"item"]){
			NSDate *itemDate = [self parseItem:anObject];
			if(!newestDate || ([itemDate compare:newestDate] == NSOrderedDescending))
				newestDate = itemDate;
		}
	}		
	
	[self setValue:newestDate forKeyPath:@"lastFetchDate"];
}

-(NSDate *)parseItem:(NSXMLNode *)item
{
	NSArray *children = [item children];
	id e = [children reverseObjectEnumerator];
	id anObject;
	
	NSString *itemAuthor = nil;
	NSDate *itemPubDate = nil;
	NSString *itemTitle = nil;
	NSString *itemLink = nil;
	NSString *itemGuid = nil;
	NSString *itemDescription = nil;

	while(anObject = [e nextObject]){
			NSString *name = [anObject name];
		NSString *value = [anObject stringValue];
		if([name isEqualToString:@"author"])
			itemAuthor = value;
		if([name isEqualToString:@"pubDate"] || [name isEqualToString:@"dc:date"])
			itemPubDate = [NSDate dateWithNaturalLanguageString:[anObject objectValue]];
		if([name isEqualToString:@"title"] || [name isEqualToString:@"dc:title"])
			itemTitle = value;
		if([name isEqualToString:@"link"] || [name isEqualToString:@"dc:source"])
			itemLink = value;
		if([name isEqualToString:@"guid"] || [name isEqualToString:@"dc:date"])
			itemGuid = value;
		if([name isEqualToString:@"description"])
			itemDescription = value;
	}
	
	NSDate *lastFetchDate = [self valueForKey:@"lastFetchDate"];
	if([itemPubDate compare:lastFetchDate] == NSOrderedDescending || !lastFetchDate){
		NSManagedObjectContext *moc = [self managedObjectContext];
		NSEntityDescription *entityDescription = [NSEntityDescription entityForName:@"RSSItem"
															 inManagedObjectContext:moc];
		NSFetchRequest *request = [[[NSFetchRequest alloc] init] autorelease];
		[request setEntity:entityDescription];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"guid like %@", itemGuid];
		[request setPredicate:predicate];
		NSError *error = nil;
		NSArray *array = [moc executeFetchRequest:request error:&error];
		if(error)
			NSLog([error description]);
		
		if([array count] == 0){
			RSSItem *item = [NSEntityDescription insertNewObjectForEntityForName:@"RSSItem"
														  inManagedObjectContext:moc];
			[item setValue:itemAuthor forKeyPath:@"author"];
			[item setValue:itemPubDate forKeyPath:@"date"];
			[item setValue:itemTitle forKeyPath:@"title"];
			[item setValue:itemLink forKeyPath:@"url"];
			[item setValue:itemGuid forKeyPath:@"guid"];
			[item setText:itemDescription];
			
			[self addFeedEntry:item];
			
			if(!lastFetchDate || ![lastFetchDate isEqualToDate:[NSDate distantPast]]){ // otherwise this is a first time load
				[[NSNotificationCenter defaultCenter] postNotificationName:@"newRssItem"
																	object:nil
																  userInfo:[NSDictionary dictionaryWithObject:item
																									   forKey:@"RSSItem"]];
			}
		}
	}
	
	return itemPubDate;
}

#pragma mark -
#pragma mark NSURLConnection Delegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    // this method is called when the server has determined that it
    // has enough information to create the NSURLResponse
	
    // it can be called multiple times, for example in the case of a 
    // redirect, so each time we reset the data.
    [feedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // append the new data to the receivedData
    [feedData appendData:data];
}

- (void)connection:(NSURLConnection *)aConnection 
  didFailWithError:(NSError *)error
{
    // release the connection, and the data object
	if(error){
		[self setErrorMessage:[NSString stringWithFormat:
			@"Failed %@ %@", [error localizedDescription],
			[[error userInfo] objectForKey:NSErrorFailingURLStringKey]]];
	}

    [aConnection release];
	connection = nil;
    [feedData release];
	feedData = nil;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection
{
    // do something with the data
	NSError *error;
	NSXMLDocument *feedDoc = [[NSXMLDocument alloc] initWithData:feedData options:NSXMLDocumentTidyHTML error:&error];
    // release the connection, and the data object
    [aConnection release];
	connection = nil;
    [feedData release];
	feedData = nil;
	
	if(error)
		[self setErrorMessage:[error localizedDescription]];
	else
		[self setErrorMessage:@""];
	
	[self performSelector:@selector(parseDocument:) withObject:[feedDoc autorelease] afterDelay:0.0];
}

-(void)connection:(NSURLConnection *)connection
        didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge previousFailureCount] == 0 && [self login] && [self password]) {
        NSURLCredential *newCredential;
        newCredential=[NSURLCredential credentialWithUser:[self login]
                                                 password:[self password]
                                              persistence:NSURLCredentialPersistenceNone];
        [[challenge sender] useCredential:newCredential
               forAuthenticationChallenge:challenge];
    } else {
        [[challenge sender] cancelAuthenticationChallenge:challenge];
        // inform the user that the user name and password
        // in the preferences are incorrect
		[self setErrorMessage:@"Invalid Username or Password"];
    }
}

-(NSCachedURLResponse *)connection:(NSURLConnection *)connection
                 willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
	return nil;
}

@end

