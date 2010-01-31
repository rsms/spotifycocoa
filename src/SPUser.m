#import "SPUser.h"

@implementation SPUser

- (id)initWithUserStruct:(sp_user *)user {
	self = [super init];
	_user = user;
	return self;
}

- (BOOL)isLoaded {
	return _user && !!sp_user_is_loaded(_user);
}

- (NSString *)username {
	if (!_username) {
		_username = [NSString stringWithUTF8String:sp_user_is_loaded(_user) ?
						 sp_user_display_name(_user) : sp_user_canonical_name(_user)];
	}
	return _username;
}

- (NSString *)description {
	return self.username;
}

@end
