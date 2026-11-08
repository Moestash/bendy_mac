#import <Cocoa/Cocoa.h>
#include "MockHost.h"
#include "Plugin.h"
#include "StreamWrapper.h"
#include "State.h"
#include "mac/PluginGUI.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <vector>

#define CHECK(condition) do { if (!(condition)) throw std::runtime_error(#condition); } while (0)

static_assert(sizeof(ULONG) == 4, "FL stream counts are 32-bit");
static_assert(sizeof(LARGE_INTEGER) == 8, "FL stream offsets are 64-bit");
static_assert(sizeof(TFruityPlugInfo) == 160, "FL plugin info uses 4-byte packing");

@interface NSObject (BendyEditorTesting)
- (NSMenu*)menuForParameter:(PlugParameter*)parameter;
@end

class MemoryStream : public IStream
{
public:
    std::vector<char> bytes;
    size_t position = 0;
    void QueryInterface() override {}
    ULONG AddRef() override { return 1; }
    ULONG Release() override { return 1; }
    HRESULT Read(void* data, ULONG count, ULONG* read) override
    {
        size_t size = std::min<size_t>(count, bytes.size() - position);
        std::memcpy(data, bytes.data() + position, size);
        position += size;
        if (read) *read = static_cast<ULONG>(size);
        return size == count ? S_OK : 1;
    }
    HRESULT Write(const void* data, ULONG count, ULONG* written) override
    {
        if (position + count > bytes.size()) bytes.resize(position + count);
        std::memcpy(bytes.data() + position, data, count);
        position += count;
        if (written) *written = count;
        return S_OK;
    }
    HRESULT Seek(LARGE_INTEGER offset, DWORD origin, ULARGE_INTEGER* result) override
    {
        int64_t base = origin == STREAM_SEEK_CUR ? position : origin == STREAM_SEEK_END ? bytes.size() : 0;
        if (base + offset.QuadPart < 0) return 1;
        position = static_cast<size_t>(base + offset.QuadPart);
        if (result) result->QuadPart = position;
        return S_OK;
    }
    HRESULT SetSize(ULARGE_INTEGER) override { return 1; }
    HRESULT CopyTo(IStream*, ULARGE_INTEGER, ULARGE_INTEGER*, ULARGE_INTEGER*) override { return 1; }
    HRESULT Commit(DWORD) override { return S_OK; }
    HRESULT Revert() override { return 1; }
    HRESULT LockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return 1; }
    HRESULT UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER, DWORD) override { return 1; }
    HRESULT Stat(void*, DWORD) override { return 1; }
    HRESULT Clone(IStream**) override { return 1; }
};

void testWireFormat()
{
    // Byte fixture emitted by the Windows format: UTF-16 A, é and U+1F3B5.
    const unsigned char fixture[] = {4,0,0,0, 0x41,0, 0xe9,0, 0x3c,0xd8,0xb5,0xdf};
    DataStream input(fixture, sizeof(fixture));
    CHECK(input.readString() == L"Aé🎵");
    DataStream output(1);
    output.writeString(L"Aé🎵");
    CHECK(output.getPosition() == sizeof(fixture));
    CHECK(std::memcmp(output.data(), fixture, sizeof(fixture)) == 0);
    // Exercise unaligned primitive values and a string larger than one growth step.
    output.writeChar(-1);
    output.writeInt(0x12345678);
    output.writeFloat(0.25f);
    const std::wstring large(4096, L'界');
    output.writeString(large);
    output.setPosition(sizeof(fixture));
    CHECK(output.readChar() == -1);
    CHECK(output.readInt() == 0x12345678);
    CHECK(output.readFloat() == 0.25f);
    CHECK(output.readString() == large);
    MemoryStream hostStream;
    StreamWrapper wrapper(&hostStream);
    wrapper.writeString(L"Aé🎵");
    CHECK(hostStream.bytes.size() == sizeof(fixture));
    CHECK(std::memcmp(hostStream.bytes.data(), fixture, sizeof(fixture)) == 0);
    hostStream.position = 0;
    CHECK(wrapper.readString() == L"Aé🎵");
    const unsigned char truncated[] = {1,0,0,0, 0x41};
    DataStream invalid(truncated, sizeof(truncated));
    bool rejected = false;
    try { invalid.readString(); } catch (const std::runtime_error&) { rejected = true; }
    CHECK(rejected);
}

void set(Plugin& plugin, const wchar_t* id, int value)
{
    auto param = plugin.getParameter(id);
    CHECK(param);
    plugin.ProcessParam(param->index, value, REC_UpdateValue | REC_UpdateControl);
}

void testStateAndMIDI()
{
    MockHost host;
    FruityPlugInfo info{42, &host};
    Plugin plugin(&info);
    CHECK(plugin.Info->Flags & FPF_MacNeedsNSView);
    CHECK(plugin.Info->NumParams > 50);
    // Known CRC-32 of the UTF-8 parameter id; automation indexes remain stable.
    CHECK(plugin.getParameter(L"port")->hash == 0x43915dcc);
    CHECK(plugin.getParameter(L"currentPresetIndex")->getMidiMax() == INT32_MAX);
    set(plugin, L"port", 7);
    set(plugin, L"channel", 3);
    set(plugin, L"range", 12);
    plugin.getParameter(L"midiKnobName0")->setFromString(L"Cutoff 🎵");
    MemoryStream saved;
    plugin.SaveRestoreState(&saved, true);
    const uint32_t expectedMagic = static_cast<uint32_t>(13118359537711872022ULL);
    CHECK(std::memcmp(saved.bytes.data(), &expectedMagic, sizeof(expectedMagic)) == 0);
    set(plugin, L"port", 1);
    saved.position = 0;
    plugin.SaveRestoreState(&saved, false);
    CHECK(plugin.getParameter(L"port")->getFloat() == 7);
    CHECK(plugin.getParameter(L"midiKnobName0")->toString() == L"Cutoff 🎵");
    // An unknown or truncated state must leave the current instance usable.
    MemoryStream bad;
    bad.bytes = {'B','A','D','!'};
    plugin.SaveRestoreState(&bad, false);
    CHECK(plugin.getParameter(L"port")->getFloat() == 7);
    saved.bytes.resize(10);
    saved.position = 0;
    plugin.SaveRestoreState(&saved, false);
    CHECK(plugin.getParameter(L"port")->getFloat() == 7);

    host.messages.clear();
    TVoiceParams voice{};
    voice.FinalLevels.Vol = 1;
    voice.FinalLevels.Pitch = 0; // C5 / MIDI 60
    TVoiceHandle handle = plugin.TriggerVoice(&voice, 123);
    plugin.NewTick();
    auto contains = [&](int status, int d1, int d2) {
        return std::any_of(host.messages.begin(), host.messages.end(), [&](const TMIDIOutMsg& m) {
            return m.Status == status && m.Data1 == d1 && m.Data2 == d2 && m.Port == 7;
        });
    };
    CHECK(contains(0x92, 60, 102));
    host.messages.clear();
    voice.FinalLevels.Pitch = 600; // a six-semitone slide with a 12-semitone range
    plugin.NewTick();
    CHECK(contains(0xe2, 127, 95)); // round(0.75 * 16383) = 12287
    plugin.Voice_Release(handle);
    CHECK(contains(0x82, 60, 64));
    plugin.Voice_Kill(handle);
    // Zero is a valid initial pan/volume value, not the cache's unset marker.
    plugin.ProcessEvent(FPE_MIDI_Vol, 0, 0);
    plugin.Dispatcher(FPD_SetPlaying, 0, 1);
    host.messages.clear();
    voice.FinalLevels.Pitch = 0;
    voice.FinalLevels.Pan = -1;
    handle = plugin.TriggerVoice(&voice, 124);
    plugin.NewTick();
    CHECK(contains(0xb2, 10, 0));
    CHECK(contains(0xb2, 7, 0));
    plugin.Voice_Release(handle);
    plugin.Voice_Kill(handle);
    // A disabled CC is activated by changing its value even with the editor shut.
    set(plugin, L"midiKnobValue0", 77);
    CHECK(plugin.getParameter(L"midiKnobEnabled0")->getFloat() == 1);
    ParameterFloat floating(L"Test", L"test", 0, 0, 8);
    floating.setFromString(L"1.5");
    CHECK(floating.value == 1.5f);
}

// Optional offscreen AppKit integration test; requires a macOS login session.
void testEditor(const char* snapshot)
{
    [NSApplication sharedApplication];
    MockHost host;
    FruityPlugInfo info{42, &host};
    Plugin plugin(&info);
    NSView* parent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 540)];
    NSWindow* window = [[NSWindow alloc] initWithContentRect:parent.frame
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = parent;
    plugin.Dispatcher(FPD_ShowEditor, 0, reinterpret_cast<intptr_t>((__bridge void*)parent));
    CHECK(plugin.EditorHandle != 0);
    CHECK(parent.subviews.count == 1);
    NSView* root = parent.subviews.firstObject;
    NSTabView* tabs = nil;
    for (NSView* view in root.subviews) if ([view isKindOfClass:NSTabView.class]) tabs = (NSTabView*)view;
    CHECK(tabs && tabs.numberOfTabViewItems == 4);
    [window display];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (snapshot)
    {
        [root layoutSubtreeIfNeeded];
        NSBitmapImageRep* bitmap = [root bitmapImageRepForCachingDisplayInRect:root.bounds];
        [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
        NSData* png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        CHECK([png writeToFile:[NSString stringWithUTF8String:snapshot] atomically:YES]);
    }
    NSScrollView* scroll = (NSScrollView*)[tabs tabViewItemAtIndex:0].view;
    const int portIndex = plugin.getParameter(L"port")->index;
    NSSlider* port = nil;
    for (NSView* view in scroll.documentView.subviews)
        if ([view isKindOfClass:NSSlider.class] && ((NSControl*)view).tag == portIndex) port = (NSSlider*)view;
    CHECK(port);
    port.intValue = 11;
    [port sendAction:port.action to:port.target];
    CHECK(plugin.getParameter(L"port")->getFloat() == 11);
    CHECK(host.notifiedParameter == portIndex);
    NSMenu* menu = [port.target menuForParameter:plugin.getParameter(L"port")];
    NSMenuItem* assign = nil;
    for (NSMenuItem* item in menu.itemArray)
        if ([item.title isEqualToString:@"Assign note control 1"]) assign = item;
    CHECK(assign && assign.submenu.numberOfItems == 3);
    NSMenuItem* full = [assign.submenu itemAtIndex:0];
    [NSApp sendAction:full.action to:full.target from:full];
    CHECK(plugin.HasNoteControl(plugin.getParameter(L"port")->hash));
    MemoryStream state;
    plugin.SaveRestoreState(&state, true);
    state.position = 0;
    plugin.SaveRestoreState(&state, false);
    plugin.Idle_Public();
    NSView* other = [[NSView alloc] initWithFrame:parent.frame];
    plugin.Dispatcher(FPD_ShowEditor, 0, reinterpret_cast<intptr_t>((__bridge void*)other));
    CHECK(parent.subviews.count == 0 && other.subviews.count == 1);
    plugin.Dispatcher(FPD_ShowEditor, 0, 0);
    CHECK(plugin.EditorHandle == 0 && other.subviews.count == 0);
    [window close];
}

int main(int argc, char** argv)
{
    @autoreleasepool {
        try {
            testWireFormat();
            testStateAndMIDI();
            if (argc > 1 && std::strcmp(argv[1], "--gui") == 0) testEditor(argc > 2 ? argv[2] : nullptr);
            std::puts("BENDY macOS tests passed");
            return 0;
        } catch (const std::exception& e) {
            std::fprintf(stderr, "FAIL: %s\n", e.what());
            return 1;
        }
    }
}
