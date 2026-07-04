#import "Basic";

#scope_export

AudioUnit                   :: *void;
AudioComponent              :: *void;
AudioComponentInstance      :: AudioUnit;
AudioUnitPropertyID         :: u32;
AudioUnitScope              :: u32;
AudioUnitElement            :: u32;
AudioFormatID               :: u32;
AudioFormatFlags            :: u32;
AudioUnitRenderActionFlags  :: u32;
AudioObjectID               :: u32;

kAudioUnitType_Output           :: #run fourcc("auou");
kAudioUnitSubType_DefaultOutput :: #run fourcc("def ");
kAudioUnitSubType_HALOutput     :: #run fourcc("ahal");
kAudioUnitManufacturer_Apple    :: #run fourcc("appl");

kAudioFormatLinearPCM           :: #run fourcc("lpcm");

kAudioUnitProperty_StreamFormat      :: 8;
kAudioUnitProperty_SetRenderCallback :: 23;
kAudioUnitProperty_MaximumFramesPerSlice :: 14;

kAudioUnitScope_Global :: 0;
kAudioUnitScope_Input  :: 1;
kAudioUnitScope_Output :: 2;

kAudioFormatFlagIsFloat          : u32 : (1 << 0);
kAudioFormatFlagIsBigEndian      : u32 : (1 << 1);
kAudioFormatFlagIsSignedInteger  : u32 : (1 << 2);
kAudioFormatFlagIsPacked         : u32 : (1 << 3);
kAudioFormatFlagIsAlignedHigh    : u32 : (1 << 4);
kAudioFormatFlagIsNonInterleaved : u32 : (1 << 5);

kAudioObjectSystemObject        : AudioObjectID : 1;
kAudioObjectPropertyScopeGlobal  : u32 : #run fourcc("glob");
kAudioObjectPropertyElementMain  : u32 : 0;
kAudioHardwarePropertyDefaultOutputDevice : u32 : #run fourcc("dout");
kAudioDevicePropertyNameCFString : u32 : #run fourcc("lnam");

AudioComponentDescription :: struct {
    componentType:         OSType;
    componentSubType:      OSType;
    componentManufacturer: OSType;
    componentFlags:        u32 = 0;
    componentFlagsMask:    u32 = 0;
}

AudioStreamBasicDescription :: struct {
    mSampleRate:       float64;
    mFormatID:         u32;
    mFormatFlags:      u32;
    mBytesPerPacket:   u32;
    mFramesPerPacket:  u32;
    mBytesPerFrame:    u32;
    mChannelsPerFrame: u32;
    mBitsPerChannel:   u32;
    mReserved:         u32 = 0;
}

AudioObjectPropertyAddress :: struct {
    mSelector: u32;
    mScope:    u32;
    mElement:  u32;
}

SMPTETime :: struct {
    mSubframes:       s16;
    mSubframeDivisor: s16;
    mCounter:         u32;
    mType:            u32;
    mFlags:           u32;
    mHours:           s16;
    mMinutes:         s16;
    mSeconds:         s16;
    mFrames:          s16;
}

AudioTimeStamp :: struct {
    mSampleTime:    float64;
    mHostTime:      u64;
    mRateScalar:    float64;
    mWordClockTime: u64;
    mSMPTETime:     SMPTETime;
    mFlags:         u32;
    mReserved:      u32;
}

AudioBuffer :: struct {
    mNumberChannels: u32;
    mDataByteSize:   u32;
    mData:           *void;
}

// Note: mBuffers is technically a variable length array in C. 
// For interleaved audio, you access index 0. 
// For non-interleaved, you must offset the pointer based on mNumberBuffers.
AudioBufferList :: struct {
    mNumberBuffers: u32;
    mBuffers:       [1] AudioBuffer; 
}

AURenderCallback :: #type (
    inRefCon:       *void, 
    ioActionFlags:  *AudioUnitRenderActionFlags, 
    inTimeStamp:    *AudioTimeStamp, 
    inBusNumber:    u32, 
    inNumberFrames: u32, 
    ioData:         *AudioBufferList
) -> OSStatus #c_call;

AURenderCallbackStruct :: struct {
    inputProc:       AURenderCallback;
    inputProcRefCon: *void;
}
#scope_file
#if OS == .MACOS {
    AudioToolbox   :: #library,system "AudioToolbox";
    CoreAudio      :: #library,system "CoreAudio";
    CoreFoundation :: #library,system "CoreFoundation";
}

#scope_export

AudioComponentFindNext        :: (inComponent: AudioComponent, inDesc: *AudioComponentDescription) -> AudioComponent #foreign AudioToolbox;
AudioComponentInstanceNew     :: (inComponent: AudioComponent, outInstance: *AudioComponentInstance) -> OSStatus #foreign AudioToolbox;
AudioComponentInstanceDispose :: (inInstance: AudioComponentInstance) -> OSStatus #foreign AudioToolbox;

AudioUnitInitialize           :: (inUnit: AudioUnit) -> OSStatus #foreign AudioToolbox;
AudioUnitUninitialize         :: (inUnit: AudioUnit) -> OSStatus #foreign AudioToolbox;
AudioUnitSetProperty          :: (inUnit: AudioUnit, inID: AudioUnitPropertyID, inScope: AudioUnitScope, inElement: AudioUnitElement, inData: *void, inDataSize: u32) -> OSStatus #foreign AudioToolbox;
AudioUnitGetProperty          :: (inUnit: AudioUnit, inID: AudioUnitPropertyID, inScope: AudioUnitScope, inElement: AudioUnitElement, outData: *void, ioDataSize: *u32) -> OSStatus #foreign AudioToolbox;

AudioOutputUnitStart          :: (inUnit: AudioUnit) -> OSStatus #foreign AudioToolbox;
AudioOutputUnitStop           :: (inUnit: AudioUnit) -> OSStatus #foreign AudioToolbox;
AudioChannelLayoutTag :: u32;

AudioChannelDescription :: struct {
    mChannelLabel: u32;
    mChannelFlags: u32;
    mCoordinates: [3] float32;
}

AudioChannelLayout :: struct {
    mChannelTag: AudioChannelLayoutTag;
    mChannelBitmap: u32;
    mNumberChannelDescriptions: u32;
    mChannelDescriptions: [1] AudioChannelDescription;
}

// HAL Functions (Hardware level)
AudioObjectGetPropertyData :: (
    inObjectID:          AudioObjectID,
    inAddress:           *AudioObjectPropertyAddress,
    inQualifierDataSize: u32,
    inQualifierData:     *void,
    ioDataSize:          *u32,
    outData:             *void
) -> OSStatus #foreign CoreAudio;

AudioObjectPropertyListenerProc :: #type (
    inObjectID: AudioObjectID, 
    inNumberAddresses: u32, 
    inAddresses: *AudioObjectPropertyAddress, 
    inClientData: *void
) -> OSStatus #c_call;

AudioObjectAddPropertyListener :: (
    inObjectID: AudioObjectID,
    inAddress: *AudioObjectPropertyAddress,
    inListener: AudioObjectPropertyListenerProc,
    inClientData: *void
) -> OSStatus #foreign CoreAudio;

fourcc :: (s: string) -> u32 {
    assert(s.count == 4);
    res: u32 = (cast(u32)s[0] << 24) |
               (cast(u32)s[1] << 16) |
               (cast(u32)s[2] << 8)  |
               (cast(u32)s[3]);
    return res;
}
