#import "SPSession.h"
#import "SPUser.h"

static NSString *kSCErrorDomain = @"com.spotify.libspotifycocoa.error";

static const uint8_t *_appKey = NULL;
static size_t _appKeySize = 0;
static NSString *_cacheLocation = NULL;
static NSString *_settingsLocation = NULL;
static NSString *_userAgent = NULL;
static id _sharedSession = NULL;

#define REPLACE_OBJ(target, nval)\
do {\
	id oldval = target;\
	target = nval;\
	if (target)\
		[target retain];\
	if (oldval)\
		[target release];\
} while(0)

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
		id __deleg = _sess.delegate;\
		if (__deleg && [__deleg respondsToSelector:@selector(_sign)]) {\
			[__deleg _sign _sess];\
		}\
	} while(0)

#define CB_INVOKE_DELEGATE2(_sess, _signPart1, _signPart2, _arg) \
	do {\
		id __deleg = _sess.delegate;\
		if (__deleg && [__deleg respondsToSelector:@selector(_signPart1 _signPart2)]) {\
			[__deleg _signPart1 _sess _signPart2 _arg];\
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
static void logged_in(sp_session *session, sp_error status) {
	SPSession *sess = (SPSession *)sp_session_userdata(session);

	if (status != SP_ERROR_OK) {
		CB_INVOKE_DELEGATE2(sess, session:, singInError:, [NSError spotifyErrorWithCode:status]);
		return;
	}

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
	SPSession *sess = (SPSession *)sp_session_userdata(session);
	//NSLog(@"TODO %s", __func__);
	//pthread_kill(g_main_thread, SIGIO);
	CFRunLoopSourceSignal(sess.runloopSource);
	CFRunLoopWakeUp(sess.runloop);
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
#pragma mark -
#pragma mark Runloop source callbacks

struct sp_rlsrc_ctx {
	SPSession *self;
	sp_session *session;
};

/*static const void *rlsrc_retain(const void *info) {
	[(NSObject *)info retain];
	return info;
}

static void rlsrc_release(const void *info) {
	[(NSObject *)info release];
}*/

// Callback invoked when a version 0 CFRunLoopSource object is added to a run
// loop mode.
static void rlsrc_schedule(void *info, CFRunLoopRef rl, CFStringRef mode) {
	//struct sp_rlsrc_ctx *ctx = (struct sp_rlsrc_ctx *)info;
}

// A cancel callback for the run loop source. This callback is called when the
// source is removed from a run loop mode.
static void rlsrc_cancel(void *info, CFRunLoopRef rl, CFStringRef mode) {
	//struct sp_rlsrc_ctx *ctx = (struct sp_rlsrc_ctx *)info;
}

// A perform callback for the run loop source. This callback is called when the
// source has fired.
static void rlsrc_perform(void *info) {
	struct sp_rlsrc_ctx *ctx = (struct sp_rlsrc_ctx *)info;
	int timeout = -1;
	NSLog(@"rlsrc_perform");
	sp_session_process_events(ctx->session, &timeout);
}


// ----------------------------------------------------------------------------

@interface SPSession (Private)
+ (void)_setup_cacheLocation:(NSString *)cacheDirname
						settingsLocation:(NSString *)settingsDirname
									 userAgent:(NSString *)userAgentName;
@end

@implementation SPSession

@synthesize delegate=_delegate, runloop=_runloop, runloopSource=_runloopSource, session=_session;



+ (void)_setup_cacheLocation:(NSString *)cacheDirname
					 settingsLocation:(NSString *)settingsDirname
									userAgent:(NSString *)userAgent
{
	NSArray *paths;
	NSString *basePath;

	// cache dir
	if (!cacheDirname) {
		paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
		basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
		cacheDirname = [basePath stringByAppendingPathComponent:@"com.spotify.embedded"];
	}
	REPLACE_OBJ(_cacheLocation, cacheDirname);

	// settings dir
	if (!settingsDirname) {
		paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
		basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
		settingsDirname = [basePath stringByAppendingPathComponent:@"Spotify (embedded)"];
	}
	REPLACE_OBJ(_settingsLocation, settingsDirname);

	// user agent
	REPLACE_OBJ(_userAgent, userAgent ? userAgent : @"spotify-cocoa");
}

+ (void)setupWithApplicationKey:(const uint8_t *)appkey
											 ofLength:(size_t)appkeyLength
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgent
{
	// Set app key
	_appKeySize = appkeyLength;
	_appKey = appkey;
	[self _setup_cacheLocation:cacheDirname settingsLocation:settingsDirname userAgent:userAgent];
}


+ (void)setupWithApplicationKey:(NSData *)appkey
									cacheLocation:(NSString *)cacheDirname
							 settingsLocation:(NSString *)settingsDirname
											userAgent:(NSString *)userAgent
{
	// Copy app key
	_appKeySize = [appkey length];
	_appKey = malloc(_appKeySize);
	assert(memcpy((uint8_t *)_appKey, [appkey bytes], _appKeySize) != NULL);
	[self _setup_cacheLocation:cacheDirname settingsLocation:settingsDirname userAgent:userAgent];
}


+ (id)sharedSession {
	@synchronized(self) {
		if (_sharedSession == NULL)
			_sharedSession = [[self alloc] init];
	}
	return _sharedSession;
}

#pragma mark -
#pragma mark Initialization and finalization

- (int)_initSettingError:(NSError **)err {
	NSFileManager *fm;
	struct sp_rlsrc_ctx *info = calloc(1, sizeof(struct sp_rlsrc_ctx));
	info->self = self;

	CFRunLoopSourceContext ctx;
	ctx.version = 0;
	ctx.info = (void *)info;
	ctx.retain = NULL;//&rlsrc_retain;
	ctx.release = NULL;//&rlsrc_release;
	ctx.copyDescription = NULL;
	ctx.equal = NULL;
	ctx.hash = NULL;
	ctx.schedule = &rlsrc_schedule;
	ctx.cancel = &rlsrc_cancel;
	ctx.perform = &rlsrc_perform;

	_runloop = CFRunLoopGetMain();
	_runloopSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx);

	CFRunLoopAddSource(_runloop, _runloopSource, kCFRunLoopDefaultMode);

	fm = [NSFileManager defaultManager];
	sp_error rc;

	// Always do this. It allows libspotify to check for
	// header/library inconsistencies.
	_config.api_version = SPOTIFY_API_VERSION;

	// The path of the directory to store the cache. This must be specified.
	// Please read the documentation on preferred values.
	if (_cacheLocation) {
		if (_config.cache_location) free((void *)_cacheLocation);
		assert((_config.cache_location = strdup([_cacheLocation UTF8String])) != NULL);
		if (![fm fileExistsAtPath:_cacheLocation] && ![fm createDirectoryAtPath:_cacheLocation withIntermediateDirectories:YES attributes:nil error:err]) {
			return SP_ERROR_API_INITIALIZATION_FAILED;
		}
	}

	// The path of the directory to store the settings. This must be specified.
	// Please read the documentation on preferred values.
	if (_settingsLocation) {
		if (_config.settings_location) free((void *)_settingsLocation);
		assert((_config.settings_location = strdup([_settingsLocation UTF8String])) != NULL);
		if (![fm fileExistsAtPath:_settingsLocation] && ![fm createDirectoryAtPath:_settingsLocation withIntermediateDirectories:YES attributes:nil error:err]) {
			return SP_ERROR_API_INITIALIZATION_FAILED;
		}
	}

	// The key of the application. They are generated by Spotify,
	// and are specific to each application using libspotify.
	assert(_appKey != NULL);
	_config.application_key = _appKey;
	assert(_appKeySize > 0);
	_config.application_key_size = _appKeySize;

	// This identifies the application using some
	// free-text string [1, 255] characters.
	if (_userAgent) {
		if (_config.user_agent) free((void *)_userAgent);
		assert((_config.user_agent = strdup([_userAgent UTF8String])) != NULL);
	}

	// Register the callbacks.
	_config.callbacks = &_callbacks;

	// Reference to ourselves
	_config.userdata = (void *)self;

	// Initialize session
	assert(_session == NULL);
	rc = sp_session_init(&_config, &_session);

	if (rc != SP_ERROR_OK) {
		NSError *e = [NSError spotifyErrorWithCode:rc];
		if (err) {
			*err = e;
		} else {
			CB_INVOKE_DELEGATE2(self, session:, setupError:, e);
		}
		return rc;
	}

	info->session = _session;


	CB_INVOKE_DELEGATE1(self, sessionDidInitialize:);
	return rc;
}

- (BOOL)_initIfNeededSettingError:(NSError **)err {
	if (_session != NULL)
		return YES;
	@synchronized(self) {
		if (_session != NULL)
			return YES;
		return [self _initSettingError:err] == SP_ERROR_OK;
	}
	return SP_ERROR_OK;
}

#pragma mark -
#pragma mark User

- (BOOL)signInUserNamed:(NSString *)username withPassphrase:(NSString *)passphrase error:(NSError **)err {
	sp_error rc;

	if (![self _initIfNeededSettingError:err])
		return NO;

	if (_delegate && [_delegate respondsToSelector:@selector(session:shouldBeginForUserNamed:)]) {
		if (![_delegate session:self shouldBeginForUserNamed:username]) {
			// aborted by delegate
			*err = [NSError spotifyErrorWithFormat:@"Delegate %@ did not allow user %@ to sign in",
							_delegate, username];
			return NO;
		}
	}

	// Login using the credentials given on the command line.
	rc = sp_session_login(_session, [username UTF8String], [passphrase UTF8String]);

	if (rc != SP_ERROR_OK) {
		*err = [NSError spotifyErrorWithCode:rc];
		return NO;
	}

	return YES;
}

#pragma mark -
#pragma mark Properties

- (SPUser *)user {
	@synchronized(self) {
		if (!_user) {
			_user = [[SPUser alloc] initWithUserStruct:sp_session_user(_session)];
		}
	}
	return _user;
}

@end
