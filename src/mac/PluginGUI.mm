#import <Cocoa/Cocoa.h>
#include "mac/PluginGUI.h"
#include "Plugin.h"
#include "Parameter.h"
#include <atomic>
#include <codecvt>
#include <locale>

namespace {
NSString* text(const std::wstring& value)
{
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return [NSString stringWithUTF8String:converter.to_bytes(value).c_str()] ?: @"";
}
std::wstring toWideString(NSString* value)
{
    std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
    return converter.from_bytes(value.UTF8String ?: "");
}
NSTextField* label(NSString* value, NSRect rect)
{
    NSTextField* field = [NSTextField labelWithString:value];
    field.frame = rect;
    return field;
}
}

// Targets store parameter indexes, never pointers into replaceable preset state.
@interface BendyEditorController : NSObject <NSTextFieldDelegate>
@property(nonatomic, assign) Plugin* plugin;
@property(nonatomic, strong) NSView* root;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSControl*>* controls;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSTextField*>* values;
@property(nonatomic, strong) NSTabView* tabs;
@property(nonatomic, strong) NSArray<NSButton*>* tabButtons;
- (void)refresh;
- (void)change:(NSControl*)sender;
- (void)choosePreset:(NSPopUpButton*)sender;
- (void)menuAction:(NSMenuItem*)sender;
- (void)addParameter:(PlugParameter*)param toView:(NSView*)view y:(CGFloat)y;
- (void)selectTab:(NSButton*)sender;
@end

@implementation BendyEditorController
- (NSMenu*)menuForParameter:(PlugParameter*)param
{
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
    menu.autoenablesItems = NO;
    // FL supplies the automation/linking items, including their current flags.
    for (int n = 0; n < 128; ++n)
    {
        auto entry = reinterpret_cast<PParamMenuEntry>(self.plugin->PlugHost->Dispatcher(
            self.plugin->HostTag, FHD_GetParamMenuEntry, param->index, n));
        if (!entry) break;
        if (std::strcmp(entry->Name, "-") == 0)
        {
            [menu addItem:NSMenuItem.separatorItem];
            continue;
        }
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:
            ([NSString stringWithUTF8String:entry->Name] ?: @"") action:@selector(menuAction:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @[@(param->index), @0, @(n)];
        item.enabled = !(entry->Flags & FHP_Disabled);
        item.state = (entry->Flags & FHP_Checked) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    if (param->canSetRange)
    {
        if (menu.numberOfItems) [menu addItem:NSMenuItem.separatorItem];
        for (int operation = 1; operation <= 2; ++operation)
        {
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:
                operation == 1 ? @"Set minimum…" : @"Set maximum…"
                action:@selector(menuAction:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = @[@(param->index), @(operation), @0];
            [menu addItem:item];
        }
    }
    if (dynamic_cast<ParameterInt*>(param) || dynamic_cast<ParameterFloat*>(param))
    {
        for (int control = 0; control < 2; ++control)
        {
            NSMenuItem* parent = [[NSMenuItem alloc] initWithTitle:
                [NSString stringWithFormat:@"Assign note control %d", control + 1]
                action:nil keyEquivalent:@""];
            NSMenu* submenu = [[NSMenu alloc] initWithTitle:parent.title];
            for (int type = 0; type < 3; ++type)
            {
                NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@[@"Full", @"Upper", @"Lower"][type]
                    action:@selector(menuAction:) keyEquivalent:@""];
                item.target = self;
                item.representedObject = @[@(param->index), @3, @(control * 3 + type)];
                [submenu addItem:item];
            }
            parent.submenu = submenu;
            [menu addItem:parent];
        }
        NSMenuItem* clear = [[NSMenuItem alloc] initWithTitle:@"Unassign note control"
            action:@selector(menuAction:) keyEquivalent:@""];
        clear.target = self;
        clear.representedObject = @[@(param->index), @4, @0];
        [menu addItem:clear];
    }
    return menu;
}
- (void)addParameter:(PlugParameter*)param toView:(NSView*)view y:(CGFloat)y
{
    NSString* title = text(param->name);
    if (param->id == L"enableNoteTrigger") title = @"Trigger MIDI notes";
    if (param->id == L"range") title = @"Pitch bend range (semitones)";
    if (!param->id.empty() && iswdigit(param->id.back()))
        title = [title stringByAppendingFormat:@" %d", static_cast<int>(param->id.back() - L'0') + 1];
    NSTextField* name = label(title, NSMakeRect(16, y + 2, 250, 22));
    name.toolTip = text(param->name);
    [view addSubview:name];
    NSControl* control;
    if (auto selection = dynamic_cast<ParameterStringSelection*>(param))
    {
        NSPopUpButton* popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(272, y, 212, 26) pullsDown:NO];
        for (int i = 0; i < static_cast<int>(selection->strings.size()); ++i)
            [popup addItemWithTitle:text(selection->toReadable(i, false))];
        control = popup;
    }
    else if (dynamic_cast<ParameterBool*>(param))
    {
        NSButton* button = [NSButton checkboxWithTitle:@"Enabled" target:self action:@selector(change:)];
        button.frame = NSMakeRect(272, y, 212, 24);
        button.allowsMixedState = YES;
        control = button;
    }
    else if (dynamic_cast<ParameterString*>(param))
    {
        NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(272, y, 212, 24)];
        field.delegate = self;
        control = field;
    }
    else
    {
        NSSlider* slider = [[NSSlider alloc] initWithFrame:NSMakeRect(272, y, 154, 24)];
        slider.continuous = YES;
        control = slider;
        NSTextField* value = [[NSTextField alloc] initWithFrame:NSMakeRect(432, y, 52, 24)];
        value.tag = param->index;
        value.target = self;
        value.delegate = self;
        [view addSubview:value];
        self.values[@(param->index)] = value;
    }
    control.tag = param->index;
    control.target = self;
    if (![control isKindOfClass:NSTextField.class]) control.action = @selector(change:);
    control.toolTip = @"Use the ••• menu for automation, ranges and note controls.";
    [view addSubview:control];
    self.controls[@(param->index)] = control;
    // A pull-down builds its menu on demand so host automation flags stay current.
    NSButton* options = [NSButton buttonWithTitle:@"•••" target:self action:@selector(showOptions:)];
    options.frame = NSMakeRect(492, y, 34, 24);
    options.tag = param->index;
    [view addSubview:options];
}
- (void)showOptions:(NSButton*)sender
{
    auto param = self.plugin->getParameterByIndex(static_cast<int>(sender.tag));
    if (!param) return;
    NSMenu* menu = [self menuForParameter:param];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
}
- (void)selectTab:(NSButton*)sender
{
    [self.tabs selectTabViewItemAtIndex:sender.tag];
    for (NSButton* button in self.tabButtons)
        button.state = button == sender ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)change:(NSControl*)sender
{
    auto param = self.plugin->getParameterByIndex(static_cast<int>(sender.tag));
    if (!param) return;
    if (dynamic_cast<ParameterString*>(param))
        param->setFromString(toWideString(sender.stringValue));
    else
    {
        float value = sender.floatValue;
        if ([sender isKindOfClass:NSPopUpButton.class])
            value = static_cast<float>(((NSPopUpButton*)sender).indexOfSelectedItem);
        else if ([sender isKindOfClass:NSButton.class])
        {
            NSControlStateValue state = ((NSButton*)sender).state;
            value = state == NSControlStateValueMixed ? -1 : state == NSControlStateValueOn ? 1 : 0;
        }
        value = std::fmax(param->getMin(), std::fmin(param->getMax(), value));
        if (dynamic_cast<ParameterInt*>(param)) value = std::round(value);
        param->setFloat(value);
        const int wireValue = *static_cast<int*>(param->get4ByteValue());
        self.plugin->ProcessParam(param->index, wireValue, REC_UpdateValue | REC_UpdateControl);
        self.plugin->PlugHost->OnParamChanged(self.plugin->HostTag, param->index, wireValue);
    }
    [self refresh];
}
- (void)controlTextDidEndEditing:(NSNotification*)notification
{
    [self change:notification.object];
}
- (void)choosePreset:(NSPopUpButton*)sender
{
    // The host may destroy/recreate this editor during the dispatcher call.
    Plugin* plugin = self.plugin;
    const NSInteger index = sender.indexOfSelectedItem - 1;
    if (index >= 0) plugin->Dispatcher(FPD_SetPreset, index, 0);
}
- (void)menuAction:(NSMenuItem*)sender
{
    NSArray<NSNumber*>* info = sender.representedObject;
    auto param = self.plugin->getParameterByIndex(info[0].intValue);
    if (!param) return;
    int operation = info[1].intValue;
    if (operation == 0)
        self.plugin->PlugHost->Dispatcher(self.plugin->HostTag, FHD_ParamMenu, param->index, info[2].intValue);
    else if (operation == 3)
        self.plugin->AssignNoteControl(param->index, static_cast<NoteControlIndex>(info[2].intValue / 3),
            static_cast<NoteControlType>(info[2].intValue % 3));
    else if (operation == 4)
        self.plugin->AssignNoteControl(param->index, NoControl, Full);
    else
    {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = operation == 1 ? @"Set minimum" : @"Set maximum";
        NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
        input.floatValue = operation == 1 ? param->getMin() : param->getMax();
        alert.accessoryView = input;
        [alert addButtonWithTitle:@"Apply"];
        [alert addButtonWithTitle:@"Cancel"];
        const int parameterIndex = param->index;
        if ([alert runModal] == NSAlertFirstButtonReturn)
        {
            param = self.plugin->getParameterByIndex(parameterIndex);
            if (!param) return;
            float value = input.floatValue;
            if (operation == 1 && value < param->getMax()) param->setMin(value);
            if (operation == 2 && value > param->getMin()) param->setMax(value);
            const int wireValue = *static_cast<int*>(param->get4ByteValue());
            self.plugin->ProcessParam(param->index, wireValue, REC_UpdateValue | REC_UpdateControl);
        }
    }
    [self refresh];
}
- (void)refresh
{
    for (NSNumber* index in self.controls)
    {
        auto param = self.plugin->getParameterByIndex(index.intValue);
        if (!param) continue;
        NSControl* control = self.controls[index];
        if ([control isKindOfClass:NSPopUpButton.class])
            [(NSPopUpButton*)control selectItemAtIndex:static_cast<NSInteger>(param->getFloat())];
        else if ([control isKindOfClass:NSButton.class])
            ((NSButton*)control).state = param->getFloat() < 0 ? NSControlStateValueMixed :
                param->getFloat() > 0 ? NSControlStateValueOn : NSControlStateValueOff;
        else if ([control isKindOfClass:NSSlider.class])
        {
            NSSlider* slider = (NSSlider*)control;
            slider.minValue = param->getMin();
            slider.maxValue = param->getMax();
            slider.floatValue = param->getFloat();
        }
        else if (![(NSTextField*)control currentEditor])
            control.stringValue = text(param->toString());
        NSTextField* value = self.values[index];
        if (value && !value.currentEditor) value.stringValue = text(param->toString());
    }
}
@end

struct PluginGUI::Impl
{
    Plugin* plugin;
    BendyEditorController* controller;
    std::atomic<bool> dirty{true};
    explicit Impl(Plugin* p) : plugin(p) {}
    void build()
    {
        controller = [[BendyEditorController alloc] init];
        controller.plugin = plugin;
        controller.controls = [NSMutableDictionary dictionary];
        controller.values = [NSMutableDictionary dictionary];
        controller.root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 540)];
        auto root = controller.root;
        root.wantsLayer = YES;
        root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
        NSTextField* title = label(@"BENDY", NSMakeRect(20, 492, 180, 32));
        title.font = [NSFont boldSystemFontOfSize:26];
        [root addSubview:title];
        NSPopUpButton* presets = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(270, 496, 310, 26) pullsDown:NO];
        [presets addItemWithTitle:@"Load a factory preset…"];
        // GetName is the same preset-name API used by FL Studio.
        for (int i = 0; i < 128; ++i)
        {
            char name[256] = {};
            plugin->GetName(FPN_Preset, i, 0, name);
            if (!name[0]) break;
            [presets addItemWithTitle:[NSString stringWithUTF8String:name] ?: @""];
        }
        presets.target = controller;
        presets.action = @selector(choosePreset:);
        [root addSubview:presets];
        NSTabView* tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(10, 44, 580, 404)];
        tabs.tabViewType = NSNoTabsNoBorder;
        controller.tabs = tabs;
        NSArray* names = @[@"Notes", @"MIDI CC", @"Envelope", @"Harmony & vibrato"];
        NSMutableArray<NSButton*>* tabButtons = [NSMutableArray array];
        for (int tab = 0; tab < 4; ++tab)
        {
            NSButton* button = [NSButton buttonWithTitle:names[tab] target:controller action:@selector(selectTab:)];
            button.frame = NSMakeRect(20 + tab * 140, 456, 140, 28);
            [button setButtonType:NSButtonTypePushOnPushOff];
            button.tag = tab;
            button.state = tab == 0 ? NSControlStateValueOn : NSControlStateValueOff;
            [root addSubview:button];
            [tabButtons addObject:button];
            NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:@(tab)];
            item.label = names[tab];
            NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 574, 404)];
            scroll.hasVerticalScroller = YES;
            scroll.scrollerStyle = NSScrollerStyleOverlay;
            NSView* document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 574, 404)];
            NSMutableArray<NSNumber*>* indexes = [NSMutableArray array];
            for (int i = 0; i < plugin->Info->NumParams; ++i)
            {
                auto param = plugin->getParameterByIndex(i);
                if (!param || !param->children.empty() || dynamic_cast<ParameterLink*>(param)) continue;
                const auto& id = param->id;
                if (id == L"currentPresetIndex" || id == L"expanded") continue;
                int group = id.find(L"midiKnob") == 0 ? 1 : id.find(L"asdr") == 0 ? 2 :
                    (id.find(L"harmon") == 0 || id == L"harmony" || id.find(L"vibrato") == 0) ? 3 : 0;
                if (tab == group) [indexes addObject:@(i)];
            }
            const CGFloat height = std::fmax(404, indexes.count * 34 + 20);
            document.frame = NSMakeRect(0, 0, 574, height);
            for (NSUInteger row = 0; row < indexes.count; ++row)
                [controller addParameter:plugin->getParameterByIndex(indexes[row].intValue)
                    toView:document y:height - 40 - row * 34];
            scroll.documentView = document;
            [document scrollPoint:NSMakePoint(0, height)];
            item.view = scroll;
            [tabs addTabViewItem:item];
        }
        controller.tabButtons = tabButtons;
        [root addSubview:tabs];
        NSTextField* help = label(@"Match PORT with your instrument’s MIDI input. Use ••• for note controls and automation.",
            NSMakeRect(20, 12, 560, 28));
        help.font = [NSFont systemFontOfSize:11];
        help.textColor = NSColor.secondaryLabelColor;
        [root addSubview:help];
        [controller refresh];
    }
};

PluginGUI::PluginGUI(void* plugin) : impl(new Impl(static_cast<Plugin*>(plugin))) {}
PluginGUI::~PluginGUI() { close(); delete impl; }
bool PluginGUI::open(void* parent)
{
    if (!parent || !NSThread.isMainThread) return false;
    impl->build();
    reparent(parent);
    return true;
}
void PluginGUI::reparent(void* parent)
{
    NSView* view = (__bridge NSView*)parent;
    if (!view) return;
    NSView* root = impl->controller.root;
    [root removeFromSuperview];
    [view setFrameSize:root.frame.size];
    [view addSubview:root];
}
void* PluginGUI::nativeView() const { return (__bridge void*)impl->controller.root; }
void PluginGUI::close()
{
    [impl->controller.root removeFromSuperview];
    impl->controller.plugin = nullptr;
    impl->controller = nil;
}
void PluginGUI::idle()
{
    if (impl->dirty.exchange(false)) [impl->controller refresh];
}
void PluginGUI::setParameter(int, float) { impl->dirty.store(true); }
void PluginGUI::reconnect()
{
    impl->dirty.store(true);
    [impl->controller refresh];
}
