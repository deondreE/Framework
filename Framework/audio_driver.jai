#import "Basic";
#import "Thread";
#import "Math";
#import "File";
#import "String";

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

    // @TODO: If task was allocated with New(), free it here or wait_for_group.
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
    pan: float32 = 0.5;
    looping: bool = false;
    playing: bool = false;
}

MAX_VOICES :: 32;

#if OS == .MACOS {
    AUDIO_QUEUE_BUFFER_COUNT     :: 3;
    AUDIO_QUEUE_FRAMES_PER_BUFFER :: 2048;

    Audio_System :: struct {
        queue:   AudioQueueRef;
        buffers: [AUDIO_QUEUE_BUFFER_COUNT] AudioQueueBufferRef;
        voices:  [MAX_VOICES] Voice;
        mutex:   Mutex;
        master_volume: float32 = 1.0;
    }

    // Called by the Audio Queue on its own internal thread whenever it needs
    // more data.  Fill the buffer, set mAudioDataByteSize, re-enqueue.
    audio_queue_callback :: (user_data: *void, queue: AudioQueueRef, buffer: AudioQueueBufferRef) -> void #c_call {
        push_context {
            sys    := cast(*Audio_System) user_data;
            frames := AUDIO_QUEUE_FRAMES_PER_BUFFER;
            out    := cast(*float32) buffer.mAudioData;

            memset(out, 0, frames * 2 * size_of(float32));

            lock(*sys.mutex);
            defer unlock(*sys.mutex);

            for * voice: sys.voices {
                if !voice.playing || !voice.sound || !voice.sound.loaded continue;

                sound := voice.sound;

                for frame: 0..frames-1 {
                    if voice.position >= sound.samples.count {
                        if voice.looping {
                            voice.position = 0;
                        } else {
                            voice.playing = false;
                            break;
                        }
                    }

                    left_sample:  float32 = 0;
                    right_sample: float32 = 0;

                    if sound.channels == 2 {
                        if voice.position + 1 < sound.samples.count {
                            left_sample  = sound.samples[voice.position]     * voice.volume * sys.master_volume;
                            right_sample = sound.samples[voice.position + 1] * voice.volume * sys.master_volume;
                            voice.position += 2;
                        } else {
                            voice.playing = false;
                            break;
                        }
                    } else {
                        s := sound.samples[voice.position] * voice.volume * sys.master_volume;
                        left_sample  = s * (1.0 - voice.pan);
                        right_sample = s * voice.pan;
                        voice.position += 1;
                    }

                    out[frame * 2]     += left_sample;
                    out[frame * 2 + 1] += right_sample;
                }
            }

            buffer.mAudioDataByteSize = cast(u32)(frames * 2 * size_of(float32));
            AudioQueueEnqueueBuffer(queue, buffer, 0, null);
        }
    }

    audio_init :: () -> *Audio_System {
        sys := New(Audio_System);
        init(*sys.mutex);

        format: AudioStreamBasicDescription;
        format.mSampleRate       = 44100.0;
        format.mFormatID         = kAudioFormatLinearPCM;
        format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        format.mBitsPerChannel   = 32;
        format.mChannelsPerFrame = 2;
        format.mFramesPerPacket  = 1;
        format.mBytesPerFrame    = 8;
        format.mBytesPerPacket   = 8;

        // AudioQueueNewOutput does NOT need AudioComponentFindNext — it goes
        // directly to the default output device and works in any process.
        // Passing null for the run loop lets the queue create its own thread.
        status := AudioQueueNewOutput(*format, audio_queue_callback, sys, null, null, 0, *sys.queue);
        if status != 0 || !sys.queue {
            print("audio_init: AudioQueueNewOutput failed, status = %\n", status);
            destroy(*sys.mutex);
            free(sys);
            return null;
        }

        buffer_byte_size: u32 = AUDIO_QUEUE_FRAMES_PER_BUFFER * 2 * size_of(float32);
        for i: 0..AUDIO_QUEUE_BUFFER_COUNT-1 {
            status = AudioQueueAllocateBuffer(sys.queue, buffer_byte_size, *sys.buffers[i]);
            if status != 0 {
                print("audio_init: AudioQueueAllocateBuffer[%] failed, status = %\n", i, status);
                AudioQueueDispose(sys.queue, true);
                destroy(*sys.mutex);
                free(sys);
                return null;
            }
            // Pre-fill with silence and enqueue so the queue has data immediately.
            buf := sys.buffers[i];
            memset(buf.mAudioData, 0, buffer_byte_size);
            buf.mAudioDataByteSize = buffer_byte_size;
            AudioQueueEnqueueBuffer(sys.queue, sys.buffers[i], 0, null);
        }

        status = AudioQueueStart(sys.queue, null);
        if status != 0 {
            print("audio_init: AudioQueueStart failed, status = %\n", status);
            AudioQueueDispose(sys.queue, true);
            destroy(*sys.mutex);
            free(sys);
            return null;
        }

        return sys;
    }

    audio_shutdown :: (sys: *Audio_System) {
        if !sys return;
        if sys.queue {
            AudioQueueStop(sys.queue, true);
            AudioQueueDispose(sys.queue, true);
        }
        lock(*sys.mutex);
        for * sys.voices it.playing = false;
        unlock(*sys.mutex);
        destroy(*sys.mutex);
        free(sys);
    }

    // @INFO: Apple-platform-only sound loading via ExtAudioFile / CFURL.
    load_sound_from_file :: (path_l: string) -> Sound, bool {
        TARGET_SAMPLE_RATE :: 44100.0;
        TARGET_CHANNELS    :: 2;

        sound: Sound;

        cwd := get_working_directory();
        full_path := join(cwd, "/", path_l,, temp);

        url := CFURLCreateFromFileSystemRepresentation(null, temp_c_string(full_path), full_path.count, false);
        if !url {
            print("load_sound_from_file: could not create CFURL for '%'\n", full_path);
            return .{}, false;
        }
        defer CFRelease(url);

        ext_file: ExtAudioFileRef;
        status := ExtAudioFileOpenURL(url, *ext_file);
        if status != 0 || !ext_file {
            print("ExtAudioFileOpenURL failed (%) for '%'\n", status, full_path);
            return .{}, false;
        }
        defer ExtAudioFileDispose(ext_file);

        // 1. Query the file's native format first so we can compute the correct output
        //    frame count after sample-rate conversion.
        file_format: AudioStreamBasicDescription;
        file_format_size := cast(u32) size_of(AudioStreamBasicDescription);
        status = ExtAudioFileGetProperty(ext_file, kExtAudioFileProperty_FileDataFormat, *file_format_size, *file_format);
        if status != 0 {
            print("ExtAudioFileGetProperty(FileDataFormat) failed: %\n", status);
            return .{}, false;
        }

        // 2. Get the file's frame count AT ITS OWN sample rate.
        file_frames: s64;
        frames_prop_size := cast(u32) size_of(s64);
        status = ExtAudioFileGetProperty(ext_file, kExtAudioFileProperty_FileLengthFrames, *frames_prop_size, *file_frames);
        if status != 0 {
            print("ExtAudioFileGetProperty(FileLengthFrames) failed: %\n", status);
            return .{}, false;
        }

        // 3. Compute how many output frames we need at TARGET_SAMPLE_RATE.
        //    The file may be at a different rate (e.g. 22050, 48000), so we cannot
        //    use file_frames directly — that would allocate the wrong buffer size.
        src_rate := file_format.mSampleRate;
        if src_rate <= 0 src_rate = TARGET_SAMPLE_RATE;
        duration_seconds  := cast(float64) file_frames / src_rate;
        output_frames     := cast(s64) (duration_seconds * TARGET_SAMPLE_RATE + 1.5); // +1.5 rounds up
        total_samples     := output_frames * TARGET_CHANNELS;

        // 4. Set the client format (what ExtAudioFile must deliver to us).
        //    This MUST happen after querying FileDataFormat so the internal
        //    AudioConverter is constructed with the correct source info.
        client_format: AudioStreamBasicDescription;
        client_format.mSampleRate       = TARGET_SAMPLE_RATE;
        client_format.mFormatID         = kAudioFormatLinearPCM;
        client_format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        client_format.mBitsPerChannel   = 32;
        client_format.mChannelsPerFrame = TARGET_CHANNELS;
        client_format.mFramesPerPacket  = 1;
        client_format.mBytesPerFrame    = TARGET_CHANNELS * 4;
        client_format.mBytesPerPacket   = TARGET_CHANNELS * 4;

        status = ExtAudioFileSetProperty(ext_file, kExtAudioFileProperty_ClientDataFormat,
                                         cast(u32) size_of(AudioStreamBasicDescription), *client_format);
        if status != 0 {
            print("ExtAudioFileSetProperty(ClientDataFormat) failed: % (file format: id=%, rate=%, ch=%)\n",
                  status, file_format.mFormatID, file_format.mSampleRate, file_format.mChannelsPerFrame);
            return .{}, false;
        }

        // 5. Allocate the output buffer and read.
        sound.samples     = NewArray(cast(int) total_samples, float32);
        sound.channels    = TARGET_CHANNELS;
        sound.sample_rate = cast(int) TARGET_SAMPLE_RATE;

        buffer_list: AudioBufferList;
        buffer_list.mNumberBuffers              = 1;
        buffer_list.mBuffers[0].mNumberChannels = TARGET_CHANNELS;
        buffer_list.mBuffers[0].mDataByteSize   = cast(u32) (total_samples * size_of(float32));
        buffer_list.mBuffers[0].mData           = sound.samples.data;

        frames_to_read := cast(u32) output_frames;
        status = ExtAudioFileRead(ext_file, *frames_to_read, *buffer_list);
        if status != 0 {
            print("ExtAudioFileRead failed: %\n", status);
            free_sound(*sound);
            return .{}, false;
        }

        // Trim to what was actually decoded (compressed formats may give fewer frames).
        sound.samples.count = cast(int) frames_to_read * TARGET_CHANNELS;
        sound.loaded = true;
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

        // @TODO: no free voice found; consider voice-stealing the oldest/quietest voice instead of failing.
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
        sys.master_volume = volume;
    }

    is_playing :: (voice: *Voice) -> bool {
        return voice.playing;
    }

} // #if MACOS
