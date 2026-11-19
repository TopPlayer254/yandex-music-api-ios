#import "BridgeSmoke.h"
#include <dlfcn.h>

// Match the original Swift getter's generic metadata/witness arguments and its
// Swift self/context register. An ordinary objc_msgSend/C-function cast would
// not exercise this ABI correctly. This shim is only in the simulator test app.
typedef void *(*AutoupdatingGetter)(const void *, const void *,
    const void * __attribute__((swift_context))) __attribute__((swiftcall));
typedef const void *(*WitnessGetter)(const void *, const void *, const void *);

void *KreshkaMakeAutoupdatingResponse(const void *request, const void *metadata) {
    void *framework=dlopen("/System/Library/PrivateFrameworks/MusicKitInternal.framework/MusicKitInternal",RTLD_NOW);
    if (!framework) return NULL;
    void *descriptor=dlsym(framework,"$s8MusicKit0A14LibraryRequestVyxG0aB8Internal0a13AutoupdatableD0AEMc");
    WitnessGetter witness=(WitnessGetter)dlsym(RTLD_DEFAULT,"swift_getWitnessTable");
    AutoupdatingGetter getter=(AutoupdatingGetter)dlsym(framework,
        "$s16MusicKitInternal0A20AutoupdatableRequestPAAE20autoupdatingResponseAA0a12AutoupdatingG0CyxGvg");
    if (!framework || !descriptor || !witness || !getter) {
        NSLog(@"KRESHKA_AUTOUPDATING_ABI_UNAVAILABLE %s",dlerror());
        return NULL;
    }
    const void *table=witness(descriptor,metadata,NULL);
    if (!table) return NULL;
    return getter(metadata,table,request);
}
