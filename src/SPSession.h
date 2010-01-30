#import "spotify_api.h"

#if 0
sp_error sp_session_init(const sp_session_config *config, sp_session **sess);
sp_error sp_session_login(sp_session *session, const char *username, const char *password);
sp_user * sp_session_user(sp_session *session);
sp_error sp_session_logout(sp_session *session);
sp_connectionstate sp_session_connectionstate(sp_session *session);
void * sp_session_userdata(sp_session *session);
void sp_session_process_events(sp_session *session, int *next_timeout);
sp_error sp_session_player_load(sp_session *session, sp_track *track);
sp_error sp_session_player_play(sp_session *session, bool play);
sp_error sp_session_player_seek(sp_session *session, int offset);
void sp_session_player_unload(sp_session *session);
sp_playlistcontainer * sp_session_playlistcontainer(sp_session *session);
#endif

@interface SPSession : NSObject {
	sp_session_config _config;
	sp_session *_session;
	NSString *_username;
	NSString *_password;
}
@property(assign) NSString *username, *password;

+ (void)setupWithApplicationKey:(NSData *)appkey
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgentName;

+ (id)sharedSession;

- (void)didReceiveLogMessage:(NSString *)message;
- (void)didEnd;

@end
