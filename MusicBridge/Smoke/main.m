#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

static BOOL callbackLifetimePassed=NO;
static void verifyAsyncCallbackLifetime(void) {
    Class requestClass=NSClassFromString(@"MPModelLibraryRequest");
    SEL selector=NSSelectorFromString(@"performWithResponseHandler:");
    id request=[requestClass new];
    if (![request respondsToSelector:selector]) { NSLog(@"KRESHKA_CALLBACK_TEST_UNAVAILABLE"); abort(); }
    NSObject *sentinel=[NSObject new];
    __weak NSObject *weakSentinel=sentinel;
    // Deliberately pass a stack block through an untyped ABI, like the soft
    // linking wrapper in MusicKit. The asynchronous adapter must copy it.
    void (^__unsafe_unretained callback)(id,NSError *)=^(id response,NSError *error){
        if (!weakSentinel || weakSentinel!=sentinel || !error) {
            NSLog(@"KRESHKA_CALLBACK_LIFETIME_FAILED"); abort();
        }
        callbackLifetimePassed=YES;
        NSLog(@"KRESHKA_CALLBACK_LIFETIME_PASSED");
    };
    ((void(*)(id,SEL,void *))objc_msgSend)(request,selector,(__bridge void *)callback);
}

@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSString *framework = [[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"KreshkaBridge.framework"] stringByAppendingPathComponent:@"KreshkaBridge"];
    void *handle = dlopen(framework.UTF8String, RTLD_NOW);
    if (!handle) { NSLog(@"KRESHKA_SMOKE_FAILED %s", dlerror()); abort(); }
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        Class backend = NSClassFromString(@"KreshkaBackend");
        if (!backend) { NSLog(@"KRESHKA_SMOKE_FAILED missing backend"); abort(); }
        id object = ((id(*)(id,SEL))objc_msgSend)(backend,NSSelectorFromString(@"sharedInstance"));
        NSDictionary *state = ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"snapshot"));
        if (!state[@"provider"]) { NSLog(@"KRESHKA_SMOKE_FAILED missing state"); abort(); }
        verifyAsyncCallbackLifetime();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (!callbackLifetimePassed) { NSLog(@"KRESHKA_SMOKE_FAILED callback timeout"); abort(); }
            NSLog(@"KRESHKA_SMOKE_READY provider=%@", state[@"provider"]);
            [@"ready" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/bridge-smoke.ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
        ((void(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"presentAccount"));
    });
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class)); }
}
