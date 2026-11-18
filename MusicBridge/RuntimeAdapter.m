#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <string.h>
#include <unistd.h>

static char KreshkaIdentifierKey;
static char KreshkaAccountButtonKey;
static NSMutableDictionary<NSNumber *,NSString *> *libraryIdentifiers;
static void KInstallModels(void);
static void KLog(NSString *event);
static void KBindNativeAccountButtons(UIView *view);
static NSString *KLibraryIdentifier(NSNumber *persistentID) {
    @synchronized (libraryIdentifiers) { return libraryIdentifiers[persistentID]; }
}
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
    @try { [object setValue:value forKey:key]; }
    @catch (NSException *exception) { KLog([NSString stringWithFormat:@"model property %@.%@ failed %@",NSStringFromClass([object class]),key,exception.name]); }
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

// The MPMediaLibrary provider boundary keeps metadata from opening Apple's
// ML3 SQLite store inside the sideloaded application's unrelated container.
@interface KreshkaLibraryProvider : NSObject
@property(atomic,copy) NSDictionary *catalog;
@end
@implementation KreshkaLibraryProvider
- (NSString *)uniqueIdentifier { return @"dev.hikeri.kreshka.music"; }
- (NSString *)name { return @"Крешка"; }
- (NSString *)syncValidity { return @"kreshka-library-1"; }
- (NSString *)databasePath { return nil; }
- (id)library { return nil; }
- (id)artworkDataSource { return nil; }
- (id)entityCache { return nil; }
- (BOOL)requiresAuthentication { return NO; }
- (NSDate *)lastModifiedDate { return NSDate.date; }
- (BOOL)hasMediaOfType:(NSUInteger)type { return [self.catalog[@"tracks"] count]>0; }
- (BOOL)itemExistsWithPersistentID:(uint64_t)identifier { return KLibraryIdentifier(@(identifier))!=nil; }
- (BOOL)collectionExistsWithPersistentID:(uint64_t)identifier groupingType:(NSInteger)type { return KLibraryIdentifier(@(identifier))!=nil; }
- (id)itemResultSetForQueryCriteria:(id)criteria { return nil; }
- (id)collectionResultSetForQueryCriteria:(id)criteria { return nil; }
- (void)loadQueryCriteria:(id)criteria countOfItemsWithCompletionBlock:(void(^)(NSUInteger))completion {
    if (completion) completion([self.catalog[@"tracks"] count]);
}
- (void)loadQueryCriteria:(id)criteria countOfCollectionsWithCompletionBlock:(void(^)(NSUInteger))completion {
    if (completion) completion([self.catalog[@"playlists"] count]);
}
- (void)loadQueryCriteria:(id)criteria hasItemsWithCompletionBlock:(void(^)(BOOL))completion {
    if (completion) completion([self.catalog[@"tracks"] count]>0);
}
- (void)loadQueryCriteria:(id)criteria hasCollectionsWithCompletionBlock:(void(^)(BOOL))completion {
    if (completion) completion([self.catalog[@"playlists"] count]>0);
}
- (void)loadProperties:(NSSet *)properties ofItemWithIdentifier:(int64_t)identifier completionBlock:(void(^)(NSDictionary *))completion {
    if (completion) completion(@{});
}
- (void)loadProperties:(NSSet *)properties ofCollectionWithIdentifier:(int64_t)identifier groupingType:(NSInteger)type completionBlock:(void(^)(NSDictionary *))completion {
    if (completion) completion(@{});
}
- (void)loadValueForAggregateFunction:(NSString *)function onItemsForProperty:(NSString *)property queryCriteria:(id)criteria completionBlock:(void(^)(id))completion {
    if (completion) completion(nil);
}
- (void)loadValueForAggregateFunction:(NSString *)function onCollectionsForProperty:(NSString *)property queryCriteria:(id)criteria completionBlock:(void(^)(id))completion {
    if (completion) completion(nil);
}
- (id)valueForDatabaseProperty:(NSString *)property {
    return [NSUserDefaults.standardUserDefaults objectForKey:[@"kreshka-media-property:" stringByAppendingString:property]];
}
- (BOOL)setValue:(id)value forDatabaseProperty:(NSString *)property {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:[@"kreshka-media-property:" stringByAppendingString:property]]; return YES;
}
@end

static KreshkaLibraryProvider *KLibraryProvider(void) {
    static KreshkaLibraryProvider *provider; static dispatch_once_t once;
    dispatch_once(&once,^{
        provider=[KreshkaLibraryProvider new]; provider.catalog=@{};
        for (NSString *name in @[@"MPMediaLibraryDataProvider",@"MPMediaLibraryDataProviderPrivate"]) {
            Protocol *protocol=NSProtocolFromString(name); if (protocol) class_addProtocol(KreshkaLibraryProvider.class,protocol);
        }
    });
    return provider;
}
static id KLocalLibrary(void) {
    static id library; static dispatch_once_t once;
    dispatch_once(&once,^{
        id allocated=[NSClassFromString(@"MPMediaLibrary") alloc];
        library=KCall1(allocated,@"_initWithLibraryDataProvider:",KLibraryProvider());
        KLog([NSString stringWithFormat:@"isolated media library initialized=%d",library!=nil]);
    });
    return library;
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
    if (!object || depth>10) return nil;
    NSString *identifier=objc_getAssociatedObject(object,&KreshkaIdentifierKey);
    if (identifier.length) return identifier;
    if ([object isKindOfClass:NSString.class]) {
        if ([object hasPrefix:@"kr:"]) return [object substringFromIndex:3];
        return nil;
    }
    NSString *content=KGet(object,@"contentItemID");
    if ([content isKindOfClass:NSString.class] && [content hasPrefix:@"kr:"]) return [content substringFromIndex:3];
    NSString *vendor=KGet(object,@"vendorID");
    if ([vendor isKindOfClass:NSString.class] && [vendor hasPrefix:@"kr:"]) return [vendor substringFromIndex:3];
    NSString *libraryID=KLibraryIdentifier(KGet(object,@"deviceLibraryPersistentID") ?: @0);
    if (libraryID) return libraryID;
    if ([object isKindOfClass:NSArray.class]) {
        for (id value in object) { identifier=KIdentifier(value,depth+1); if (identifier) return identifier; }
        return nil;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        for (id value in [object allValues]) { identifier=KIdentifier(value,depth+1); if (identifier) return identifier; }
        return nil;
    }
    for (NSString *key in @[@"identifiers",@"startItemIdentifiers",@"allowedItemIdentifiers",@"scopedContainers",@"modelObject",@"song",@"item",@"items",@"options",@"playbackContext",@"context",@"request"]) {
        identifier=KIdentifier(KGet(object,key),depth+1); if (identifier) return identifier;
    }
    return nil;
}

static id KModel(NSString *kind,NSDictionary *value);
static id KIdentifiers(NSString *identifier,Class modelClass) {
    Class cls=NSClassFromString(@"MPIdentifierSet");
    id allocated=[cls alloc];
    uint64_t persistentID=14695981039346656037ULL;
    NSData *bytes=[[NSString stringWithFormat:@"%@:%@",NSStringFromClass(modelClass),identifier] dataUsingEncoding:NSUTF8StringEncoding];
    for (NSUInteger i=0;i<bytes.length;i++) { persistentID^=((const uint8_t *)bytes.bytes)[i]; persistentID*=1099511628211ULL; }
    persistentID=(persistentID & INT64_MAX) ?: 1;
    @synchronized (libraryIdentifiers) { libraryIdentifiers[@(persistentID)]=identifier; }
    void(^populate)(id)=^(id mutable){
        KSet(mutable,@"contentItemID",[@"kr:" stringByAppendingString:identifier]);
        KSet(mutable,@"vendorID",[@"kr:" stringByAppendingString:identifier]);
        if ([mutable respondsToSelector:NSSelectorFromString(@"setLibraryIdentifiersWithDatabaseID:block:")]) {
            void(^library)(id)=^(id local){ KSet(local,@"persistentID",@(persistentID)); };
            // KVC boxes primitive setters; the two-object method takes a real
            // database namespace so MusicKit recognizes local-library identity.
            ((void(*)(id,SEL,id,id))objc_msgSend)(mutable,NSSelectorFromString(@"setLibraryIdentifiersWithDatabaseID:block:"),@"dev.hikeri.kreshka.music",library);
        } else KSet(mutable,@"deviceLibraryPersistentID",@(persistentID));
    };
    id result=nil;
    SEL modern=NSSelectorFromString(@"initWithSource:modelKind:block:");
    if ([allocated respondsToSelector:modern]) {
        id modelKind=KCall1(NSClassFromString(@"MPModelKind"),@"kindWithModelClass:",modelClass);
        result=((id(*)(id,SEL,id,id,id))objc_msgSend)(allocated,modern,@"Kreshka",modelKind,populate);
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
            KSet(model,@"album",KModel(@"album",@{@"id":value[@"albumID"] ?: @"",@"title":value[@"albumTitle"] ?: @"",@"artwork":value[@"artwork"] ?: @{},@"artists":value[@"artist"] ? @[value[@"artist"]] : @[]}));
        }
        if ([kind isEqualToString:@"album"]) {
            KSet(model,@"artist",KModel(@"artist",[value[@"artists"] firstObject]));
            KSet(model,@"trackCount",value[@"trackCount"]);
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
    if ([allocated respondsToSelector:NSSelectorFromString(@"initWithIdentifiers:block:")]) model=KCall2(allocated,@"initWithIdentifiers:block:",KIdentifiers(identifier,cls),populate);
    else { model=KCall0(allocated,@"init"); populate(model); }
    if (model) objc_setAssociatedObject(model,&KreshkaIdentifierKey,identifier,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return model;
}

static NSString *KRequestKind(id request) {
    NSString *name=NSStringFromClass(KCall0(request,@"itemClass")) ?: NSStringFromClass([KGet(request,@"itemKind") class]);
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
    NSString *identifier=KIdentifier(KGet(request,@"scopedContainers"),0) ?: KIdentifier(KGet(request,@"sectionIdentifiers"),0);
    NSString *containerKind=kind;
    for (id scope in KGet(request,@"scopedContainers")) {
        NSString *name=NSStringFromClass([scope class]);
        if ([name containsString:@"Playlist"]) containerKind=@"playlist";
        else if ([name containsString:@"Album"]) containerKind=@"album";
        else if ([name containsString:@"Artist"]) containerKind=@"artist";
    }
    NSMutableArray *ids=[NSMutableArray new];
    for (id value in KGet(request,@"allowedItemIdentifiers")) {
        NSString *itemID=KIdentifier(value,0); if (itemID) [ids addObject:itemID];
    }
    KExecute(@"catalog",@{@"kind":kind,@"containerKind":containerKind,@"query":query,@"id":identifier ?: @"",@"ids":ids},^(NSDictionary *result,NSError *error){
        if (error) { KLog([NSString stringWithFormat:@"catalog %@ failed %@ %ld",NSStringFromClass([request class]),error.domain,(long)error.code]); KFinish(completion,nil,error); return; }
        @try {
            Class responseClass=KCall0([request class],@"responseClass");
            if (!responseClass && [request isKindOfClass:NSClassFromString(@"MPModelLibraryRequest")]) responseClass=NSClassFromString(@"MPModelLibraryResponse");
            if (!responseClass || ![responseClass isSubclassOfClass:NSClassFromString(@"MPModelResponse")]) responseClass=NSClassFromString(@"MPModelResponse");
            id response=KCall1([responseClass alloc],@"initWithRequest:",request);
            id collection=[NSClassFromString(@"MPMutableSectionedCollection") new];
            NSString *key=@{@"song":@"tracks",@"album":@"albums",@"artist":@"artists",@"playlist":@"playlists"}[kind];
            // An unsectioned library request expects a generic section, not a
            // playlist masquerading as an album/artist section.
            id section=[NSClassFromString(@"MPModelObject") new];
            KSend1(collection,@"appendSection:",section);
            for (NSDictionary *value in result[key] ?: @[]) {
                id model=KModel(kind,value); if (model) KSend1(collection,@"appendItem:",model);
            }
            KSet(response,@"results",collection);
            if (!response || !collection) { KFinish(completion,nil,KError(@"Original model response API is unavailable")); return; }
            KLog([NSString stringWithFormat:@"catalog %@ -> %@ count=%lu attached=%d",NSStringFromClass([request class]),key,(unsigned long)[result[key] count],KGet(response,@"results")!=nil]);
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

static id KCommandStatus(id request,NSError *error) {
    Class cls=NSClassFromString(@"MPRemoteCommandStatus");
    id status=nil;
    if (error) {
        SEL selector=NSSelectorFromString(@"statusWithCode:error:");
        if ([cls respondsToSelector:selector]) status=((id(*)(id,SEL,NSInteger,id))objc_msgSend)(cls,selector,200,error);
    } else status=KCall0(cls,@"successStatus");
    return KCall2([NSClassFromString(@"MPCPlayerCommandStatus") alloc],@"initWithMPStatus:request:",status,request);
}

static void KRunCommand(id request,void(^completion)(id,NSError *)) {
    NSNumber *command=KGet(request,@"command");
    NSDictionary *options=KGet(request,@"options") ?: @{};
    NSString *label=[KGet(request,@"label") description].lowercaseString ?: @"";
    NSString *action=nil;
    // The command's numeric type is stable even when the UI label is localized.
    if (command) switch (command.unsignedIntValue) {
        case 0: action=@"play"; break;
        case 1: action=@"pause"; break;
        case 2: action=@"toggle"; break;
        case 3: action=@"stop"; break;
        case 4: action=@"next"; break;
        case 5: action=@"previous"; break;
        case 24: action=@"seek"; break;
        case 122: case 125: action=@"play"; break;
    }
    if (!action) {
    if ([label containsString:@"toggle"]) action=@"toggle";
    else if ([label containsString:@"previous"] || [label containsString:@"backward"]) action=@"previous";
    else if ([label containsString:@"next"]) action=@"next";
    else if ([label containsString:@"pause"]) action=@"pause";
    else if ([label containsString:@"stop"]) action=@"stop";
    else if ([label containsString:@"play"] || [label containsString:@"queue"]) action=@"play";
    }
    if (!action) {
        NSError *error=KError([NSString stringWithFormat:@"Команда воспроизведения %@ пока не поддерживается.",command ?: @"?"]);
        KLog([@"unmapped command " stringByAppendingString:NSStringFromClass([request class])]);
        completion(KCommandStatus(request,error),error); return;
    }
    id context=options[@"MPCPlayerCommandRequestMediaRemoteOptionPlaybackContext"];
    NSString *identifier=KIdentifier(KGet(context,@"startItemIdentifiers"),0) ?: KIdentifier(request,0);
    NSMutableDictionary *payload=[NSMutableDictionary new];
    if (identifier) payload[@"id"]=identifier;
    NSMutableArray *queue=[NSMutableArray new];
    for (id value in KGet(KGet(context,@"request"),@"allowedItemIdentifiers")) {
        NSString *itemID=KIdentifier(value,0); if (itemID) [queue addObject:itemID];
    }
    if (queue.count) payload[@"queue"]=queue;
    for (NSString *key in options) {
        if ([key.lowercaseString containsString:@"playbackposition"] && [options[key] isKindOfClass:NSNumber.class]) payload[@"time"]=options[key];
    }
    KExecute(action,payload,^(NSDictionary *result,NSError *error){
        KLog([NSString stringWithFormat:@"player %@ command=%@ success=%d",action,command,error==nil]);
        completion(KCommandStatus(request,error),error);
    });
}

static void KRunCommands(NSArray *commands,NSUInteger index,NSMutableArray *statuses,void(^completion)(NSArray *,NSError *),NSError *firstError) {
    if (index==commands.count) { completion(statuses,firstError); return; }
    KRunCommand(commands[index],^(id status,NSError *error){
        if (status) [statuses addObject:status];
        KRunCommands(commands,index+1,statuses,completion,firstError ?: error);
    });
}

static void KInstallModels(void) {
    Class accountClass=NSClassFromString(@"MusicApplication.AccountButton") ?: NSClassFromString(@"_TtC16MusicApplication13AccountButton");
    Method accountMove=class_getInstanceMethod(accountClass,@selector(didMoveToWindow));
    if (accountMove) {
        IMP originalMove=method_getImplementation(accountMove);
        KReplace(accountClass,@"didMoveToWindow",^(UIView *view){
            ((void(*)(id,SEL))originalMove)(view,@selector(didMoveToWindow));
            KBindNativeAccountButtons(view);
        },2,"v");
    }
    for (NSString *name in @[@"MPModelRequest",@"MPModelLibraryRequest",@"MPModelLibrarySearchRequest",@"MPModelStoreSearchRequest",@"MPModelStoreBrowseRequest"]) {
        KReplace(NSClassFromString(name),@"performWithResponseHandler:",^(id request,id completion){KModelRequest(request,completion);},3,"v");
        KReplace(NSClassFromString(name),@"responseWithCompletion:",^(id request,id completion){KModelRequest(request,completion);},3,"v");
    }
    // Native transport responses must observe this app's Now Playing session,
    // rather than the separate, installed com.apple.Music process.
    Class pathClass=NSClassFromString(@"MPCPlayerPath");
    KReplace(object_getClass(pathClass),@"systemMusicPathWithRoute:playerID:",^id(id cls,id route,id playerID){
        SEL selector=NSSelectorFromString(@"pathWithRoute:bundleID:playerID:");
        return ((id(*)(id,SEL,id,id,id))objc_msgSend)(cls,selector,route,NSBundle.mainBundle.bundleIdentifier,playerID);
    },4,"@");
    NSString *initializer=@"initWithDeviceUID:bundleID:pid:playerID:";
    Method pathInit=class_getInstanceMethod(pathClass,NSSelectorFromString(initializer));
    if (pathInit) {
        IMP originalPathInit=method_getImplementation(pathInit);
        KReplace(pathClass,initializer,^id(id path,id device,id bundleID,int pid,id playerID){
            if ([bundleID isEqualToString:@"com.apple.Music"]) { bundleID=NSBundle.mainBundle.bundleIdentifier; pid=getpid(); }
            return ((id(*)(id,SEL,id,id,int,id))originalPathInit)(path,NSSelectorFromString(initializer),device,bundleID,pid,playerID);
        },6,"@");
    }
    Class changeClass=NSClassFromString(@"MPCPlayerChangeRequest");
    KReplace(changeClass,@"performWithCompletion:",^(id request,id completion){
        void(^handler)(NSError *)=[completion copy];
        KRunCommands(KGet(request,@"commands") ?: @[],0,[NSMutableArray new],^(NSArray *statuses,NSError *error){ if (handler) handler(error); },nil);
    },3,"v");
    KReplace(changeClass,@"performWithExtendedStatusCompletion:",^(id request,id completion){
        void(^handler)(NSArray *)=[completion copy];
        KRunCommands(KGet(request,@"commands") ?: @[],0,[NSMutableArray new],^(NSArray *statuses,NSError *error){ if (handler) handler(statuses); },nil);
    },3,"v");
    for (NSString *name in @[@"MPMusicPlayerController",@"MPSystemMusicPlayerController",@"MPApplicationMusicPlayerController"]) {
        NSDictionary *actions=@{@"play":@"play",@"pause":@"pause",@"stop":@"stop",@"skipToNextItem":@"next",@"skipToPreviousItem":@"previous"};
        for (NSString *selector in actions) {
            NSString *action=actions[selector];
            KReplace(NSClassFromString(name),selector,^(id controller){
                KExecute(action,@{},^(NSDictionary *state,NSError *error){
                    KLog([NSString stringWithFormat:@"public player %@ success=%d",action,error==nil]);
                });
            },2,"v");
        }
    }
}

__attribute__((visibility("default"))) void KreshkaInstallAdapters(void) { KInstallModels(); }

static void KBindNativeAccountButtons(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    if ([name containsString:@"MusicApplication"] && [name hasSuffix:@"AccountButton"]) {
        if (!objc_getAssociatedObject(view,&KreshkaAccountButtonKey)) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
            button.frame=view.bounds;
            button.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
            button.accessibilityLabel=@"Учётная запись и настройки";
            [button addTarget:KBackend() action:NSSelectorFromString(@"presentSettings") forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(view,&KreshkaAccountButtonKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [view addSubview:button];
            view.accessibilityElements=@[button];
        }
        return;
    }
    for (UIView *child in view.subviews) KBindNativeAccountButtons(child);
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
    if (value[@"isExplicit"]) attributes[@"contentRating"]=[value[@"isExplicit"] boolValue] ? @"explicit" : @"clean";
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
    NSArray *components=[url.path componentsSeparatedByString:@"/"];
    NSString *identifier=@"";
    NSString *plural=@{@"album":@"albums",@"artist":@"artists",@"playlist":@"playlists",@"song":@"songs"}[kind];
    NSUInteger position=[components indexOfObject:plural];
    if (position!=NSNotFound && position+1<components.count) identifier=components[position+1];
    if ([identifier hasPrefix:@"kr:"]) identifier=[identifier substringFromIndex:3];
    BOOL trackRelationship=[url.path hasSuffix:@"/tracks"] || [url.path hasSuffix:@"/songs"];
    KExecute(home ? @"home" : @"catalog",@{@"kind":kind,@"containerKind":kind,@"query":query,@"id":identifier},^(NSDictionary *result,NSError *error){
        if (self.stopped) return;
        if (error) { [self.client URLProtocol:self didFailWithError:error]; return; }
        NSMutableDictionary *groups=[NSMutableDictionary dictionary];
        NSDictionary *keys=@{@"songs":@"tracks",@"albums":@"albums",@"artists":@"artists",@"playlists":@"playlists"};
        for (NSString *type in keys) {
            NSMutableArray *items=[NSMutableArray array];
            for (NSDictionary *value in result[keys[type]] ?: @[]) [items addObject:KAppleItem(type,value)];
            groups[type]=@{@"data":items};
        }
        NSString *type=trackRelationship ? @"songs" : plural;
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

// Only the original application's Apple-service onboarding/settings are
// redirected. OAuth, document pickers and our own sheets remain ordinary UI.
static NSInteger KPresentationRoute(UIViewController *controller) {
    NSString *name=NSStringFromClass(controller.class);
    if ([name containsString:@"MusicApplication"] || [name hasPrefix:@"_TtC16MusicApplication"]) {
        if ([name containsString:@"JSWhatsNewViewController"] || [name containsString:@"WelcomeViewController"]) return 1;
        if ([name containsString:@"JSSettingsViewController"]) return 2;
    }
    for (UIViewController *child in controller.childViewControllers) {
        NSInteger route=KPresentationRoute(child); if (route) return route;
    }
    return 0;
}

static BOOL KAppleMusicURL(NSURL *url) {
    NSString *scheme=url.scheme.lowercaseString;
    return [@[@"music",@"musics",@"itms-music",@"itmss",@"itms"] containsObject:scheme]
        || [url.host.lowercaseString isEqualToString:@"music.apple.com"];
}

@interface KreshkaBridgeInstaller : NSObject
@end
@implementation KreshkaBridgeInstaller
+ (void)load {
    installedHooks=[NSMutableSet new];
    libraryIdentifiers=[NSMutableDictionary new];
    // Authorization here refers to the bridge's catalogue. No request for the
    // user's Apple Music/media-library data is needed by our providers.
    Class mediaLibraryMeta=object_getClass(NSClassFromString(@"MPMediaLibrary"));
    KReplace(mediaLibraryMeta,@"authorizationStatus",^NSInteger(id cls){ return 3; },2,"q");
    KReplace(mediaLibraryMeta,@"requestAuthorization:",^(id cls,id completion){
        void(^handler)(NSInteger)=(void(^)(NSInteger))[completion copy];
        dispatch_async(dispatch_get_main_queue(),^{ if (handler) handler(3); });
    },3,"v");
    for (NSString *selector in @[@"defaultMediaLibrary",@"deviceMediaLibrary"]) {
        KReplace(mediaLibraryMeta,selector,^id(id cls){ return KLocalLibrary(); },2,"@");
    }
    KReplace(mediaLibraryMeta,@"deviceMediaLibraryWithUserIdentity:",^id(id cls,id identity){ return KLocalLibrary(); },3,"@");
    KReplace(NSClassFromString(@"MPMediaLibrary"),@"initWithClientIdentity:userIdentity:",^id(id library,id client,id identity){
        return KCall1(library,@"_initWithLibraryDataProvider:",KLibraryProvider());
    },4,"@");
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
        KExecute(@"catalog",@{},^(NSDictionary *catalog,NSError *error){
            if (error) return;
            KLibraryProvider().catalog=catalog;
            [NSNotificationCenter.defaultCenter postNotificationName:@"MPMediaLibraryDidChangeNotification" object:KLocalLibrary()];
        });
    }];
    Method present=class_getInstanceMethod(UIViewController.class,@selector(presentViewController:animated:completion:));
    IMP originalPresent=method_getImplementation(present);
    KReplace(UIViewController.class,@"presentViewController:animated:completion:",^(UIViewController *presenter,UIViewController *controller,BOOL animated,void(^completion)(void)){
        NSInteger route=KPresentationRoute(controller);
        if (route) {
            KLog(route==1 ? @"suppressed Apple onboarding presentation" : @"redirected Apple settings to Maple settings");
            dispatch_async(dispatch_get_main_queue(),^{
                if (completion) completion();
                if (route==2) KSend0(KBackend(),@"presentSettings");
            });
            return;
        }
        ((void(*)(id,SEL,id,BOOL,id))originalPresent)(presenter,@selector(presentViewController:animated:completion:),controller,animated,completion);
    },5,"v");
    Method open=class_getInstanceMethod(UIApplication.class,@selector(openURL:options:completionHandler:));
    IMP originalOpen=method_getImplementation(open);
    KReplace(UIApplication.class,@"openURL:options:completionHandler:",^(UIApplication *app,NSURL *url,NSDictionary *options,void(^completion)(BOOL)){
        if (KAppleMusicURL(url)) {
            KLog(@"blocked external Apple Music launch");
            if (completion) dispatch_async(dispatch_get_main_queue(),^{completion(NO);});
            return;
        }
        ((void(*)(id,SEL,id,id,id))originalOpen)(app,@selector(openURL:options:completionHandler:),url,options,completion);
    },5,"v");
    Method appear=class_getInstanceMethod(UIViewController.class,@selector(viewDidAppear:));
    IMP original=method_getImplementation(appear);
    KReplace(UIViewController.class,@"viewDidAppear:",^(UIViewController *controller,BOOL animated){
        ((void(*)(id,SEL,BOOL))original)(controller,@selector(viewDidAppear:),animated);
        if (KPresentationRoute(controller)==1) {
            UIViewController *host=controller;
            while (host.parentViewController && !host.presentingViewController) host=host.parentViewController;
            if (host.presentingViewController) {
                KLog(@"dismissed embedded Apple onboarding");
                [host dismissViewControllerAnimated:NO completion:nil];
            }
            return;
        }
        KInstallModels();
        KBindNativeAccountButtons(controller.view);
    },3,"v");
    KLog(@"runtime adapter loaded");
}
@end
