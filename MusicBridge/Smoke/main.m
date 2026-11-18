#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static id backend;
static BOOL callbackLifetimePassed=NO;
static id Call(id object,NSString *name) {
    return ((id(*)(id,SEL))objc_msgSend)(object,NSSelectorFromString(name));
}
static void Check(BOOL condition,NSString *message) {
    if (!condition) { NSLog(@"KRESHKA_TEST_FAILED %@",message); abort(); }
}
static id Command(unsigned int type,id identifiers) {
    id allocated=[NSClassFromString(@"MPCPlayerCommandRequest") alloc];
    SEL selector=NSSelectorFromString(@"initWithMediaRemoteCommand:options:controller:label:");
    Check([allocated respondsToSelector:selector],@"MPC command initializer unavailable");
    return ((id(*)(id,SEL,unsigned int,id,id,id))objc_msgSend)(allocated,selector,type,
        identifiers ? @{@"KreshkaSelectedTrack":identifiers} : @{},nil,@"Команда с локализованной меткой");
}
static id Change(id command) {
    id allocated=[NSClassFromString(@"MPCPlayerChangeRequest") alloc];
    return ((id(*)(id,SEL,id))objc_msgSend)(allocated,NSSelectorFromString(@"initWithCommandRequests:"),@[command]);
}
static void Finish(UIViewController *root) {
    Check(callbackLifetimePassed,@"callback did not retain captures");
    ((void(*)(id,SEL))objc_msgSend)(backend,NSSelectorFromString(@"presentSettings"));
    ((void(*)(id,SEL))objc_msgSend)(backend,NSSelectorFromString(@"presentSettings"));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Check(root.presentedViewController!=nil,@"settings not presented");
        Check(root.presentedViewController.presentedViewController==nil,@"duplicate settings sheet");
        NSLog(@"KRESHKA_SETTINGS_PRESENTATION_PASSED");
        NSLog(@"KRESHKA_SMOKE_READY provider=%@",Call(backend,@"snapshot")[@"provider"]);
        [@"ready" writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/bridge-smoke.ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
static void VerifyOnboarding(UIViewController *root) {
    const char *name="_TtC16MusicApplication24JSWhatsNewViewController";
    Class cls=NSClassFromString(@(name));
    if (!cls) { cls=objc_allocateClassPair(UIViewController.class,name,0); objc_registerClassPair(cls); }
    __block NSUInteger completed=0;
    for (NSUInteger i=0;i<3;i++) {
        [root presentViewController:[cls new] animated:NO completion:^{
            Check(root.presentedViewController==nil,@"Apple onboarding presented");
            if (++completed==3) {
                NSLog(@"KRESHKA_ONBOARDING_SUPPRESSION_PASSED");
                Finish(root);
            }
        }];
    }
}
static void VerifyPlayback(id identifiers,UIViewController *root) {
    Check(NSClassFromString(@"MPCPlayerChangeRequest")!=Nil,@"native MPC framework unavailable");
    id request=Change(Command(125,identifiers));
    void(^played)(NSArray *)=^(NSArray *statuses){
        Check(statuses.count==1 && Call(statuses.firstObject,@"error")==nil,@"native Play failed");
        NSDictionary *state=Call(backend,@"snapshot");
        Check(state[@"track"]!=nil && [state[@"playing"] boolValue],@"Play did not reach our player");
        id pause=Change(Command(1,nil));
        void(^paused)(NSError *)=^(NSError *error){
            Check(error==nil && ![Call(backend,@"snapshot")[@"playing"] boolValue],@"native Pause did not pause our player");
            NSLog(@"KRESHKA_NATIVE_PLAY_PAUSE_PASSED");
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"music://music.apple.com"] options:@{} completionHandler:^(BOOL opened){
                Check(!opened,@"external Apple Music was launched");
                NSLog(@"KRESHKA_APPLE_LAUNCH_BLOCK_PASSED");
                VerifyOnboarding(root);
            }];
        };
        ((void(*)(id,SEL,id))objc_msgSend)(pause,NSSelectorFromString(@"performWithCompletion:"),paused);
    };
    ((void(*)(id,SEL,id))objc_msgSend)(request,NSSelectorFromString(@"performWithExtendedStatusCompletion:"),played);
}
static void VerifyCatalogue(UIViewController *root) {
    id request=[NSClassFromString(@"MPModelLibraryRequest") new];
    ((void(*)(id,SEL,Class))objc_msgSend)(request,NSSelectorFromString(@"setItemClass:"),NSClassFromString(@"MPModelSong"));
    NSObject *sentinel=[NSObject new];
    __weak NSObject *weakSentinel=sentinel;
    void(^__unsafe_unretained callback)(id,NSError *)=^(id response,NSError *error){
        Check(weakSentinel==sentinel && weakSentinel!=nil,@"released stack-block capture");
        Check(response!=nil && error==nil,@"catalogue success path failed");
        callbackLifetimePassed=YES;
        NSLog(@"KRESHKA_CALLBACK_LIFETIME_PASSED");
        NSArray *songs=Call(Call(response,@"results"),@"allItems");
        Check(songs.count>0,@"native model collection is empty");
        id song=songs.firstObject;
        Check([Call(song,@"title") length]>0,@"native song title missing");
        id identifiers=[Call(song,@"identifiers") copy];
        Check([Call(identifiers,@"contentItemID") hasPrefix:@"kr:"],@"identity lost during copy");
        NSLog(@"KRESHKA_NATIVE_CATALOG_PASSED count=%lu",(unsigned long)songs.count);
        VerifyPlayback(identifiers,root);
    };
    ((void(*)(id,SEL,void *))objc_msgSend)(request,NSSelectorFromString(@"performWithResponseHandler:"),(__bridge void *)callback);
}

@interface SmokeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation SmokeDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    setenv("KRESHKA_SMOKE_CATALOG","1",1);
    dlopen("/System/Library/PrivateFrameworks/MediaPlaybackCore.framework/MediaPlaybackCore",RTLD_NOW);
    NSString *framework=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"KreshkaBridge.framework/KreshkaBridge"];
    void *handle=dlopen(framework.UTF8String,RTLD_NOW);
    if (!handle) { NSLog(@"KRESHKA_SMOKE_FAILED %s",dlerror()); abort(); }
    UIViewController *root=[UIViewController new];
    root.view.backgroundColor=UIColor.systemBackgroundColor;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=root;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        backend=Call(NSClassFromString(@"KreshkaBackend"),@"sharedInstance");
        Check(backend!=nil,@"backend missing");
        VerifyCatalogue(root);
    });
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(SmokeDelegate.class)); }
}
