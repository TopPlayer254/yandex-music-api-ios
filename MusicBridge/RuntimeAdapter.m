#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

static char KreshkaIdentifierKey;
// These are the only direct CoreAnalytics symbols imported by the pinned
// original binary. Its CoreAnalytics load is redirected to this framework.
__attribute__((visibility("default")))
void AnalyticsSendEvent(NSString *event,NSDictionary *payload) { }
__attribute__((visibility("default")))
void AnalyticsSendEventLazy(NSString *event,NSDictionary *(^payload)(void)) { }

static NSMutableSet<NSString *> *installedHooks;
static id KCall0(id object, NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static id KCall1(id object, NSString *name,id value) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id(*)(id,SEL,id))objc_msgSend)(object,selector,value) : nil;
}
static id KCall2(id object,NSString *name,id first,id second) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id(*)(id,SEL,id,id))objc_msgSend)(object,selector,first,second) : nil;
}
static void KSend0(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if ([object respondsToSelector:selector]) ((void(*)(id,SEL))objc_msgSend)(object,selector);
}
static void KSend1(id object,NSString *name,id value) {
    SEL selector=NSSelectorFromString(name);
    if ([object respondsToSelector:selector]) ((void(*)(id,SEL,id))objc_msgSend)(object,selector,value);
}
static id KGet(id object,NSString *key) {
    if (![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}
static void KSet(id object,NSString *key,id value) {
    if (!object || !value || !key.length) return;
    NSString *setter=[NSString stringWithFormat:@"set%@%@:",[[key substringToIndex:1] uppercaseString],[key substringFromIndex:1]];
    if (![object respondsToSelector:NSSelectorFromString(setter)]) return;
    @try { [object setValue:value forKey:key]; } @catch (NSException *exception) { }
}
static void KLog(NSString *event) {
    NSLog(@"KRESHKA %@",event);
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("dev.hikeri.kreshka.music.log",DISPATCH_QUEUE_SERIAL);});
    dispatch_async(queue,^{
        NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Kreshka"];
        [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil];
        NSString *path=[folder stringByAppendingPathComponent:@"bridge.log"];
        NSData *data=[[NSString stringWithFormat:@"%@ %@\n",NSDate.date,event] dataUsingEncoding:NSUTF8StringEncoding];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) [data writeToFile:path atomically:YES];
        else { NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path]; [file seekToEndOfFile]; [file writeData:data]; [file closeFile]; }
    });
}
static NSError *KError(NSString *description) {
    return [NSError errorWithDomain:@"dev.hikeri.kreshka.music.bridge" code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}
static id KBackend(void) { return KCall0(NSClassFromString(@"KreshkaBackend"),@"sharedInstance"); }
static void KExecute(NSString *action,NSDictionary *payload,void(^completion)(NSDictionary *,NSError *)) {
    dispatch_async(dispatch_get_main_queue(),^{
        id backend=KBackend(); SEL selector=NSSelectorFromString(@"execute:payload:completion:");
        if (![backend respondsToSelector:selector]) { completion(nil,KError(@"Swift backend is unavailable")); return; }
        ((void(*)(id,SEL,id,id,id))objc_msgSend)(backend,selector,action,payload ?: @{},[completion copy]);
    });
}

// Validate the block signature instead of assuming every private completion
// has the same arity. The original request types use one or two object args.
static void KFinish(id block,id value,NSError *error) {
    if (!block) return;
    struct Block { void *isa; int flags; int reserved; void *invoke; void *descriptor; };
    struct Block *layout=(__bridge struct Block *)block;
    if (!(layout->flags & (1<<30))) { KLog(@"completion has no signature"); return; }
    uint8_t *descriptor=layout->descriptor;
    descriptor += 2*sizeof(unsigned long);
    if (layout->flags & (1<<25)) descriptor += 2*sizeof(void *);
    const char *types=*(const char **)descriptor;
    NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:types];
    if (signature.methodReturnType[0]!='v') { KLog(@"unsupported completion return type"); return; }
    NSUInteger count=signature.numberOfArguments;
    for (NSUInteger i=1;i<count;i++) {
        if ([signature getArgumentTypeAtIndex:i][0]!='@') { KLog(@"unsupported completion argument type"); return; }
    }
    if (count==3) ((void(^)(id,id))block)(value,error);
    else if (count==2) {
        const char *argument=[signature getArgumentTypeAtIndex:1];
        BOOL expectsError=strstr(argument,"NSError")!=NULL;
        if (error) KLog([@"request failed " stringByAppendingString:error.domain]);
        ((void(^)(id))block)(expectsError ? error : value);
    }
    else KLog(@"unsupported completion arity");
}

static NSString *KIdentifier(id object,NSUInteger depth) {
    if (!object || depth>4) return nil;
    NSString *identifier=objc_getAssociatedObject(object,&KreshkaIdentifierKey);
    if (identifier.length) return identifier;
    if ([object isKindOfClass:NSString.class]) {
        if ([object hasPrefix:@"kr:"]) return [object substringFromIndex:3];
        return nil;
    }
    if ([object isKindOfClass:NSArray.class]) {
        for (id value in object) { identifier=KIdentifier(value,depth+1); if (identifier) return identifier; }
        return nil;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        for (id value in [object allValues]) { identifier=KIdentifier(value,depth+1); if (identifier) return identifier; }
        return nil;
    }
    for (NSString *key in @[@"contentItemID",@"identifiers",@"modelObject",@"song",@"item",@"items",@"options",@"playbackContext",@"context"]) {
        identifier=KIdentifier(KGet(object,key),depth+1); if (identifier) return identifier;
    }
    return nil;
}

static id KModel(NSString *kind,NSDictionary *value);
static id KIdentifiers(NSString *identifier) {
    Class cls=NSClassFromString(@"MPIdentifierSet");
    id allocated=[cls alloc];
    void(^populate)(id)=^(id mutable){ KSet(mutable,@"contentItemID",[@"kr:" stringByAppendingString:identifier]); KSet(mutable,@"vendorID",identifier); };
    id result=nil;
    SEL modern=NSSelectorFromString(@"initWithSource:modelKind:block:");
    if ([allocated respondsToSelector:modern]) {
        result=((id(*)(id,SEL,id,id,id))objc_msgSend)(allocated,modern,@"Kreshka",nil,populate);
    } else if ([allocated respondsToSelector:NSSelectorFromString(@"initWithBlock:")]) {
        result=KCall1(allocated,@"initWithBlock:",populate);
    } else { result=KCall0(allocated,@"init"); populate(result); }
    if (result) objc_setAssociatedObject(result,&KreshkaIdentifierKey,identifier,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return result;
}

@interface KreshkaArtworkSource : NSObject
@property(nonatomic,strong) NSCache<NSString *,UIImage *> *images;
+ (instancetype)shared;
@end
@implementation KreshkaArtworkSource
+ (instancetype)shared { static id source; static dispatch_once_t once; dispatch_once(&once,^{source=[self new];}); return source; }
- (instancetype)init { if ((self=[super init])) _images=[NSCache new]; return self; }
- (BOOL)areRepresentationsAvailableForCatalog:(id)catalog { return [KGet(catalog,@"token") isKindOfClass:NSString.class]; }
- (void)cancelLoadingRepresentationForArtworkCatalog:(id)catalog { }
- (id)visualIdenticalityIdentifierForCatalog:(id)catalog { return KGet(catalog,@"token"); }
- (BOOL)isRepresentation:(id)representation bestRepresentationForArtworkCatalog:(id)catalog { return representation!=nil; }
- (id)representation:(UIImage *)image {
    Class cls=NSClassFromString(@"MPArtworkRepresentation"); SEL sel=NSSelectorFromString(@"representationWithSize:image:");
    if (!image || ![cls respondsToSelector:sel]) return nil;
    return ((id(*)(id,SEL,CGSize,id))objc_msgSend)(cls,sel,image.size,image);
}
- (id)existingRepresentationForArtworkCatalog:(id)catalog { return [self representation:[self.images objectForKey:KGet(catalog,@"token") ?: @""]]; }
- (void)loadRepresentationForArtworkCatalog:(id)catalog completionHandler:(id)completion {
    completion=[completion copy];
    NSString *key=KGet(catalog,@"token"); NSURL *url=[NSURL URLWithString:key ?: @""];
    if (!url || ![url.scheme isEqualToString:@"https"]) { KFinish(completion,nil,KError(@"Invalid artwork URL")); return; }
    UIImage *cached=[self.images objectForKey:key];
    if (cached) { KFinish(completion,[self representation:cached],nil); return; }
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        UIImage *image=data ? [UIImage imageWithData:data] : nil;
        if (image) [self.images setObject:image forKey:key];
        dispatch_async(dispatch_get_main_queue(),^{KFinish(completion,[self representation:image],error ?: (image ? nil : KError(@"Artwork download failed")));});
    }] resume];
}
@end

static id KModel(NSString *kind,NSDictionary *value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSString *className=@{@"song":@"MPModelSong",@"album":@"MPModelAlbum",@"artist":@"MPModelArtist",@"playlist":@"MPModelPlaylist"}[kind];
    Class cls=NSClassFromString(className); if (!cls) return nil;
    NSString *identifier=[value[@"id"] description] ?: @"";
    void(^populate)(id)=^(id model){
        KSet(model,@"title",value[@"title"] ?: value[@"name"]);
        KSet(model,@"name",value[@"name"] ?: value[@"title"]);
        KSet(model,@"duration",value[@"duration"]);
        KSet(model,@"explicitSong",value[@"isExplicit"]);
        KSet(model,@"libraryAdded",@YES);
        if ([kind isEqualToString:@"song"]) {
            KSet(model,@"artist",KModel(@"artist",value[@"artist"]));
            KSet(model,@"album",KModel(@"album",@{@"id":value[@"albumID"] ?: @"",@"title":value[@"albumTitle"] ?: @"",@"artwork":value[@"artwork"] ?: @{}}));
        }
        NSString *artwork=[value[@"artwork"] isKindOfClass:NSDictionary.class] ? value[@"artwork"][@"url"] : nil;
        if (artwork.length) {
            id(^catalog)(id)=^id(id unused){
                return KCall2([NSClassFromString(@"MPArtworkCatalog") alloc],@"initWithToken:dataSource:",artwork,KreshkaArtworkSource.shared);
            };
            KSet(model,@"artworkCatalogBlock",[catalog copy]);
        }
    };
    id allocated=[cls alloc]; id model=nil;
    if ([allocated respondsToSelector:NSSelectorFromString(@"initWithIdentifiers:block:")]) model=KCall2(allocated,@"initWithIdentifiers:block:",KIdentifiers(identifier),populate);
    else { model=KCall0(allocated,@"init"); populate(model); }
    if (model) objc_setAssociatedObject(model,&KreshkaIdentifierKey,identifier,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return model;
}

static NSString *KRequestKind(id request) {
    NSString *name=NSStringFromClass([KGet(request,@"itemKind") class]);
    if ([name containsString:@"Album"]) return @"album";
    if ([name containsString:@"Artist"]) return @"artist";
    if ([name containsString:@"Playlist"]) return @"playlist";
    return @"song";
}
static void KModelRequest(id request,id completion) {
    // The caller may pass a stack block. Retaining it as id does not give ARC
    // the block-typed ownership needed to move its captures to the heap.
    completion=[completion copy];
    NSString *kind=KRequestKind(request);
    NSString *query=KGet(request,@"searchString") ?: KGet(request,@"searchTerm") ?: @"";
    NSString *identifier=KIdentifier(KGet(request,@"sectionIdentifiers"),0);
    KExecute(@"catalog",@{@"kind":kind,@"query":query,@"id":identifier ?: @""},^(NSDictionary *result,NSError *error){
        if (error) { KFinish(completion,nil,error); return; }
        @try {
            Class responseClass=KCall0([request class],@"responseClass");
            if (!responseClass || ![responseClass isSubclassOfClass:NSClassFromString(@"MPModelResponse")]) responseClass=NSClassFromString(@"MPModelResponse");
            id response=KCall1([responseClass alloc],@"initWithRequest:",request);
            id collection=[NSClassFromString(@"MPMutableSectionedCollection") new];
            NSString *key=@{@"song":@"tracks",@"album":@"albums",@"artist":@"artists",@"playlist":@"playlists"}[kind];
            // The section object is a model, rather than a Foundation string.
            id section=KModel(@"playlist",@{@"id":@"library",@"name":@"Медиатека"});
            KSend1(collection,@"appendSection:",section);
            for (NSDictionary *value in result[key] ?: @[]) {
                id model=KModel(kind,value); if (model) KSend1(collection,@"appendItem:",model);
            }
            KSet(response,@"results",collection);
            if (!response || !collection) { KFinish(completion,nil,KError(@"Original model response API is unavailable")); return; }
            KLog([NSString stringWithFormat:@"catalog %@ -> %@",NSStringFromClass([request class]),key]);
            KFinish(completion,response,nil);
        } @catch (NSException *exception) {
            KLog([@"model adapter exception " stringByAppendingString:exception.name]);
            KFinish(completion,nil,KError(exception.reason ?: @"Model adapter failed"));
        }
    });
}

static BOOL KReplace(Class cls,NSString *name,id block,NSUInteger args,const char *returnType) {
    if (!cls) return NO;
    NSString *key=[NSString stringWithFormat:@"%@/%@",NSStringFromClass(cls),name];
    if ([installedHooks containsObject:key]) return YES;
    SEL selector=NSSelectorFromString(name); Method method=class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method)!=args) return NO;
    char *type=method_copyReturnType(method); BOOL valid=type && type[0]==returnType[0]; free(type);
    if (!valid) { KLog([@"incompatible hook " stringByAppendingString:key]); return NO; }
    IMP implementation=imp_implementationWithBlock(block);
    class_replaceMethod(cls,selector,implementation,method_getTypeEncoding(method));
    [installedHooks addObject:key]; KLog([@"installed " stringByAppendingString:key]); return YES;
}

static void KCommand(id request,id completion) {
    completion=[completion copy];
    NSString *label=[KGet(request,@"label") description].lowercaseString ?: @"";
    NSString *action=nil;
    if ([label containsString:@"toggle"]) action=@"toggle";
    else if ([label containsString:@"previous"] || [label containsString:@"backward"]) action=@"previous";
    else if ([label containsString:@"next"]) action=@"next";
    else if ([label containsString:@"pause"]) action=@"pause";
    else if ([label containsString:@"stop"]) action=@"stop";
    else if ([label containsString:@"play"] || [label containsString:@"queue"]) action=@"play";
    if (!action) { KLog([@"unmapped command " stringByAppendingString:NSStringFromClass([request class])]); KFinish(completion,nil,KError(@"Unmapped original player command")); return; }
    NSString *identifier=KIdentifier(request,0);
    KExecute(action,identifier ? @{@"id":identifier} : @{},^(NSDictionary *result,NSError *error){
        KLog([@"player " stringByAppendingString:action]);
        id status=nil;
        @try { status=[NSClassFromString(@"MPCPlayerCommandStatus") new]; KSet(status,@"error",error); }
        @catch (NSException *exception) { error=KError(@"Player command status ABI is unavailable"); }
        KFinish(completion,status,error);
    });
}

static void KInstallModels(void) {
    for (NSString *name in @[@"MPModelRequest",@"MPModelLibraryRequest",@"MPModelLibrarySearchRequest",@"MPModelStoreSearchRequest",@"MPModelStoreBrowseRequest"]) {
        KReplace(NSClassFromString(name),@"performWithResponseHandler:",^(id request,id completion){KModelRequest(request,completion);},3,"v");
    }
    Class commandClass=NSClassFromString(@"MPCPlayerCommandRequest");
    KReplace(commandClass,@"performWithCompletion:",^id(id request,id completion){KCommand(request,completion);return request;},3,"@");
    KReplace(commandClass,@"performWithCompletion:",^(id request,id completion){KCommand(request,completion);},3,"v");
    unsigned count=0; Method *methods=class_copyMethodList(commandClass,&count);
    for (unsigned i=0;i<count;i++) {
        NSString *name=NSStringFromSelector(method_getName(methods[i]));
        if ([name containsString:@"perform"] || [name containsString:@"execute"]) KLog([@"command method " stringByAppendingString:name]);
    }
    free(methods);
}

static BOOL KAppleHost(NSString *host) {
    host=host.lowercaseString;
    for (NSString *suffix in @[@"music.apple.com",@"itunes.apple.com",@"itunes.com",@"mzstatic.com",@"applemusic.com",@"xp.apple.com"]) {
        if ([host isEqualToString:suffix] || [host hasSuffix:[@"." stringByAppendingString:suffix]]) return YES;
    }
    return NO;
}
static NSDictionary *KAppleItem(NSString *type,NSDictionary *value) {
    NSDictionary *artist=value[@"artist"];
    NSString *title=value[@"title"] ?: value[@"name"] ?: @"";
    NSMutableDictionary *attributes=[@{@"name":title,@"artistName":artist[@"name"] ?: @"",@"albumName":value[@"albumTitle"] ?: @""} mutableCopy];
    if (value[@"duration"]) attributes[@"durationInMillis"]=@([value[@"duration"] doubleValue]*1000);
    NSString *artwork=value[@"artwork"][@"url"];
    if (artwork) attributes[@"artwork"]=@{@"url":artwork,@"width":@1000,@"height":@1000};
    NSString *identifier=[value[@"id"] description] ?: @"";
    attributes[@"playParams"]=@{@"id":[@"kr:" stringByAppendingString:identifier],@"kind":@"song"};
    return @{@"id":identifier,@"type":type,@"attributes":attributes};
}
@interface KreshkaAppleProtocol : NSURLProtocol
@property(atomic) BOOL stopped;
@end
@implementation KreshkaAppleProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return KAppleHost(request.URL.host); }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading { self.stopped=YES; }
- (void)startLoading {
    NSURLComponents *url=[NSURLComponents componentsWithURL:self.request.URL resolvingAgainstBaseURL:NO];
    BOOL search=[url.path containsString:@"/search"];
    BOOL home=[url.path containsString:@"/recommendations"] || [url.path containsString:@"/recently-played"];
    BOOL supported=[url.path hasPrefix:@"/v1/"] && (search || home || [url.path containsString:@"/songs"] || [url.path containsString:@"/albums"] || [url.path containsString:@"/artists"] || [url.path containsString:@"/playlists"]);
    if (!supported) {
        KLog([NSString stringWithFormat:@"blocked Apple endpoint %@ %@",url.host,url.path]);
        [self.client URLProtocol:self didFailWithError:KError(@"Apple service disconnected; endpoint adapter not implemented")]; return;
    }
    NSString *query=@""; for (NSURLQueryItem *item in url.queryItems) if ([item.name isEqualToString:@"term"]) query=item.value ?: @"";
    NSString *kind=[url.path containsString:@"/albums"] ? @"album" : [url.path containsString:@"/artists"] ? @"artist" : [url.path containsString:@"/playlists"] ? @"playlist" : @"song";
    KExecute(home ? @"home" : @"catalog",@{@"kind":kind,@"query":query},^(NSDictionary *result,NSError *error){
        if (self.stopped) return;
        if (error) { [self.client URLProtocol:self didFailWithError:error]; return; }
        NSMutableDictionary *groups=[NSMutableDictionary dictionary];
        NSDictionary *keys=@{@"songs":@"tracks",@"albums":@"albums",@"artists":@"artists",@"playlists":@"playlists"};
        for (NSString *type in keys) {
            NSMutableArray *items=[NSMutableArray array];
            for (NSDictionary *value in result[keys[type]] ?: @[]) [items addObject:KAppleItem(type,value)];
            groups[type]=@{@"data":items};
        }
        NSString *type=@{@"song":@"songs",@"album":@"albums",@"artist":@"artists",@"playlist":@"playlists"}[kind];
        NSDictionary *envelope=search ? @{@"results":groups} : groups[type];
        NSData *data=[NSJSONSerialization dataWithJSONObject:envelope options:0 error:&error];
        if (!data) { [self.client URLProtocol:self didFailWithError:error]; return; }
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:data]; [self.client URLProtocolDidFinishLoading:self];
        KLog([NSString stringWithFormat:@"routed Apple endpoint %@",url.path]);
    });
}
@end

@interface KreshkaBridgeInstaller : NSObject
@end
@implementation KreshkaBridgeInstaller
+ (void)load {
    installedHooks=[NSMutableSet new];
    // Authorization here refers to the bridge's catalogue. No request for the
    // user's Apple Music/media-library data is needed by our providers.
    Class mediaLibraryMeta=object_getClass(NSClassFromString(@"MPMediaLibrary"));
    KReplace(mediaLibraryMeta,@"authorizationStatus",^NSInteger(id cls){ return 3; },2,"q");
    KReplace(mediaLibraryMeta,@"requestAuthorization:",^(id cls,id completion){
        void(^handler)(NSInteger)=(void(^)(NSInteger))[completion copy];
        dispatch_async(dispatch_get_main_queue(),^{ if (handler) handler(3); });
    },3,"v");
    [NSURLProtocol registerClass:KreshkaAppleProtocol.class];
    Class meta=object_getClass(NSURLSessionConfiguration.class);
    for (NSString *name in @[@"defaultSessionConfiguration",@"ephemeralSessionConfiguration"]) {
        Method method=class_getClassMethod(NSURLSessionConfiguration.class,NSSelectorFromString(name));
        IMP original=method_getImplementation(method);
        KReplace(meta,name,^id(id cls){
            NSURLSessionConfiguration *configuration=((id(*)(id,SEL))original)(cls,NSSelectorFromString(name));
            NSMutableArray *protocols=[configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
            if (![protocols containsObject:KreshkaAppleProtocol.class]) [protocols insertObject:KreshkaAppleProtocol.class atIndex:0];
            configuration.protocolClasses=protocols; return configuration;
        },2,"@");
    }
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){
        KInstallModels();
        KExecute(@"state",@{},^(NSDictionary *state,NSError *error){
            KLog([NSString stringWithFormat:@"bridge ready provider=%@ signedIn=%@",state[@"provider"],state[@"signedIn"]]);
            if (![state[@"signedIn"] boolValue] && ![NSBundle.mainBundle.bundleIdentifier hasSuffix:@".smoke"]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{KSend0(KBackend(),@"presentAccount");});
            }
        });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:@"KreshkaCatalogChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){
        [NSNotificationCenter.defaultCenter postNotificationName:@"MPMediaLibraryDidChangeNotification" object:nil];
    }];
    Method appear=class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
    IMP original=method_getImplementation(appear);
    KReplace(UIViewController.class,@"viewDidAppear:",^(UIViewController *controller,BOOL animated){
        ((void(*)(id,SEL,BOOL))original)(controller,@selector(viewDidAppear:),animated);
        NSString *name=NSStringFromClass(controller.class);
        if (([name containsString:@"MusicApplication"] || [name hasPrefix:@"Music"]) && controller.navigationController.topViewController==controller) {
            controller.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle"] style:UIBarButtonItemStylePlain target:KBackend() action:NSSelectorFromString(@"presentAccount")];
        }
    },3,"v");
    KLog(@"runtime adapter loaded");
}
@end
