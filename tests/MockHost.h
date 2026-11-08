#pragma once
#include "fp_plugclass.h"
#include <cstring>
#include <vector>

// Minimal host for exercising the real plugin callbacks without FL Studio.
struct MockHost : TFruityPlugHost
{
    std::vector<TMIDIOutMsg> messages;
    int notifiedParameter = -1;
    intptr_t Dispatcher(TPluginTag Sender, intptr_t ID, intptr_t Index, intptr_t Value) override { return {}; }
    void OnParamChanged(TPluginTag Sender, int Index, int Value) override { notifiedParameter = Index; }
    void OnHint(TPluginTag Sender, char *Text) override {  }
    void ComputeLRVol_Old(float &LVol, float &RVol, int Pan, float Volume) override {  }
    void Voice_Release(intptr_t Sender) override {  }
    void Voice_Kill(intptr_t Sender, BOOL KillHandle) override { }
    int Voice_ProcessEvent(intptr_t Sender, intptr_t EventID, intptr_t EventValue, intptr_t Flags) override { if (EventID == FPV_GetVelocity) { float velocity = 0.8f; int bits; std::memcpy(&bits, &velocity, sizeof(bits)); return bits; } return 0; }
    void LockMix_Old() override {  }
    void UnlockMix_Old() override {  }
    void MIDIOut_Delayed(TPluginTag Sender, intptr_t Msg) override { TMIDIOutMsg message; uint32_t bits = static_cast<uint32_t>(Msg); std::memcpy(&message, &bits, sizeof(message)); messages.push_back(message); }
    void MIDIOut(TPluginTag Sender, intptr_t Msg) override { TMIDIOutMsg message; uint32_t bits = static_cast<uint32_t>(Msg); std::memcpy(&message, &bits, sizeof(message)); messages.push_back(message); }
    void AddWave_32FM_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, float &LastLVol, float &LastRVol) override {  }
    void AddWave_32FS_32FS_Ramp(void *SourceBuffer, void *DestBuffer, int Length, float LVol, float RVol, float &LastLVol, float &LastRVol) override {  }
    bool LoadSample(TSampleHandle &Handle, char *FileName, PWaveFormatExtensible NeededFormat, int Flags) override { return {}; }
    void * GetSampleData(TSampleHandle Handle, int &Length) override { return {}; }
    void CloseSample(TSampleHandle Handle) override {  }
    int GetSongMixingTime() override { return {}; }
    double GetSongMixingTime_A() override { return {}; }
    double GetSongPlayingTime() override { return {}; }
    void OnControllerChanged(TPluginTag Sender, intptr_t Index, intptr_t Value) override {  }
    void * GetSendBuffer(intptr_t Num) override { return {}; }
    void PlugMsg_Delayed(TPluginTag Sender, intptr_t Msg) override {  }
    void PlugMsg_Kill(TPluginTag Sender, intptr_t MSg) override {  }
    void GetSampleInfo(TSampleHandle Handle, PSampleInfo Info) override {  }
    void DistWave_32FM(int DistType, int DistThres, void *SourceBuffer, int Length, float DryVol, float WetVol, float Mul) override {  }
    void * GetMixBuffer(int Num) override { return {}; }
    void * GetInsBuffer(TPluginTag Sender, int Ofs) override { return {}; }
    BOOL PromptEdit(int x, int y, char *SetCaption, char *s, int &c) override { return {}; }
    void SuspendOutput_Old() override {  }
    void ResumeOutput_Old() override {  }
    void GetSampleRegion(TSampleHandle Handle, int RegionNum, PSampleRegion Region) override {  }
    void ComputeLRVol(float &LVol, float &RVol, float Pan, float Volume) override {  }
    void LockPlugin(TPluginTag Sender) override {  }
    void UnlockPlugin(TPluginTag Sender) override {  }
    void LockMix_Shared_Old() override {  }
    void UnlockMix_Shared_Old() override {  }
    void GetInBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer IBuffer) override {  }
    void GetOutBuffer(TPluginTag Sender, intptr_t Index, PIOBuffer OBuffer) override {  }
    TOutVoiceHandle TriggerOutputVoice(TVoiceParams *VoiceParams, intptr_t SetIndex, intptr_t SetTag) override { return {}; }
    void OutputVoice_Release(TOutVoiceHandle Handle) override {  }
    void OutputVoice_Kill(TOutVoiceHandle Handle) override {  }
    int OutputVoice_ProcessEvent(TOutVoiceHandle Handle, intptr_t EventID, intptr_t EventValue, intptr_t Flags) override { return {}; }
    BOOL PromptEdit_Ex(int x, int y, const char* SetCaption, char* Text, int& Color1, int& Color2, int& IconIndex, int FontHeight, int SetOptions) override { return {}; }
    void SuspendOutput(TPluginTag Sender) override {  }
    void ResumeOutput(TPluginTag Sender) override {  }
};
