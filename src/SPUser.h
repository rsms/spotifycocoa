#import <spotify/api.h>
@interface SPUser : NSObject {
	sp_user *_user;
}

- (id)initWithUserStruct:(sp_user *)user;

@end
