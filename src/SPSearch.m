//
//  SPSearch.m
//  Explorify
//
//  Created by Amanda Rösler on 2010-01-31.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import "SPSearch.h"
#import "SPSession.h"

@interface SPSearch ()
@property (copy) SPSearchCompletion callback;
@property (readwrite) sp_search *search;
@end

static void SPSearchComplete(sp_search *result, void *userdata)
{
	SPSearch *search = (id)userdata;
	search.search = result;
	search.callback(search);
}


@implementation SPSearch
@synthesize callback, search;

+(void)makeSearch:(NSString *)searchFor numberOfTracks:(int)trackCount numberOfAlbums:(int)albumCount numberOfArtists:(int)artistCount done:(SPSearchCompletion)doneCallback;
{
	SPSearch *spsearch = [[SPSearch alloc] init];
	spsearch.callback = doneCallback;
	
	sp_search_create([[SPSession sharedSession] session], [searchFor UTF8String], 0, trackCount, 0, albumCount, 0, artistCount, SPSearchComplete, spsearch);

}
-(void)dealloc;
{
	self.callback = nil;
	if(search)
		sp_search_release(search);
	[super dealloc];
}
@end