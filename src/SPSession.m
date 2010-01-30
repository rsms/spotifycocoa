#import "SPSession.h"
#import "SPUser.h"

static NSString *kSCErrorDomain = @"com.spotify.libspotifycocoa.error";

static void *_appKey = NULL;
static size_t _appKeySize = 0;
static char *_cacheLocation = NULL;
static char *_settingsLocation = NULL;
static char *_userAgent = NULL;
static id _sharedSession = NULL;

// -------------
// NSError additions

@interface NSError (SCAdditions)
+ (NSError *)spotifyErrorWithDescription:(NSString *)msg code:(NSInteger)code;
+ (NSError *)spotifyErrorWithCode:(sp_error)code;
+ (NSError *)spotifyErrorWithDescription:(NSString *)msg;
+ (NSError *)spotifyErrorWithCode:(NSInteger)code format:(NSString *)format, ...;
+ (NSError *)spotifyErrorWithFormat:(NSString *)format, ...;
@end
@implementation NSError (SCAdditions)
+ (NSError *)spotifyErrorWithDescription:(NSString *)msg code:(NSInteger)code {
	return [NSError errorWithDomain:kSCErrorDomain code:code userInfo:[NSDictionary dictionaryWithObject:msg forKey:NSLocalizedDescriptionKey]];
}
+ (NSError *)spotifyErrorWithCode:(sp_error)code {
	return [NSError spotifyErrorWithDescription:[NSString stringWithUTF8String:sp_error_message(code)] code:code];
}
+ (NSError *)spotifyErrorWithDescription:(NSString *)msg {
	return [NSError spotifyErrorWithDescription:msg code:0];
}
+ (NSError *)spotifyErrorWithCode:(NSInteger)code format:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError spotifyErrorWithDescription:msg code:code];
}
+ (NSError *)spotifyErrorWithFormat:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError spotifyErrorWithDescription:msg code:0];
}
@end

// -------------
// Callback proxies

#define CB_INVOKE_DELEGATE1(_sess, _sign) \
	do {\
		id _delegate = _sess.delegate;\
		if (_delegate && [_delegate respondsToSelector:@selector(_sign)]) {\
			[_delegate _sign _sess];\
		}\
	} while(0)

#define CB_INVOKE_DELEGATE2(_sess, _signPart1, _signPart2, _arg) \
	do {\
		id _delegate = _sess.delegate;\
		if (_delegate && [_delegate respondsToSelector:@selector(_signPart1 _signPart2)]) {\
			[_delegate _signPart1 _sess _signPart2 _arg];\
		}\
	} while(0)

/* ------------------------  BEGIN SESSION CALLBACKS  ---------------------- */
/**
 * This callback is called when the user was logged in, but the connection to
 * Spotify was dropped for some reason.
 */
static void connection_error(sp_session *session, sp_error error) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE2(sess, session:, connectionError:, [NSError spotifyErrorWithCode:error]);
}

/**
 * This callback is called when an attempt to login has succeeded or failed.
 */
static void logged_in(sp_session *session, sp_error error) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);

	if (SP_ERROR_OK != error) {
		CB_INVOKE_DELEGATE2(sess, session:, loginDidFailWithError:, [NSError spotifyErrorWithCode:error]);
		return;
	}

	// XXX DEBUG Let us print the nice message...
	sp_user *me = sp_session_user(session);
	const char *my_name = (sp_user_is_loaded(me) ?
												 sp_user_display_name(me) :
												 sp_user_canonical_name(me));
	NSLog(@"Logged in as user %s", my_name);

	CB_INVOKE_DELEGATE1(sess, sessionDidBegin:);
}

/**
 * This callback is called when the session has logged out of Spotify.
 *
 * @sa sp_session_callbacks#logged_out
 */
static void logged_out(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE1(sess, sessionDidEnd:);
}

/**
 * Called when processing needs to take place on the main thread.
 *
 * You need to call sp_session_process_events() in the main thread to get
 * libspotify to do more work. Failure to do so may cause request timeouts,
 * or a lost connection.
 *
 * The most straight forward way to do this is using Unix signals. We use
 * SIGIO. signal(7) in Linux says "I/O now possible" which sounds reasonable.
 *
 * @param[in]  session    Session
 *
 * @note This function is called from an internal session thread - you need
 * to have proper synchronization!
 */
static void notify_main_thread(sp_session *session) {
	NSLog(@"TODO %s", __func__);
	//pthread_kill(g_main_thread, SIGIO);
}

/**
 * This callback is called for log messages.
 */
static void log_message(sp_session *session, const char *data) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE2(sess, session:, logMessage:, [NSString stringWithUTF8String:data]);
}

/**
 * Callback called when libspotify has new metadata available
 *
 * If you have metadata cached outside of libspotify, you should purge
 * your caches and fetch new versions.
 */
static void metadata_updated(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE1(sess, sessionMetadataChanged:);
}

/**
 * Called when the access point wants to display a message to the user
 *
 * In the desktop client, these are shown in a blueish toolbar just below the
 * search box.
 *
 * @param[in]  session    Session
 * @param[in]  message    String in UTF-8 format.
 */
static void message_to_user(sp_session *session, const char *msg) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE2(sess, session:, presentMessage:, [NSString stringWithUTF8String:msg]);
}


/**
 * Called when there is decompressed audio data available.
 *
 * @param[in]  session    Session
 * @param[in]  format     Audio format descriptor sp_audioformat
 * @param[in]  frames     Points to raw PCM data as described by \p format
 * @param[in]  num_frames Number of available samples in \p frames.
 *                        If this is 0, a discontinuity has occured (such as after a seek). The application
 *                        should flush its audio fifos, etc.
 *
 * @return                Number of frames consumed.
 *                        This value can be used to rate limit the output from the library if your
 *                        output buffers are saturated. The library will retry delivery in about 100ms.
 *
 * @note This function is called from an internal session thread - you need to have proper synchronization!
 *
 * @note This function must never block. If your output buffers are full you must return 0 to signal
 *       that the library should retry delivery in a short while.
 */
static int music_delivery(sp_session *session, const sp_audioformat *format, const void *frames, int num_frames) {
	NSLog(@"TODO %s", __func__);
	return num_frames;
}

/**
 * Music has been paused because only one account may play music at the same time.
 *
 * @param[in]  session    Session
 */
static void play_token_lost(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE1(sess, sessionPlayTokenLost:);
}

/**
 * End of track.
 * Called when the currently played track has reached its end.
 *
 * @note This function is invoked from the same internal thread
 * as the music delivery callback
 *
 * @param[in]  session    Session
 */
static void end_of_track(sp_session *session) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	CB_INVOKE_DELEGATE1(sess, sessionPlaybackDidEnd:);
}

static sp_session_callbacks _callbacks = {
	&logged_in,
	&logged_out,
	&metadata_updated,
	&connection_error,
	&message_to_user,
	&notify_main_thread,
	&music_delivery,
	&play_token_lost,
	&log_message,
	&end_of_track
};

// -------------

@implementation SPSession

@synthesize username=_username, password=_password, delegate=_delegate;

+ (void)setupWithApplicationKey:(NSData *)appkey
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgent
{
	// Copy app key
	if (_appKey) {
		free(_appKey);
		_appKey = NULL;
	}
	_appKeySize = [appkey length];
	_appKey = malloc(_appKeySize);
	assert(memcpy(_appKey, [appkey bytes], _appKeySize) != NULL);

	// Save ref to cache dir
	NSString *s = cacheDirname ? cacheDirname : NSTemporaryDirectory();
	if (_cacheLocation) free((void *)_cacheLocation);
	assert((_cacheLocation = strdup([s UTF8String])) != NULL);

	// Save ref to settings dir
	s = settingsDirname ? settingsDirname : NSTemporaryDirectory();
	if (_settingsLocation) free(_settingsLocation);
	assert((_settingsLocation = strdup([s UTF8String])) != NULL);

	// Save ref to settings dir
	if (_userAgent) free(_userAgent);
	assert((_userAgent = strdup(userAgent ? [userAgent UTF8String] : "spotify-cocoa")) != NULL);
}

+ (id)sharedSession {
	@synchronized(self) {
		if (_sharedSession == NULL)
			_sharedSession = [[self alloc] init];
		return _sharedSession;
	}
}

#pragma mark -
#pragma mark Initialization and finalization


- (int)_initSession {
	sp_error error;

	// Always do this. It allows libspotify to check for
	// header/library inconsistencies.
	_config.api_version = SPOTIFY_API_VERSION;

	// The path of the directory to store the cache. This must be specified.
	// Please read the documentation on preferred values.
	assert(_cacheLocation != NULL);
	_config.cache_location = _cacheLocation;

	// The path of the directory to store the settings. This must be specified.
	// Please read the documentation on preferred values.
	assert(_settingsLocation != NULL);
	_config.settings_location = _settingsLocation;

	// The key of the application. They are generated by Spotify,
	// and are specific to each application using libspotify.
	assert(_appKey != NULL);
	_config.application_key = _appKey;
	assert(_appKeySize > 0);
	_config.application_key_size = _appKeySize;

	// This identifies the application using some
	// free-text string [1, 255] characters.
	assert(_userAgent != NULL);
	_config.user_agent = _userAgent;

	// Register the callbacks.
	_config.callbacks = &_callbacks;

	// Reference to ourselves
	_config.userdata = (void *)self;

	// Initialize session
	assert(_session == NULL);
	error = sp_session_init(&_config, &_session);

	if (SP_ERROR_OK != error) {
		fprintf(stderr, "failed to create session: %s\n",
						sp_error_message(error));
		return error;
	}

	if (_delegate && [_delegate respondsToSelector:@selector(sessionWillBegin:)]) {
		[_delegate sessionWillBegin:self];
	}

	return error;
}

#pragma mark -
#pragma mark Properties

- (SPUser *)user {
	@synchronized(self) {
		if (!_user) {
			_user = [[SPUser alloc] initWithUserStruct:sp_session_user(_session)];
		}
		return _user;
	}
}

@end
