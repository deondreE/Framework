#import "Basic";
#import "Thread";
#import "Math";

Sound :: struct {
    samples: []float32;
    channels: int;
    sample_rate: int;
}

Voice :: struct {
    sound: *Sound;
    position: int;
    volume: float32 = 1.0;
    pan: float32 = 0.5; // 0.0 Left, 1.0 Right
    looping: bool = false;
    playing: bool = false;
}

MAX_VOICES :: 32;

#if OS == .MACOS {
    audio_render_callback :: (
        inRefCon: *void,
        ioActionFlag: *AudioUnitRenderActionFlags,
        inTimeStamp: *AudioTimeStamp,
        inBusNumber: u32,
        inNumberFrames: u32,
        ioData: *AudioBufferList,
    ) -> OSStatus #c_call {
        sys := cast(*Audio_System)inRefCon;

        // CoreAudio expects non-interleaved or interleaved based on flags.
        // We configured for interleaved Stereo (2 channels) below.
        out_buffer := cast(*float32) ioData.mBuffers[0].mData;

        // DEBUG: Clear the output buffer first
        memset(out_buffer, 0, inNumberFrames * 2 * size_of(float32));
        
        // TODO: this could be a new thread and stream the updates.
        lock(*sys.mutex);
        defer unlock(*sys.mutex);

        for * voice: sys.voices {
            if !voice.playing || !voice.sound continue;

            sound := voice.sound;

            for frame: 0..inNumberFrames-1 {
                if voice.position >= sound.samples.count {
                    if voice.looping {
                        voice.position = 0;
                    } else {
                        voice.position = false;
                        break;
                    }
                }

                // Simple Stero Mix
                // Assuming sound.channels is 1 (mono) or 2 (Stero)
                left_sample: float32 = 0;
                right_sample: float32 = 0;

                if sound.channels == 2 {
                    left_sample = sound.samples[voice.position] * voice.volume * sys.master_volume;
                    right_sample = sound.samples[voice.position + 1] * voice.volume * sys.master_volume;
                    voice.position += 2;
                } else {
                    s := sound.samples[voice.position] * voice.volume * sys.master_volume;
                    left_sample = s * (1.0 - voice.pan);
                    right_sample = s * voice.pan;
                    voice.position += 1;
                }

                out_buffer[frame * 2] += left_sample;
                out_buffer[frame * 2  + 1] += right_sample;
            }
        }

        return 0; // noErr
    }

Audio_System :: struct {
    uint: AudioUnit;
    voices: [MAX_VOICES] Voice;
    mutex: Mutex;
    master_volume: float32 = 1.0;
}

audio_init :: () -> *Audio_System {
    sys := New(Audio_System);
    init_mutex(*sys.mutex);

    desc: AudioComponentDescription;
    desc.componentType = kAudioType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioManufacturer_Apple;

    comp := AudioComponentFindNext(null, *desc);
    if !comp return null;

    status := AudioComponentInstanceNew(comp, *sys.unit);

    // Set up stream format
    stream_desc: AudioStreamBasicDescription;
    stream_desc.mSampleRate = 44100.0;
    stream_desc.mFormatID = kAudioFormatLinearPCM;
    stream_desc.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFlagIsPacked;
    stream_desc.mFramesPerPacket = 1;
    stream_desc.mChannelsPerFrame = 2;
    stream_desc.mBitsPerChannel = 32;
    stream_desc.mBytesPerFrame = 8; // 2 channels * 4
    stream_desc.mBytesPerPacket = 8;

    AudioUnitSetProperty(sys.unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, *stream_desc, size_of(AudioStreamBasicDescription));

    // Set the Render Callback
    callback_struct: AURenderCallbackStruct;
    callback_struct.inputProc = audio_render_callback;
    callback_struct.inputProcRefCon = sys;

    AudioUnitSetProperty(sys.unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, *callback_struct, size_of(AURenderCallbackStruct));

    AudioUnitInitialize(sys.unit);
    AudioOutputUnitStart(sys.unit);

    return sys;
}

audio_shutdown :: (sys: *Audio_System) {
    AudioOutputUnitStop(sys.unit);
    AudioUnitUninitialize(sys.unit);
    AudioComponentInstanceDispose(sys.unit);
    destroy_mutex(*sys.mutex);
    free(sys);
}

// @ DEBUG: These things depend on apple platforms.
load_sound_from_file :: (path: string) -> Sound, bool {
    sound: Sound;

    url := CFURLCreateFromFileSystemRepresentation(null, temp_c_string(path), path.count, false);
    if !url return .{}, false;
    defer CFRelease(url);

    ext_file: ExtAudioFileRef;
    status := ExtAudioFileOpenURL(url, *ext_file);
    if status != 0 return .{}, false;
    defer ExtAudioFileDispose(ext_file);

    file_format: AudioStreamBasicDescription;
    prop_size := cast(u32) size_of(AudoStreamBasicDescription);
    ExtAudioFileGetProperty(ext_file, kExtFileProperty_FileDataFormat, *prop_size, *file_format);

    client_format: AudioStreamBasicDescription;
    client_format.mSampleRate = file_format.mSampleRate;
    client_format.mFormatID = kAudioFormatLinearPCM;
    client_format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    client_format.mBitsPerChannel   = 32;
    client_format.mChannelPerFrame = file_format.mChannelPerFrame;
    client_format.mFramesPerPacket = 1;
    client_format.mBytesPerFrame = client_format.mChannelsPerFrame * 4;
    client_format.mBytesPerPacket = client_format.mBytesPerFrame;

    total_frames: s64;
    frames_prop_size := cast(u32) size_of(s64);
    ExtAudioFileSetProperty(ext_file, kExtFileProperty_FileLengthFrames, *frames_prop_size, *total_frames);

    total_samples := total_frames * client_format.mChannelsPerFrame;
    sound.samples = NewArray(total_samples, float32);
    sound.channels = cast(int) client_format.mChannelsPerFrame;
    sound.sample_rate = cast(int) client_format.mSampleRate;

    buffer_list: AudioBufferList;
    buffer_list.mNumberBuffers = 1;
    buffer_list.mBuffers[0].mNumberChannels = client_format.mChannelsPerFrame;
    buffer_list.mBuffers[0].mDataByteSize = cast(u32)(total_samples * size_of(float32));
    buffer_list.mBuffers[0].mData = sound.samples.data;

    frame_to_read := cast(u32) total_frame;
    status = ExtAudioFileRead(ext_file, *frame_to_read, *buffer_list);

    if status != 0 {
        free(sound.samples.data);
        return .{}, false;
    }
    
    return sound, true;
}

free_sound :: (sound: *Sound) {
    if sound.samples.data {
        free(sound.samples.data);
    }
    sound.samples.data = null;
    sound.samples.count = 0;
}

play_sound :: (sys: *Audio_System, sound: *Sound, volume: float32 = 1.0, looping: bool) -> *Voice {
    lock(*sys.mutex);
    defer unlock(*sys.mutex);

    for * voice: sys.voices {
        if !voice.playing {
            voice.sound = sound;
            voice.position = 0;
            voice.volume = volume;
            voice.looping = looping;
            voice.playing = true;
            return voice;
        }
    }
    return null;
 }

stop_voice :: (sys: *Audio_System, voice: *Voice) {
    lock(*sys.mutex);
    voice.playing = false;
    unlock(*sys.mutex);
}

set_volume :: (voice: *Voice, volume: float32) {
   voice.volume = volume; 
}

set_master_volume :: (sys: *Audio_System, volume: float32) {
    voice.master_volume = volume;
}

is_playing :: (voice: *Voice) -> bool {
    return voice.playing;
}

} // #if MACOS
