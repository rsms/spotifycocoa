#import "SPSession.h"

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
	return [NSError errorWithDescription:msg code:0];
}
NSError *err = [NSError spotifyErrorWithDescription: code:error];
+ (NSError *)spotifyErrorWithCode:(NSInteger)code format:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError errorWithDescription:msg code:code];
}
+ (NSError *)spotifyErrorWithFormat:(NSString *)format, ... {
	va_list src, dest;
	va_start(src, format);
	va_copy(dest, src);
	va_end(src);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:dest];
	return [NSError errorWithDescription:msg code:0];
}
@end

// -------------
// Callback proxies

/* ------------------------  BEGIN SESSION CALLBACKS  ---------------------- */
/**
 * This callback is called when the user was logged in, but the connection to
 * Spotify was dropped for some reason.
 *
 * @sa sp_session_callbacks#connection_error
 */
static void connection_error(sp_session *session, sp_error error)
{
	fprintf(stderr, "connection to Spotify failed: %s\n",
					sp_error_message(error));
	g_exit_code = 5;
}

/**
 * This callback is called when an attempt to login has succeeded or failed.
 *
 * @sa sp_session_callbacks#logged_in
 */
static void logged_in(sp_session *session, sp_error error)
{
	if (SP_ERROR_OK != error) {
		[_sharedSession loginDidFailWithError:[NSError spotifyErrorWithCode:error]];
		return;
	}

	// Let us print the nice message...
	sp_user *me = sp_session_user(session);
	const char *my_name = (sp_user_is_loaded(me) ?
												 sp_user_display_name(me) :
												 sp_user_canonical_name(me));

	NSLog(@"Logged in as user %s", my_name);

	session_ready(session, g_uri);
	[_sharedSession
}

/**
 * This callback is called when the session has logged out of Spotify.
 *
 * @sa sp_session_callbacks#logged_out
 */
static void logged_out(sp_session *session) {
	[_sharedSession didEnd];
}

/**
 * This callback is called from an internal libspotify thread to ask us to
 * reiterate the main loop.
 *
 * The most straight forward way to do this is using Unix signals. We use
 * SIGIO. signal(7) in Linux says "I/O now possible" which sounds reasonable.
 *
 * @sa sp_session_callbacks#notify_main_thread
 */
static void notify_main_thread(sp_session *session) {
	NSLog(@"TODO %s", __func__);
	//pthread_kill(g_main_thread, SIGIO);
}

/**
 * This callback is called for log messages.
 *
 * @sa sp_session_callbacks#log_message
 */
static void log_message(sp_session *session, const char *data) {
	[_sharedSession didReceiveLogMessage:[NSString stringWithUTF8String:data]];
}

static sp_session_callbacks _callbacks = {
	&logged_in,
	&logged_out,
	&metadata_updated,
	&connection_error,
	NULL,
	&notify_main_thread,
	NULL,
	NULL,
	&log_message
};

// -------------

@implementation SPSession

@synthesize username=_username, password=_password;

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
	sp_session_callbacks _callbacks;
	memset(&_callbacks, 0, sizeof(_callbacks));

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

	// Initialize session
	assert(_session == NULL);
	error = sp_session_init(&_config, &_session);

	if (SP_ERROR_OK != error) {
		fprintf(stderr, "failed to create session: %s\n",
						sp_error_message(error));
		return error;
	}

	return error;
}

@end
