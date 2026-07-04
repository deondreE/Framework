#import "Basic";
#import "Thread";
#import "Math";

Load_Sound_Task :: struct {
    path: string;
    target_sound: *Sound;
    status_success: *bool;
    on_complete: () -> void = null;
}

load_sound_job_proc :: (group: *Job_Group, payload: *void) {
    task := cast(*Load_Sound_Task) payload;

    sound, success := load_sound_from_file(task.path);
    task.target_sound.* = sound;
    task.status_success.* = success;

    if task.on_complete task.on_complete();

    // NOTE: If task was allocated with New(), free it here or wait_for_group.
}

Sound :: struct {
    samples: []float32;
    channels: int;
    sample_rate: int;
    loaded: bool;
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
    ioActionFlag: *AudioUnitRenderActionFlags, // NOTE: CoreAudio usually names this ioActionFlags
    inTimeStamp: *AudioTimeStamp,
    inBusNumber: u32,
    inNumberFrames: u32,
    ioData: *AudioBufferList
) -> OSStatus #c_call {
    push_context {
        sys := cast(*Audio_System)inRefCon;

        out_buffer := cast(*float32) ioData.mBuffers[0].mData;

        memset(out_buffer, 0, inNumberFrames * 2 * size_of(float32));
        
        lock(*sys.mutex);
        defer unlock(*sys.mutex);

        for * voice: sys.voices {
            // Sound must be valid and finished loading
            if !voice.playing || !voice.sound || !voice.sound.loaded continue;

            sound := voice.sound;

            for frame: 0..inNumberFrames-1 {
                // Check if we hit the end of the sample buffer
                if voice.position >= sound.samples.count {
                    if voice.looping {
                        voice.position = 0;
                    } else {
                        voice.playing = false; // FIX: stop the voice
                        break;
                    }
                }

                left_sample: float32 = 0;
                right_sample: float32 = 0;

                // Simple Stereo Mix
                if sound.channels == 2 {
                    // Safety check to ensure we don't read out of bounds on a trailing single sample
                    if voice.position + 1 < sound.samples.count {
                        left_sample = sound.samples[voice.position] * voice.volume * sys.master_volume;
                        right_sample = sound.samples[voice.position + 1] * voice.volume * sys.master_volume;
                        voice.position += 2;
                    } else {
                        voice.playing = false;
                        break;
                    }
                } else {
                    // Mono source
                    s := sound.samples[voice.position] * voice.volume * sys.master_volume;
                    left_sample  = s * (1.0 - voice.pan);
                    right_sample = s * voice.pan;
                    voice.position += 1;
                }

                // Add to output buffer (accumulative mixing)
                out_buffer[frame * 2]     += left_sample;
                out_buffer[frame * 2 + 1] += right_sample;
            }
        }
    }

    return 0; // noErr
}

Audio_System :: struct {
    unit: AudioUnit;
    voices: [MAX_VOICES] Voice;
    mutex: Mutex;
    master_volume: float32 = 1.0;
}

audio_init :: () -> *Audio_System {
    sys := New(Audio_System);
    init(*sys.mutex);

    desc: AudioComponentDescription;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    comp := AudioComponentFindNext(null, *desc);
    if !comp return null;

    status := AudioComponentInstanceNew(comp, *sys.unit);

    // Set up stream format
    stream_desc: AudioStreamBasicDescription;
    stream_desc.mSampleRate = 44100.0;
    stream_desc.mFormatID = kAudioFormatLinearPCM;
    stream_desc.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
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
    if !sys return;
    
    AudioOutputUnitStop(sys.unit);
    AudioUnitUninitialize(sys.unit);
    AudioComponentInstanceDispose(sys.unit);

    lock(*sys.mutex);
    for * sys.voices it.playing = false;
    unlock(*sys.mutex);
    
    destroy(*sys.mutex);
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
    prop_size := cast(u32) size_of(AudioStreamBasicDescription);
    ExtAudioFileGetProperty(ext_file, kExtAudioFileProperty_FileDataFormat, *prop_size, *file_format);

    client_format: AudioStreamBasicDescription;
    client_format.mSampleRate = file_format.mSampleRate;
    client_format.mFormatID = kAudioFormatLinearPCM;
    client_format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    client_format.mBitsPerChannel   = 32;
    client_format.mChannelsPerFrame = file_format.mChannelsPerFrame;
    client_format.mFramesPerPacket = 1;
    client_format.mBytesPerFrame = client_format.mChannelsPerFrame * 4;
    client_format.mBytesPerPacket = client_format.mBytesPerFrame;

    total_frames: s64;
    frames_prop_size := cast(u32) size_of(s64);
    ExtAudioFileSetProperty(ext_file, kExtAudioFileProperty_FileLengthFrames, frames_prop_size, *total_frames);

    total_samples := total_frames * client_format.mChannelsPerFrame;
    sound.samples = NewArray(total_samples, float32);
    sound.channels = cast(int) client_format.mChannelsPerFrame;
    sound.sample_rate = cast(int) client_format.mSampleRate;

    buffer_list: AudioBufferList;
    buffer_list.mNumberBuffers = 1;
    buffer_list.mBuffers[0].mNumberChannels = client_format.mChannelsPerFrame;
    buffer_list.mBuffers[0].mDataByteSize = cast(u32)(total_samples * size_of(float32));
    buffer_list.mBuffers[0].mData = sound.samples.data;

    frame_to_read := cast(u32) total_frames;
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
