#import <UIKit/UIKit.h>

// Simulator-only dependency fixture. It supplies no catalogue or playback and
// is never linked into KreshkaBridge or included in the device IPA.
@interface PresenceDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation PresenceDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    UIViewController *root=[UIViewController new];
    root.view.backgroundColor=UIColor.systemBackgroundColor;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(PresenceDelegate.class)); }
}
