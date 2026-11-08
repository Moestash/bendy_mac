#include "MockHost.h"
#include <cstdio>
#include <dlfcn.h>

// A separate host process avoids registering the editor's Objective-C classes
// twice, once in the test executable and once in the loaded plugin.
int main(int argc, char** argv)
{
    if (argc != 2) return 2;
    void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::fprintf(stderr, "%s\n", dlerror()); return 1; }
    using Factory = TFruityPlug* (*)(TFruityPlugHost*, TPluginTag);
    auto factory = reinterpret_cast<Factory>(dlsym(library, "CreatePlugInstance"));
    if (!factory) return 1;
    MockHost host;
    auto plugin = factory(&host, 12);
    if (!plugin || plugin->HostTag != 12 || std::strcmp(plugin->Info->LongName, "BENDY")) return 1;
    char name[256] = {};
    plugin->GetName(FPN_Param, 0, 0, name);
    if (!name[0] || !(plugin->Info->Flags & FPF_MacNeedsNSView)) return 1;
    plugin->DestroyObject();
    dlclose(library);
    std::puts("BENDY dylib load test passed");
    return 0;
}
