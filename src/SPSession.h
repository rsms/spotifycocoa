#import <Spotify/api.h>

@class SPUser;
@protocol SPSessionDelegate;

@interface SPSession : NSObject {
	sp_session_config _config;
	sp_session *_session;
	SPUser *_user;
	NSObject<SPSessionDelegate> *_delegate;
	CFRunLoopRef _runloop;
	CFRunLoopSourceRef _runloopSource;
}
@property(readonly) SPUser *user;
@property(assign) NSObject<SPSessionDelegate> *delegate;
@property(readonly) CFRunLoopRef runloop;
@property(readonly) CFRunLoopSourceRef runloopSource;
@property(readonly) sp_session *session;

+ (void)setupWithApplicationKey:(NSData *)appkey
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgentName;

+ (void)setupWithApplicationKey:(const uint8_t *)appkey
											 ofLength:(size_t)appkeyLength
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgentName;

+ (id)sharedSession;

/**
 * @returns true if login was successfully intialized.
 * @note: login success will be indicated by a call to one of the delegate
 *        methods sessionDidBegin: or session:singInError:)
 */
- (BOOL)signInUserNamed:(NSString *)username withPassphrase:(NSString *)passphrase error:(NSError **)err;

@end


@protocol SPSessionDelegate
@optional
- (void)sessionDidInitialize:(SPSession *)session;

- (BOOL)session:(SPSession *)session shouldBeginForUserNamed:(NSString *)username;
- (void)sessionDidBegin:(SPSession *)session; // user successfully logged in
- (void)sessionDidEnd:(SPSession *)session; // user logged out

- (void)sessionMetadataChanged:(SPSession *)session;
- (void)sessionPlayTokenLost:(SPSession *)session;
- (void)sessionPlaybackDidEnd:(SPSession *)session;

- (void)session:(SPSession *)session logMessage:(NSString *)message;
- (void)session:(SPSession *)session presentMessage:(NSString *)message;

- (void)session:(SPSession *)session setupError:(NSError *)error;
- (void)session:(SPSession *)session connectionError:(NSError *)error;
- (void)session:(SPSession *)session singInError:(NSError *)error;

@end
