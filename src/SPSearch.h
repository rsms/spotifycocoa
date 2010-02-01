//
//  SPSearch.h
//  Explorify
//
//  Created by Amanda Rösler on 2010-01-31.
//  Copyright 2010 Apple Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <spotify/api.h>

@class SPSearch;

typedef void(^SPSearchCompletion)(SPSearch *searchResult);

@interface SPSearch : NSObject {
	sp_search *search;
	SPSearchCompletion callback;
}
@property (readonly) sp_search *search;

+(void)makeSearch:(NSString*)searchFor numberOfTracks:(int)trackCount numberOfAlbums:(int)albumCount numberOfArtists:(int)artistCount done:(SPSearchCompletion)doneCallback;

@end
