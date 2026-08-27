#include <CoreFoundation/CFPlugInCOM.h>
#include <QuickLook/QuickLook.h>
#include <stdlib.h>

OSStatus GenerateThumbnailForURL(void *thisInterface, QLThumbnailRequestRef thumbnail, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options, CGSize maxSize);
void CancelThumbnailGeneration(void *thisInterface, QLThumbnailRequestRef thumbnail);
OSStatus GeneratePreviewForURL(void *thisInterface, QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI, CFDictionaryRef options);
void CancelPreviewGeneration(void *thisInterface, QLPreviewRequestRef preview);

typedef struct {
    QLGeneratorInterfaceStruct *interface;
    CFUUIDRef factoryID;
    UInt32 refCount;
} ThreeMFQLGeneratorPlugin;

static CFUUIDRef ThreeMFFactoryID(void) {
    return CFUUIDGetConstantUUIDWithBytes(
        kCFAllocatorDefault,
        0x72, 0xC8, 0xAE, 0x8C, 0x8E, 0x89, 0x4E, 0x65,
        0x9C, 0x6B, 0x0D, 0x69, 0x46, 0x28, 0xCD, 0x70
    );
}

static HRESULT STDMETHODCALLTYPE ThreeMFQueryInterface(void *thisPointer, REFIID iid, LPVOID *ppv) {
    if (ppv == NULL) {
        return E_POINTER;
    }

    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    if (CFEqual(interfaceID, kQLGeneratorCallbacksInterfaceID) || CFEqual(interfaceID, IUnknownUUID)) {
        ((ThreeMFQLGeneratorPlugin *)thisPointer)->interface->AddRef(thisPointer);
        *ppv = thisPointer;
        CFRelease(interfaceID);
        return S_OK;
    }

    *ppv = NULL;
    CFRelease(interfaceID);
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE ThreeMFAddRef(void *thisPointer) {
    ThreeMFQLGeneratorPlugin *plugin = (ThreeMFQLGeneratorPlugin *)thisPointer;
    return ++plugin->refCount;
}

static ULONG STDMETHODCALLTYPE ThreeMFRelease(void *thisPointer) {
    ThreeMFQLGeneratorPlugin *plugin = (ThreeMFQLGeneratorPlugin *)thisPointer;
    plugin->refCount--;

    if (plugin->refCount == 0) {
        CFPlugInRemoveInstanceForFactory(plugin->factoryID);
        CFRelease(plugin->factoryID);
        free(plugin);
        return 0;
    }

    return plugin->refCount;
}

static QLGeneratorInterfaceStruct generatorInterface = {
    NULL,
    ThreeMFQueryInterface,
    ThreeMFAddRef,
    ThreeMFRelease,
    GenerateThumbnailForURL,
    CancelThumbnailGeneration,
    GeneratePreviewForURL,
    CancelPreviewGeneration
};

void *QuickLookGeneratorPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    ThreeMFQLGeneratorPlugin *plugin = malloc(sizeof(ThreeMFQLGeneratorPlugin));
    if (plugin == NULL) {
        return NULL;
    }

    plugin->interface = &generatorInterface;
    plugin->factoryID = CFRetain(ThreeMFFactoryID());
    plugin->refCount = 1;
    CFPlugInAddInstanceForFactory(plugin->factoryID);
    return plugin;
}