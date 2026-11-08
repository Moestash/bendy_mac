#pragma once

class Plugin;

// Cocoa implementation; the Windows editor continues to use VSTGUI.
class PluginGUI
{
public:
    explicit PluginGUI(void* plugin);
    ~PluginGUI();
    bool open(void* parent);
    void close();
    void reparent(void* parent);
    void* nativeView() const;
    void idle();
    void setParameter(int hash, float value);
    void reconnect();

private:
    struct Impl;
    Impl* impl;
};
