# BENDY
An FL Studio native plugin for using piano roll note bends with Virtual Instruments (VST) and external synthesizers.

<img width="230" alt="image" src="https://github.com/user-attachments/assets/827120d6-6eb5-48ca-8386-c7082dfd632d" />



**Basic Use**

Add BENDY to your project, then add your most beloved VST plugin (The order doesn't matter, BENDY can be added later for any plugin!). Click the gear in the corner of your VST, then click the button that looks like a plug overtop of a gear. In the MIDI section, adjust the "Input port" field to match the "PORT" value in BENDY:
![image](https://github.com/user-attachments/assets/82d922d3-d459-4b6c-971a-20459e81f881)
Simple piano roll bends should now work in most plugins! But, since BENDY's BEND parameter is set to 2, it will only bend up to 2 semitones (notes) up or down. 

**Bending More Than 2 Semitones**

First, try changing BENDY's BEND parameter to the desired bend range:

![image](https://github.com/user-attachments/assets/fee24f80-7d72-4862-8612-755d290169d1)

This may work if the plugin accepts a bend range message, but most plugins don't... If it's not working, you need to figure out where the bend range parameter is hiding in your plugin. Here are a few examples to give you an idea of what this setting looks like and how they might have been sneaky in burying it:

**REFX NEXUS**

With this one you should set speed up to full if you don't want notes to quack.

![image](https://github.com/user-attachments/assets/e993c193-b582-4dfb-a252-0aff7a06967c)


**KONTAKT**

This one varies per library, some examples:

![image](https://github.com/user-attachments/assets/5fbf9a31-b4d4-4a1b-9fba-f316105143ca)
![image](https://github.com/user-attachments/assets/641c622b-46e5-48ed-9ba5-40fc9f1fa366)


**SYLENTH**

These folks know where bend range should go.

![image](https://github.com/user-attachments/assets/694bb314-7f87-4342-9c8f-484f4ad54ac3)


**Arturia Synclavier V**

God help you with these, every Arturia plugin is different and as far as I'm aware there's no standard for setting bend range.

![image](https://github.com/user-attachments/assets/541e79a3-e82a-4596-8831-438521f95208)



**Using BENDY with an external synthesizer**

The process is exactly the same. BENDY will send MIDI notes on whatever port it has set, so all you need to do is plug your synthesizer into the same port, or route it to that port in FL Studio's MIDI settings. You're on your own finding where the pitch bend range is on these, sorry!


**Presets**

There are some presets for synths I like to use: 

<img width="293" alt="image" src="https://github.com/user-attachments/assets/6f9d94e4-15ff-4d8a-be50-a40dae7a0530" />

These automatically hook up some common controls to BENDY's CC knobs, Cutoff and Reverb in NEXUS for example. If you create a preset, please share it and I'll add it to a later version! You should be able to export your preset with the "Save preset as..." button. BENDY also supports note names, you can see this in action with the Shreddage preset. Unfortunately there's no way to set these through BENDY at the moment, but I plan to add one later. If your preset would benefit from note names, just let me know what notes need names when you share your preset and I can add them on my end for now.

If you run into any problems, especially crashes, or if you want a preset added, please open an issue here or email me at superjoebob@gmail.com!

This plugin uses Steinberg's VSTGUI: https://github.com/steinbergmedia/vstgui

## Building on macOS

Requires macOS 11 or newer, Xcode Command Line Tools (or Xcode), and CMake 3.20+.
Install the command line tools with `xcode-select --install` if needed. With
Homebrew, CMake can be installed with `brew install cmake`.

From this repository's directory:

```sh
cmake -S . -B build-macos -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build-macos --parallel
ctest --test-dir build-macos --output-on-failure
```

The resulting **`build-macos/BENDY/BENDY_x64.dylib`** is a universal FL Studio
native plugin for Apple Silicon and Intel. The `_x64` filename follows FL
Studio's native plugin naming convention; both architectures are included.
The build ad-hoc signs the library for local use. No third-party GUI library,
Windows resource builder, or .NET installation is required on macOS.

Quit FL Studio, then install into your actual FL Studio app:

```sh
./scripts/install-macos.sh "/Applications/FL Studio 2026.app"
```

The installer copies the library and `Plugin.nfo` into
`Contents/Resources/FL/Plugins/Fruity/Generators/BENDY/` within that app and
backs up an existing BENDY installation before replacing its files. Use your
installed app's name if it differs. Administrator access may be needed if the
app is not writable. FL Studio updates may require reinstalling BENDY.
Refresh FL Studio's plugin list and add BENDY as a native generator. This
library is not a VST or Audio Unit and does not belong in `Library/Audio/Plug-Ins`.

macOS uses a Cocoa editor with tabs for notes/routing, MIDI CC, envelope, and
harmony/vibrato. The **•••** buttons expose FL Studio's automation menu, custom
parameter ranges, and full/upper/lower note-control assignment. CC names and
numbers are editable. A mixed-state enable checkbox means the CC has not yet
been activated; changing its value enables it. Factory presets are available
in the editor and through FL Studio. The Windows VSTGUI editor remains in use
for Windows builds.

The port preserves the existing parameter IDs/indexes and Windows state wire
format (32-bit header and UTF-16 strings). Automated tests cover Unicode state
round trips, Windows-format byte fixtures, malformed-state handling, MIDI
note/bend output, and dynamic loading through `CreatePlugInstance`.
An additional Cocoa integration test checks editing, state restoration,
reparenting, and cleanup; run it in a macOS desktop session:

```sh
./build-macos/bendy_tests --gui
```

The port has been built and tested with a mock FL Studio host on Apple Silicon
and under Rosetta for Intel. The Cocoa editor integration test and an Apple
Silicon AddressSanitizer/UndefinedBehaviorSanitizer run also pass.
Playback and project compatibility inside the
actual FL Studio host still require validation; the Windows build has not
been rebuilt as part of this port. For distribution beyond local use, supply
your own Developer ID signing/notarization workflow.
