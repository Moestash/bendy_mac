#import <Cocoa/Cocoa.h>
#include "mac/PluginGUI.h"
#include "Plugin.h"
#include "Parameter.h"
#include "BitmapFont.h"
#include "BendyArtwork.h"
// The FL SDK uses a Windows-style BOOL macro; AppKit's BOOL has a different
// ABI on Apple Silicon. Keep it out of Objective-C properties and overrides.
#undef BOOL
#include <algorithm>
#include <atomic>
#include <codecvt>
#include <locale>

namespace {
constexpr CGFloat scale = 3; // Windows sScaleFactor, in macOS points.
NSRect scaled(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return NSMakeRect(x*scale, y*scale, w*scale, h*scale); }
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
NSImage* artwork(NSString* name)
{
    static NSMutableDictionary<NSString*, NSImage*>* cache = [NSMutableDictionary dictionary];
    if (cache[name]) return cache[name];
    for (const auto& entry : BendyArtwork::images)
    {
        if (![name isEqualToString:[NSString stringWithUTF8String:entry.name]]) continue;
        NSImage* original = [[NSImage alloc] initWithData:[NSData dataWithBytes:entry.bytes length:entry.size]];
        CGImageRef source = [original CGImageForProposedRect:nullptr context:nil hints:nil];
        const size_t width = CGImageGetWidth(source), height = CGImageGetHeight(source);
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap = CGBitmapContextCreate(nullptr, width, height, 8, width*4, colors,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colors);
        CGContextDrawImage(bitmap, CGRectMake(0, 0, width, height), source);
        auto pixels = static_cast<unsigned char*>(CGBitmapContextGetData(bitmap));
        // The Windows resource builder turns the font atlas's magenta into alpha.
        for (size_t i = 0; i < width*height; ++i)
            if (pixels[i*4] == 255 && pixels[i*4+1] == 0 && pixels[i*4+2] == 255)
                std::memset(pixels+i*4, 0, 4);
        CGImageRef keyed = CGBitmapContextCreateImage(bitmap);
        NSImage* image = [[NSImage alloc] initWithCGImage:keyed size:NSMakeSize(width, height)];
        CGImageRelease(keyed);
        CGContextRelease(bitmap);
        cache[name] = image;
        return image;
    }
    return nil;
}
void sprite(NSString* name, NSRect destination, NSRect source)
{
    NSImage* image = artwork(name);
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationNone;
    // Source sprite sheets count rows down from the top.
    source.origin.y = image.size.height - NSMaxY(source);
    [image drawInRect:destination fromRect:source operation:NSCompositingOperationSourceOver
        fraction:1 respectFlipped:YES hints:nil];
}
void bitmapText(const std::wstring& value, NSRect rect, NSTextAlignment alignment = NSTextAlignmentCenter)
{
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(rect);
    CGFloat width = value.size()*4*scale;
    CGFloat x = rect.origin.x;
    if (alignment == NSTextAlignmentCenter) x += (rect.size.width-width)/2;
    if (alignment == NSTextAlignmentRight) x += rect.size.width-width;
    for (wchar_t character : value)
    {
        int glyph = 31; // '?'
        for (size_t i = 0; i < sizeof(kBendyBitmapCharacters)/sizeof(wchar_t); ++i)
            if (kBendyBitmapCharacters[i] == character) { glyph = static_cast<int>(i); break; }
        if (glyph >= 256) glyph = 31;
        sprite(@"biosFontCaseSensitive_halfres", NSMakeRect(std::round(x), rect.origin.y, 4*scale, 4*scale),
            NSMakeRect((glyph%16)*8, (glyph/16)*8, 8, 8));
        x += 4*scale;
    }
    [NSGraphicsContext restoreGraphicsState];
}
void bitmapNumber(int value, NSRect rect)
{
    std::string digits = std::to_string(value);
    if (digits.size() > 2) digits = "--";
    while (digits.size() < 2) digits = " " + digits;
    for (int i = 0; i < 2; ++i)
    {
        int frame = digits[i] == ' ' ? 0 : digits[i] == '-' ? 11 : digits[i]-'0'+1;
        sprite(@"bendyNumbers", NSMakeRect(rect.origin.x+i*7*scale, rect.origin.y, 6*scale, 7*scale), NSMakeRect(0, frame*7, 6, 7));
    }
}
}

enum ControlKind { Spinner, Knob, Toggle, BitmapText, Expand, Presets };
@class BendyEditorController;
@interface BendyBitmapControl : NSControl
@property(nonatomic, weak) BendyEditorController* controller;
@property(nonatomic) ControlKind kind;
@property(nonatomic, copy) NSString* spriteName;
@property(nonatomic, copy) NSString* fixedText;
@property(nonatomic, copy) NSString* prefix;
@property(nonatomic) BOOL textMode;
@property(nonatomic) BOOL arrows;
@property(nonatomic) NSTextAlignment bitmapAlignment;
@property(nonatomic) float displayedValue;
@property(nonatomic) CGFloat dragStartY;
@property(nonatomic) float dragStartValue;
@property(nonatomic) BOOL dragging;
- (void)step:(float)amount;
@end

@interface BendyBitmapEditor : NSView
@property(nonatomic, weak) BendyEditorController* controller;
@property(nonatomic, assign) Plugin* plugin;
@property(nonatomic) BOOL expanded;
- (void)animate;
@end

@interface BendyEditorController : NSObject
@property(nonatomic, assign) Plugin* plugin;
@property(nonatomic, strong) BendyBitmapEditor* root;
@property(nonatomic, strong) NSMutableArray<BendyBitmapControl*>* controls;
- (void)build;
- (void)refresh;
- (void)change:(BendyBitmapControl*)sender;
- (void)edit:(BendyBitmapControl*)sender;
- (void)showPresets:(NSView*)sender;
- (void)choosePreset:(NSMenuItem*)sender;
- (void)showParameterMenu:(BendyBitmapControl*)sender;
- (NSMenu*)menuForParameter:(PlugParameter*)param;
- (void)menuAction:(NSMenuItem*)sender;
- (void)selectValue:(NSMenuItem*)sender;
- (void)setExpanded:(BOOL)expanded;
@end

@implementation BendyBitmapControl
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (float)floatValue { return self.displayedValue; }
- (void)setFloatValue:(float)value { self.displayedValue = value; self.needsDisplay = YES; }
- (NSString*)accessibilityRole
{
    if (self.kind == Toggle) return NSAccessibilityCheckBoxRole;
    return self.kind == Knob || self.kind == Spinner ? NSAccessibilitySliderRole : NSAccessibilityButtonRole;
}
- (id)accessibilityValue
{
    Plugin* plugin = self.controller.plugin;
    if (!plugin) return nil;
    auto param = plugin->getParameterByIndex(static_cast<int>(self.tag));
    return param && self.kind == BitmapText ? text(param->toString()) : @(self.floatValue);
}
- (BOOL)accessibilityPerformIncrement { [self step:1]; return YES; }
- (BOOL)accessibilityPerformDecrement { [self step:-1]; return YES; }
- (BOOL)accessibilityPerformPress
{
    if (self.kind == Toggle) { self.floatValue = self.floatValue > 0 ? 0 : 1; [self.controller change:self]; }
    else if (self.kind == Expand) [self.controller setExpanded:!self.controller.root.expanded];
    else if (self.kind == Presets) [self.controller showPresets:self];
    else [self.controller edit:self];
    return YES;
}
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    Plugin* plugin = self.controller.plugin;
    if (!plugin) return;
    auto param = self.tag >= 0 ? plugin->getParameterByIndex(static_cast<int>(self.tag)) : nullptr;
    if (self.kind == Toggle)
    {
        int frame = self.floatValue < 0 ? 2 : self.floatValue > 0 ? 1 : 0;
        NSSize size = self.bounds.size;
        sprite(self.spriteName, self.bounds, NSMakeRect(0, frame*size.height/scale, size.width/scale, size.height/scale));
    }
    else if (self.kind == Knob && param)
    {
        float normalized = (self.floatValue-param->getMin())/(param->getMax()-param->getMin());
        int frame = static_cast<int>(std::fmax(0, std::fmin(1, normalized))*23);
        sprite(@"knob", self.bounds, NSMakeRect(0, frame*11, 11, 11));
    }
    else if (self.kind == Spinner && param)
    {
        if (self.textMode)
        {
            NSRect area = self.bounds;
            area.origin.x += self.arrows ? 8 : scale;
            area.origin.y += area.size.height/2-4;
            area.size.width -= self.arrows ? 38 : 2*scale;
            bitmapText(param->toReadable(), area, self.bitmapAlignment);
        }
        else bitmapNumber(static_cast<int>(self.floatValue), scaled(2, 2, 13, 7));
        if (self.arrows)
        {
            CGFloat x = self.bounds.size.width-9*scale;
            sprite(@"bendySpinnerUp", NSMakeRect(x, 0, 9*scale, 6*scale), NSMakeRect(0, 0, 9, 6));
            sprite(@"bendySpinnerDown", NSMakeRect(x, 5*scale, 9*scale, 6*scale), NSMakeRect(0, 0, 9, 6));
        }
    }
    else if (self.kind == BitmapText)
    {
        std::wstring value = self.fixedText ? toWideString(self.fixedText) : param ? param->toString() : L"";
        if (self.prefix) value = toWideString(self.prefix)+value;
        bitmapText(value, self.bounds, self.bitmapAlignment);
    }
    else if (self.kind == Expand)
        sprite(self.controller.root.expanded ? @"buttonContract" : @"buttonExpand", self.bounds, NSMakeRect(0, 0, 23, 7));
}
- (void)step:(float)amount
{
    Plugin* plugin = self.controller.plugin;
    if (!plugin) return;
    auto param = plugin->getParameterByIndex(static_cast<int>(self.tag));
    if (!param) return;
    self.floatValue = std::fmax(param->getMin(), std::fmin(param->getMax(), self.floatValue+amount*param->getInc()));
    [self.controller change:self];
}
- (void)scrollWheel:(NSEvent*)event
{
    if (self.kind == Knob || self.kind == Spinner)
        [self step:(event.scrollingDeltaY > 0 ? 1 : event.scrollingDeltaY < 0 ? -1 : 0) * ((event.modifierFlags & NSEventModifierFlagShift) ? 0.1f : 1.0f)];
}
- (void)keyDown:(NSEvent*)event
{
    if (event.keyCode == 126 || event.keyCode == 124) [self step:1];
    else if (event.keyCode == 125 || event.keyCode == 123) [self step:-1];
    else if (event.keyCode == 36 || event.keyCode == 49) [self accessibilityPerformPress];
    else [super keyDown:event];
}
- (void)mouseDown:(NSEvent*)event
{
    if (event.modifierFlags & NSEventModifierFlagControl) { [self rightMouseDown:event]; return; }
    [self.window makeFirstResponder:self];
    if (self.kind == Expand) { [self.controller setExpanded:!self.controller.root.expanded]; return; }
    if (self.kind == Presets) { [self.controller showPresets:self]; return; }
    if (self.kind == Toggle) { self.floatValue = self.floatValue > 0 ? 0 : 1; [self.controller change:self]; return; }
    if (self.kind == BitmapText || event.clickCount > 1) { [self.controller edit:self]; return; }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.kind == Spinner)
    {
        if (self.arrows && point.x >= self.bounds.size.width-9*scale) [self step:point.y < 5*scale ? 1 : -1];
        else [self.controller edit:self];
        return;
    }
    // Linear knob drag, with Shift for fine adjustments, like the Windows knob.
    self.dragStartY = event.locationInWindow.y;
    self.dragStartValue = self.floatValue;
    self.dragging = YES;
}
- (void)mouseDragged:(NSEvent*)event
{
    Plugin* plugin = self.controller.plugin;
    if (!self.dragging || !plugin) return;
    auto param = plugin->getParameterByIndex(static_cast<int>(self.tag));
    if (!param) return;
    CGFloat factor = (event.modifierFlags & NSEventModifierFlagShift) ? 0.1 : 1;
    float value = self.dragStartValue+(event.locationInWindow.y-self.dragStartY)*(param->getMax()-param->getMin())/120*factor;
    self.floatValue = std::fmax(param->getMin(), std::fmin(param->getMax(), value));
    [self.controller change:self];
}
- (void)mouseUp:(NSEvent*)event { (void)event; self.dragging = NO; }
- (void)rightMouseDown:(NSEvent*)event
{
    (void)event;
    if (self.kind == Presets || self.kind == Expand) [self.controller showPresets:self];
    else [self.controller showParameterMenu:self];
}
@end

@implementation BendyBitmapEditor
{
    float letterLevels[5];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)animate
{
    if (!self.plugin) return;
    for (int i = 0; i < 5; ++i)
        letterLevels[i] = self.plugin->letters[i] ? 1 : std::fmax(0, letterLevels[i]-0.1f);
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    if (!self.plugin) return;
    sprite(self.expanded ? @"bendyBack" : @"bendyBackShort", self.bounds,
        NSMakeRect(0, 0, 149, self.expanded ? 163 : 39));
    NSArray* letters = @[@"bendyLetterB", @"bendyLetterE", @"bendyLetterN", @"bendyLetterD", @"bendyLetterY"];
    for (int i = 0; i < 5; ++i)
        sprite(letters[i], scaled(6, 5+i*6, 7, 6), NSMakeRect(0, static_cast<int>(letterLevels[i]*2)*6, 7, 6));
    // Same vertical version stamp as Windows (0.994).
    int version[] = {12, 1, 11, 10, 10, 5};
    for (int i = 0; i < 6; ++i)
        sprite(@"version_num", scaled(139, 8+i*4, 5, 3), NSMakeRect(0, version[i]*3, 5, 3));
    if (self.plugin->isLegacy()) bitmapText(L"LEGACY", scaled(18, 32, 24, 8));
    if (!self.expanded) return;
    auto value = [&](const wchar_t* id) { return self.plugin->getParameter(id)->getNormalized(); };
    float attack = value(L"asdrCCValue0"), sustain = value(L"asdrCCValue1"), decay = value(L"asdrCCValue2"), release = value(L"asdrCCValue3");
    float widths[] = {attack, decay, 1, release}, heights[] = {1, sustain, sustain, 0};
    float total = attack+decay+1+release, x = 0;
    NSBezierPath* graph = [NSBezierPath bezierPath];
    [graph moveToPoint:NSMakePoint(6*scale, 97*scale)];
    for (int i = 0; i < 4; ++i)
    {
        x += widths[i]/total;
        [graph lineToPoint:NSMakePoint((6+x*39)*scale, (88+(1-heights[i])*9)*scale)];
    }
    [NSColor.whiteColor setStroke];
    graph.lineWidth = scale;
    [graph stroke];
}
- (void)rightMouseDown:(NSEvent*)event { (void)event; [self.controller showPresets:self]; }
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
- (void)showParameterMenu:(BendyBitmapControl*)sender
{
    auto param = self.plugin->getParameterByIndex(static_cast<int>(sender.tag));
    if (!param) return;
    [[self menuForParameter:param] popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
}
- (void)change:(BendyBitmapControl*)sender
{
    auto param = self.plugin->getParameterByIndex(static_cast<int>(sender.tag));
    if (!param) return;
    float value = std::fmax(param->getMin(), std::fmin(param->getMax(), sender.floatValue));
    if (dynamic_cast<ParameterInt*>(param)) value = std::round(value);
    param->setFloat(value);
    int wireValue;
    std::memcpy(&wireValue, param->get4ByteValue(), sizeof(wireValue));
    self.plugin->ProcessParam(param->index, wireValue, REC_UpdateValue | REC_UpdateControl);
    self.plugin->PlugHost->OnParamChanged(self.plugin->HostTag, param->index, wireValue);
    [self refresh];
}
- (void)selectValue:(NSMenuItem*)sender
{
    NSArray<NSNumber*>* info = sender.representedObject;
    for (BendyBitmapControl* control in self.controls)
        if (control.tag == info[0].integerValue) { control.floatValue = info[1].floatValue; [self change:control]; break; }
}
- (void)edit:(BendyBitmapControl*)sender
{
    auto param = self.plugin->getParameterByIndex(static_cast<int>(sender.tag));
    if (!param) return;
    if (auto selection = dynamic_cast<ParameterStringSelection*>(param))
    {
        NSMenu* menu = [[NSMenu alloc] initWithTitle:text(param->name)];
        for (int i = 0; i < static_cast<int>(selection->strings.size()); ++i)
        {
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:text(selection->toReadable(i, false)) action:@selector(selectValue:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = @[@(param->index), @(i)];
            item.state = i == static_cast<int>(param->getFloat()) ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:item];
        }
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
        return;
    }
    const int index = param->index;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = text(param->name);
    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    input.stringValue = text(param->toString());
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.window.initialFirstResponder = input;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    param = self.plugin->getParameterByIndex(index);
    if (!param) return;
    if (dynamic_cast<ParameterString*>(param)) { param->setFromString(toWideString(input.stringValue)); [self refresh]; }
    else { sender.floatValue = input.floatValue; [self change:sender]; }
}
- (void)showPresets:(NSView*)sender
{
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Factory presets"];
    for (int i = 0; i < 128; ++i)
    {
        char name[256] = {};
        self.plugin->GetName(FPN_Preset, i, 0, name);
        if (!name[0]) break;
        NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithUTF8String:name] action:@selector(choosePreset:) keyEquivalent:@""];
        item.target = self;
        item.tag = i;
        [menu addItem:item];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, sender.bounds.size.height) inView:sender];
}
- (void)choosePreset:(NSMenuItem*)sender
{
    // The host may destroy this editor during the preset change.
    Plugin* plugin = self.plugin;
    plugin->Dispatcher(FPD_SetPreset, sender.tag, 0);
}
- (void)setExpanded:(BOOL)expanded
{
    BOOL changed = self.root.expanded != expanded;
    self.root.expanded = expanded;
    self.plugin->getParameter(L"expanded")->setFloat(expanded ? 1 : 0);
    NSSize size = NSMakeSize(149*scale, (expanded ? 163 : 39)*scale);
    [self.root setFrameSize:size];
    for (BendyBitmapControl* control in self.controls)
        control.hidden = NSMinY(control.frame) >= 39*scale && !expanded;
    if (self.root.superview)
    {
        [self.root.superview setFrameSize:size];
        if (changed) self.plugin->PlugHost->Dispatcher(self.plugin->HostTag, FHD_EditorResized, 0, 0);
    }
    self.root.needsDisplay = YES;
}
- (void)refresh
{
    for (BendyBitmapControl* control in self.controls)
    {
        auto param = self.plugin->getParameterByIndex(static_cast<int>(control.tag));
        if (param)
        {
            control.floatValue = param->getFloat();
            control.toolTip = [NSString stringWithFormat:@"%@: %@\nRight-click for automation and note controls.", text(param->getName()), text(param->toReadable())];
        }
        control.needsDisplay = YES;
    }
    [self setExpanded:self.plugin->getParameter(L"expanded")->getFloat() > 0.5f];
}
- (BendyBitmapControl*)add:(ControlKind)kind id:(const wchar_t*)identifier rect:(NSRect)rect sprite:(NSString*)image
{
    BendyBitmapControl* control = [[BendyBitmapControl alloc] initWithFrame:rect];
    control.kind = kind;
    control.controller = self;
    control.spriteName = image;
    control.bitmapAlignment = NSTextAlignmentCenter;
    control.tag = -1;
    control.target = self;
    control.action = @selector(change:);
    if (identifier)
    {
        auto param = self.plugin->getParameter(identifier);
        control.tag = param->index;
        [control setAccessibilityLabel:text(param->name)];
    }
    [self.root addSubview:control];
    [self.controls addObject:control];
    return control;
}
- (BendyBitmapControl*)spinner:(const wchar_t*)id rect:(NSRect)rect text:(BOOL)textMode arrows:(BOOL)arrows
{
    auto control = [self add:Spinner id:id rect:rect sprite:nil];
    control.textMode = textMode;
    control.arrows = arrows;
    return control;
}
- (void)build
{
    self.controls = [NSMutableArray array];
    self.root = [[BendyBitmapEditor alloc] initWithFrame:scaled(0, 0, 149, 39)];
    self.root.plugin = self.plugin;
    self.root.controller = self;
    auto expand = [self add:Expand id:nullptr rect:scaled(117, 34, 23, 7) sprite:nil];
    [expand setAccessibilityLabel:@"Show or hide advanced controls"];
    expand.toolTip = @"Show or hide advanced controls";
    auto logo = [self add:Presets id:nullptr rect:scaled(3, 3, 13, 33) sprite:nil];
    logo.toolTip = @"Click for factory presets";
    [logo setAccessibilityLabel:@"Factory presets"];
    [self spinner:L"port" rect:scaled(50, 7, 25, 11) text:NO arrows:YES];
    [self spinner:L"channel" rect:scaled(112, 7, 25, 11) text:NO arrows:YES];
    [self spinner:L"range" rect:scaled(50, 21, 25, 11) text:NO arrows:YES];
    const wchar_t* toggles[] = {L"enableNoteTrigger", L"enableNoteVelocity", L"enableNotePanning", L"enableNotePitch"};
    NSArray* toggleImages = @[@"checkboxTriggerNotesSimple", @"checkboxVelocitySimple", @"checkboxPanningSimple", @"checkboxPitchSimple"];
    for (int i = 0; i < 4; ++i) [self add:Toggle id:toggles[i] rect:scaled(81+i*15, 21, 11, 11) sprite:toggleImages[i]];
    auto patch = [self spinner:L"midiPatch" rect:scaled(4, 42, 88, 11) text:YES arrows:YES];
    patch.bitmapAlignment = NSTextAlignmentLeft;
    [self spinner:L"midiBankCoarse" rect:scaled(93, 42, 25, 11) text:NO arrows:YES];
    [self spinner:L"midiBankFine" rect:scaled(119, 42, 25, 11) text:NO arrows:YES];
    [self add:Toggle id:L"vibratoEnabled" rect:scaled(39, 56, 5, 5) sprite:@"tinyCheckboxSimple"];
    [self add:Knob id:L"vibratoSpeed" rect:scaled(70, 58, 11, 11) sprite:nil];
    [self add:Knob id:L"vibratoDepth" rect:scaled(132, 58, 11, 11) sprite:nil];
    [self add:Toggle id:L"asdrCCEnable" rect:scaled(2, 79, 5, 5) sprite:@"tinyCheckboxSimple"];
    [self add:BitmapText id:L"asdrCCName" rect:scaled(8, 81, 38, 6) sprite:nil];
    NSArray* envelopeNames = @[@"A", @"S", @"D", @"R"];
    for (int i = 0; i < 4; ++i)
    {
        std::wstring cc = L"asdrCC"+std::to_wstring(i), value = L"asdrCCValue"+std::to_wstring(i);
        auto caption = [self add:BitmapText id:cc.c_str() rect:scaled(51+i*12, 81, 5, 6) sprite:nil];
        caption.fixedText = envelopeNames[i];
        [self add:Knob id:value.c_str() rect:scaled(48+i*12, 87, 11, 11) sprite:nil];
    }
    [self add:Toggle id:L"harmonizerEnabled" rect:scaled(99, 79, 5, 5) sprite:@"tinyCheckboxSimple"];
    [self spinner:L"harmonyKey" rect:scaled(101, 85, 11, 11) text:YES arrows:NO];
    [self spinner:L"harmonyType" rect:scaled(113, 85, 20, 11) text:YES arrows:NO];
    [self spinner:L"harmony" rect:scaled(134, 85, 11, 11) text:YES arrows:NO];
    for (int i = 0; i < 8; ++i)
    {
        int x = 15+(i%4)*36, y = 110+(i/4)*30;
        std::wstring suffix = std::to_wstring(i);
        [self add:Toggle id:(L"midiKnobEnabled"+suffix).c_str() rect:scaled(x-13, y-10, 5, 5) sprite:@"tinyCheckboxSimple"];
        [self add:Knob id:(L"midiKnobValue"+suffix).c_str() rect:scaled(x, y, 11, 11) sprite:nil];
        auto cc = [self add:BitmapText id:(L"midiKnobCC"+suffix).c_str() rect:scaled(x-7, y-6, 25, 4) sprite:nil];
        cc.prefix = @"CC-";
        [self add:BitmapText id:(L"midiKnobName"+suffix).c_str() rect:scaled(x-12, y+13, 34, 4) sprite:nil];
    }
    [self refresh];
}
@end

struct PluginGUI::Impl
{
    BendyEditorController* controller;
    std::atomic<bool> dirty{true};
    explicit Impl(Plugin* plugin)
    {
        controller = [[BendyEditorController alloc] init];
        controller.plugin = plugin;
    }
};
PluginGUI::PluginGUI(void* plugin) : impl(new Impl(static_cast<Plugin*>(plugin))) {}
PluginGUI::~PluginGUI() { close(); delete impl; }
bool PluginGUI::open(void* parent)
{
    if (!parent || !NSThread.isMainThread) return false;
    [impl->controller build];
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
    impl->controller.root.plugin = nullptr;
    impl->controller.plugin = nullptr;
    impl->controller = nil;
}
void PluginGUI::idle()
{
    if (impl->dirty.exchange(false)) [impl->controller refresh];
    [impl->controller.root animate];
}
void PluginGUI::setParameter(int, float) { impl->dirty.store(true); }
void PluginGUI::reconnect() { [impl->controller refresh]; }
