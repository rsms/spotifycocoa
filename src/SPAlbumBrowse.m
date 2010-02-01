//
//  SPAlbumBrowse.m
//  Explorify
//
//  Created by Amanda Rösler on 2010-01-31.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import "SPAlbumBrowse.h"
#import "SPSession.h"

@interface SPAlbumBrowse ()
@property (copy) SPBrowseCompletion callback;
@property (readwrite) sp_albumbrowse *browse;
@end

static void SPAlbumComplete(sp_albumbrowse *result, void *userdata)
{
	SPAlbumBrowse *browse = (id)userdata;
	browse.browse = result;
	browse.callback(browse);
}


@implementation SPAlbumBrowse
@synthesize callback, browse;

+(void)browseAlbum:(sp_album *)album done:(SPBrowseCompletion)doneCallback;
{
	SPAlbumBrowse *spbrowse = [[SPAlbumBrowse alloc] init];
	spbrowse.callback = doneCallback;
	sp_albumbrowse_create([[SPSession sharedSession] session], album, SPAlbumComplete, spbrowse);
}
-(void)dealloc;
{
	self.callback = nil;
	if(browse)
		sp_albumbrowse_release(browse);
	[super dealloc];
}
@end
