@interface SPUser : NSObject {
	sp_user *_user;
	NSString *_username;
}

@property(readonly) BOOL isLoaded;
@property(readonly) NSString *username;

- (id)initWithUserStruct:(sp_user *)user;

@end
