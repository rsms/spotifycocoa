@class SPUser;

@interface SPSession : NSObject {
	sp_session_config _config;
	sp_session *_session;
	NSString *_username;
	NSString *_password;
	SPUser *_user;
	id _delegate;
}
@property(assign) NSString *username, *password;
@property(readonly) SPUser *user;
@property(assign) id delegate;

+ (void)setupWithApplicationKey:(NSData *)appkey
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgentName;

+ (id)sharedSession;

@end


@protocol SPSessionDelegate

- (void)sessionWillBegin:(SPSession *)session;
- (void)sessionDidBegin:(SPSession *)session;
- (void)sessionDidEnd:(SPSession *)session;
- (void)sessionMetadataChanged:(SPSession *)session;
- (void)sessionPlayTokenLost:(SPSession *)session;
- (void)sessionPlaybackDidEnd:(SPSession *)session;
- (void)session:(SPSession *)session logMessage:(NSString *)message;
- (void)session:(SPSession *)session presentMessage:(NSString *)message;
- (void)session:(SPSession *)session loginDidFailWithError:(NSError *)error;
- (void)session:(SPSession *)session connectionError:(NSError *)error;

@end
