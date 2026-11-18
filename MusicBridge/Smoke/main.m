#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

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
        NSCAssert(backend, @"Bridge class is absent");
        id object = ((id(*)(id,SEL))objc_msgSend)(backend,NSSelectorFromString(@"sharedInstance"));
        NSDictionary *state = ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"snapshot"));
        NSCAssert(state[@"provider"], @"Backend was not initialized");
        NSLog(@"KRESHKA_SMOKE_READY provider=%@", state[@"provider"]);
        [@"ready" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/bridge-smoke.ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        ((void(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(@"presentAccount"));
    });
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class)); }
}
