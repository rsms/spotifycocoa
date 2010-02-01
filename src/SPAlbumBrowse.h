//
//  SPAlbumBrowse.h
//  Explorify
//
//  Created by Amanda Rösler on 2010-01-31.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <spotify/api.h>

@class SPAlbumBrowse;

typedef void(^SPBrowseCompletion)(SPAlbumBrowse *browseResult);

@interface SPAlbumBrowse : NSObject {
	sp_albumbrowse *browse;
	SPBrowseCompletion callback;
}
@property (readonly) sp_albumbrowse *browse;

+(void)browseAlbum:(sp_album *)album done:(SPBrowseCompletion)doneCallback;



@end
