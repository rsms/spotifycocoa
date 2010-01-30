#import "SPUser.h"

@implementation SPUser

- (id)initWithUserStruct:(sp_user *)user {
	self = [super init];
	_user = user;
	return self;
}

@end
