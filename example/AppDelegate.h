#import <Spotify/Spotify.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, SPSessionDelegate> {
	NSWindow *_window;
	NSTextField *_usernameTextField;
	NSSecureTextField *_passwordTextField;
	SPSession *_session;
}

@property(assign) IBOutlet NSWindow *window;
@property(assign) IBOutlet NSTextField *usernameTextField;
@property(assign) IBOutlet NSSecureTextField *passwordTextField;
@property(readonly) NSString *supportDirectory;
@property(readonly) NSString *cacheDirectory;

- (IBAction)login:(id)sender;

@end
