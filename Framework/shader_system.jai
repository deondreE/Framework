#import "Basic";
#import "Metal";
#import "File";
#import "POSIX";

Blend_Mode :: enum {
    None;           // no blending, opaque
    Alpha;          // standard src-alpha / one-minus-src-alpha
    Additive;       // src-alpha / one  (particles, glows)
    Premultiplied;  // one / one-minus-src-alpha
}

Render_Shader_Config :: struct {
    vertex_fn:   string     = "vertex_main";
    fragment_fn: string     = "fragment_main";
    blend_mode:  Blend_Mode = .Alpha;
    depth_test:  bool       = true;
    depth_write: bool       = true;
    pixel_format: MTLPixelFormat = .MTLPixelFormatBGRA8Unorm;
}

Render_Shader :: struct {
    pipeline_state: *MTLRenderPipelineState;
    source_path:    string;
    last_modified:  s64;  // unix seconds from stat st_mtime
    config:         Render_Shader_Config;
    valid:          bool;
}

Compute_Shader :: struct {
    pipeline_state: *MTLComputePipelineState;
    source_path:    string;
    last_modified:  s64;
    kernel_fn:      string;
    valid:          bool;
}

_render_shaders:  [..] *Render_Shader;
_compute_shaders: [..] *Compute_Shader;

_get_mtime :: (path: string) -> s64 {
    s: stat_t;
    c_path := temp_c_string(path);
    if stat(c_path, *s) != 0  return 0;
    return s.st_mtime.tv_sec;
}

_compile_library :: (source_path: string) -> *MTLLibrary {
    using global_framework;

    src, ok := read_entire_file(source_path);
    defer if ok then free(src);
    if !ok {
        print("Shader: could not read '%'\n", source_path);
        return null;
    }

    error: *NSError;
    lib := device.newLibraryWithSource_options_error(device, ns_string(src), null, *error);
    if !lib  print("Shader compile error ('%'):\n%\n", source_path, error);
    return lib;
}

_apply_blend_mode :: (att: *MTLRenderPipelineColorAttachmentDescriptor, mode: Blend_Mode) {
    if mode == .None {
        att.setBlendingEnabled(att, NO);
        return;
    }
    att.setBlendingEnabled(att, YES);
    if #complete mode == {
        case .Alpha;
            att.setSourceRGBBlendFactor(att,      .MTLBlendFactorSourceAlpha);
            att.setDestinationRGBBlendFactor(att, .MTLBlendFactorOneMinusSourceAlpha);
            att.setSourceAlphaBlendFactor(att,    .MTLBlendFactorSourceAlpha);
            att.setDestinationAlphaBlendFactor(att,.MTLBlendFactorOneMinusSourceAlpha);
        case .Additive;
            att.setSourceRGBBlendFactor(att,      .MTLBlendFactorSourceAlpha);
            att.setDestinationRGBBlendFactor(att, .MTLBlendFactorOne);
            att.setSourceAlphaBlendFactor(att,    .MTLBlendFactorSourceAlpha);
            att.setDestinationAlphaBlendFactor(att,.MTLBlendFactorOne);
        case .Premultiplied;
            att.setSourceRGBBlendFactor(att,      .MTLBlendFactorOne);
            att.setDestinationRGBBlendFactor(att, .MTLBlendFactorOneMinusSourceAlpha);
            att.setSourceAlphaBlendFactor(att,    .MTLBlendFactorOne);
            att.setDestinationAlphaBlendFactor(att,.MTLBlendFactorOneMinusSourceAlpha);
        case .None; // handled above
    }
}

_build_render_pipeline :: (lib: *MTLLibrary, config: Render_Shader_Config) -> *MTLRenderPipelineState {
    using global_framework;

    vfn := lib.newFunctionWithName(lib, ns_string(config.vertex_fn));
    ffn := lib.newFunctionWithName(lib, ns_string(config.fragment_fn));
    if !vfn || !ffn {
        print("Shader: missing function '%' or '%'\n", config.vertex_fn, config.fragment_fn);
        return null;
    }

    desc := objc_init(objc_alloc(MTLRenderPipelineDescriptor));
    desc.setVertexFunction(desc, vfn);
    desc.setFragmentFunction(desc, ffn);

    if config.depth_test {
        desc.setDepthAttachmentPixelFormat(desc, depth_pixel_format);
    }

    color_attachments := desc.colorAttachments(desc);
    color0 := color_attachments.objectAtIndexedSubscript(color_attachments, 0);
    color0.setPixelFormat(color0, config.pixel_format);
    _apply_blend_mode(color0, config.blend_mode);

    err: *NSError;
    ps := device.newRenderPipelineStateWithDescriptor_error(device, desc, *err);
    if !ps  print("Shader: pipeline link error: %\n", err);
    return ps;
}

// ------------------------------------------------------------------
//  Public API – render shaders
// ------------------------------------------------------------------

// Load and compile a render shader from a .metal source file.
// Returns a stable pointer you can cache.  If compilation fails the
// shader is still registered (for hot-reload) but .valid == false.
//
//   config := Render_Shader_Config.{ vertex_fn = "my_vert", fragment_fn = "my_frag" };
//   my_shader := create_render_shader(get_shader_path("my.metal"), config);
//
create_render_shader :: (source_path: string, config: Render_Shader_Config = .{}) -> *Render_Shader {
    shader := New(Render_Shader);
    shader.source_path = copy_string(source_path);
    shader.config      = config;

    lib := _compile_library(source_path);
    if lib {
        shader.pipeline_state = _build_render_pipeline(lib, config);
        shader.valid = shader.pipeline_state != null;
    }

    shader.last_modified = _get_mtime(source_path);

    array_add(*_render_shaders, shader);
    return shader;
}

// Bind a render shader inside an active MTLRenderCommandEncoder.
// Call this just before issuing draw calls that should use the shader.
use_render_shader :: (encoder: *MTLRenderCommandEncoder, shader: *Render_Shader) {
    if !shader || !shader.valid return;
    encoder.setRenderPipelineState(encoder, shader.pipeline_state);
}

// ------------------------------------------------------------------
//  Public API – compute shaders
// ------------------------------------------------------------------

// Load and compile a Metal compute kernel from source.
//
//   cs := create_compute_shader(get_shader_path("particles.metal"), "update_particles");
//
create_compute_shader :: (source_path: string, kernel_fn: string) -> *Compute_Shader {
    using global_framework;

    shader := New(Compute_Shader);
    shader.source_path = copy_string(source_path);
    shader.kernel_fn   = copy_string(kernel_fn);

    lib := _compile_library(source_path);
    if lib {
        fn := lib.newFunctionWithName(lib, ns_string(kernel_fn));
        if fn {
            err: *NSError;
            shader.pipeline_state = device.newComputePipelineStateWithFunction_error(device, fn, *err);
            shader.valid = shader.pipeline_state != null;
            if !shader.valid  print("Compute shader pipeline error: %\n", err);
        } else {
            print("Compute shader: missing kernel '%'\n", kernel_fn);
        }
    }

    shader.last_modified = _get_mtime(source_path);

    array_add(*_compute_shaders, shader);
    return shader;
}

// Convenience: encode a 1-D compute dispatch (e.g. over N particles).
// Creates and commits its own command buffer.  If you need to interleave
// with other work, manage your own MTLComputeCommandEncoder instead.
dispatch_compute_1d :: (shader: *Compute_Shader, thread_count: int,
                        threads_per_group: int = 64) {
    if !shader || !shader.valid return;
    using global_framework;

    cb := command_queue.commandBuffer(command_queue);
    enc := cb.computeCommandEncoder(cb);

    enc.setComputePipelineState(enc, xx shader.pipeline_state);

    tpg  := min(threads_per_group, thread_count);
    groups := (thread_count + tpg - 1) / tpg;
    enc.dispatchThreadgroups_threadsPerThreadgroup(
        enc,
        MTLSize.{xx groups, 1, 1},
        MTLSize.{xx tpg, 1, 1}
    );

    (cast(*MTLCommandEncoder) enc).endEncoding(cast(*MTLCommandEncoder) enc);
    cb.commit(cb);
}

// Encode a compute dispatch into a caller-owned MTLComputeCommandEncoder.
// Use this when batching multiple compute passes in one command buffer.
//
//   enc := cb.computeCommandEncoder(cb);
//   enc.setBuffer_offset_atIndex(enc, my_buf, 0, 0);
//   dispatch_compute(enc, cs, 1024);
//   enc.endEncoding(enc);
//
dispatch_compute :: (enc: *MTLComputeCommandEncoder, shader: *Compute_Shader,
                     thread_count_x: int, thread_count_y: int = 1, thread_count_z: int = 1,
                     threads_per_group_x: int = 64, threads_per_group_y: int = 1,
                     threads_per_group_z: int = 1) {
    if !shader || !shader.valid return;

    enc.setComputePipelineState(enc, xx shader.pipeline_state);

    tpg_x := min(threads_per_group_x, thread_count_x);
    gx    := (thread_count_x + tpg_x - 1) / tpg_x;
    gy    := thread_count_y;
    gz    := thread_count_z;

    enc.dispatchThreadgroups_threadsPerThreadgroup(
        enc,
        MTLSize.{xx gx, xx gy, xx gz},
        MTLSize.{xx tpg_x, xx threads_per_group_y, xx threads_per_group_z}
    );
}

// ------------------------------------------------------------------
//  Hot reload  – call once per frame from update_framework
// ------------------------------------------------------------------

// Returns true if any shader was successfully reloaded.
check_shader_hot_reload :: () -> bool {
    using global_framework;

    any_reloaded := false;

    for shader : _render_shaders {
        modtime := _get_mtime(shader.source_path);
        if modtime <= shader.last_modified  continue;

        print("[hot-reload] render shader '%'...\n", shader.source_path);
        lib := _compile_library(shader.source_path);
        if !lib continue;

        new_ps := _build_render_pipeline(lib, shader.config);
        if new_ps {
            shader.pipeline_state = new_ps;
            shader.valid          = true;
            shader.last_modified  = modtime;
            any_reloaded = true;
            print("  -> OK\n");
        }
    }

    for shader : _compute_shaders {
        modtime := _get_mtime(shader.source_path);
        if modtime <= shader.last_modified  continue;

        print("[hot-reload] compute shader '%' (kernel: %)...\n",
              shader.source_path, shader.kernel_fn);
        lib := _compile_library(shader.source_path);
        if !lib continue;

        fn := lib.newFunctionWithName(lib, ns_string(shader.kernel_fn));
        if !fn { print("  -> missing kernel after reload\n"); continue; }

        err: *NSError;
        new_ps := device.newComputePipelineStateWithFunction_error(device, fn, *err);
        if new_ps {
            shader.pipeline_state = new_ps;
            shader.valid          = true;
            shader.last_modified  = modtime;
            any_reloaded = true;
            print("  -> OK\n");
        } else {
            print("  -> pipeline error: %\n", err);
        }
    }

    return any_reloaded;
}
