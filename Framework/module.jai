#import "Basic";
#import "Window_Creation";
#import "Input";
#import "Metal";
#import "Objective_C";
#import "Objective_C/AppKit";
#import "macOS";
#import "System";
#import "String";
#import "File";

#load "metal_helpers.jai";
#load "font_atlas.jai";
#load "text.jai";

Uniforms :: struct {
    time: float32;
}

Vertex :: struct {
    position: [3] float32;
    color: [3] float32;
}

InstanceData :: struct {
    offset: [2] float32;
    rotation_speed: float32;
    _pad: float32;
}


Framework :: struct {
    window: *NSWindow;
    window_width : s32 = 1280;
    window_height : s32 = 720;

    device: *MTLDevice;
    command_queue: *MTLCommandQueue;
    metal_layer: *CAMetalLayer;

    pipeline_state: *MTLRenderPipelineState;
    vertex_buffer: *MTLBuffer;

    start_time: Apollo_Time;
    instances: [..] InstanceData;

    depth_texture: *MTLTexture;
    depth_stencil_state: *MTLDepthStencilState;
    depth_pixel_format := MTLPixelFormat.MTLPixelFormatDepth32Float;

    text_pipeline_state: *MTLRenderPipelineState;
    text_sampler_state: *MTLSamplerState;
    text_vertex_buffer: *MTLBuffer;
    text_vertex_buffer_capacity: int;
    font: Font_Atlas;

    text_batch: [..] Text_Vertex;
    FALLBACK_CHAR :: #char "?";

    quit := false;
}

TEXT_BUFFER_INITIAL_CAPACITY :: 4096; // vertices; grows as needed

ensure_text_buffer_capacity :: (needed_verts: int) {
    using global_framework;

    if needed_verts <= text_vertex_buffer_capacity return;

    new_capacity := max(needed_verts, text_vertex_buffer_capacity * 2);
    if new_capacity < TEXT_BUFFER_INITIAL_CAPACITY new_capacity = TEXT_BUFFER_INITIAL_CAPACITY;

    text_vertex_buffer = device.newBufferWithLength_options(
        device, xx (size_of(Text_Vertex) * new_capacity), xx 0); // 0 = MTLResourceStorageModeShared on Apple Silicon (default)

    text_vertex_buffer_capacity = new_capacity;
}

global_framework: Framework;

create_depth_using_texture :: (width: s32, height: s32) -> *MTLTexture {
    using global_framework; 

    desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        depth_pixel_format, xx width, xx height, NO);

    desc.setUsage(desc, .MTLTextureUsageRenderTarget);
    desc.setStorageMode(desc, .MTLStorageModePrivate);

    return xx device.newTextureWithDescriptor(device, desc);
}

get_sahder_path :: (filename: string) -> string {
    exe_path := get_path_of_running_executable();

    slash_index := find_index_from_right(exe_path, #char "/");
    dir: string;
    if slash_index == -1 {
        dir = ".";
    } else {
        dir = slice(exe_path, 0, slash_index);
    }

    return sprint("%/%", dir, filename);
}

init_framework :: () -> bool {
    using global_framework;

    init_objective_c();
    init_metal();

    window = create_window(window_width, window_height, "Jai Metal Framework");
    if !window return false;

    device = xx MTLCreateSystemDefaultDevice();
    if !device {
        print("Error: Metal not supported.\n");
        return false;
    }

    shader_path := get_sahder_path("default.metal");
    defer free(shader_path);

    shader_source, ok := read_entire_file(shader_path);
    defer if ok then free(shader_source);

    if !ok {
        print("Error: could not read shader source '%'.\n", shader_path);
        return false;
    }

    ns_source := NSString.initWithString(objc_alloc(NSString), shader_source);

    error: *NSError;
    library := device.newLibraryWithSource_options_error(device, ns_source, null, *error);
    if !library {
        print("Shader compile error: %\n", error);
        return false;
    }

    vertex_name := NSString.initWithString(objc_alloc(NSString), "vertex_main");
    fragment_name := NSString.initWithString(objc_alloc(NSString), "fragment_main"); 

    vertex_fn := library.newFunctionWithName(library, vertex_name);
    fragment_fn := library.newFunctionWithName(library, fragment_name);
    text_vertex_fn := library.newFunctionWithName(library, ns_string("vertex_text"));
    text_fragment_fn := library.newFunctionWithName(library, ns_string("fragment_text"));

    if !vertex_fn || !fragment_fn {
        print("Error: Could not fund vertex_main/fragment_main in shader library.\n");
        return false;
    }

    //////////////////
    // Default pipeline state

    pipeline_desc := objc_init(objc_alloc(MTLRenderPipelineDescriptor));
    pipeline_desc.setVertexFunction(pipeline_desc, vertex_fn);
    pipeline_desc.setFragmentFunction(pipeline_desc, fragment_fn);

    pipeline_desc.setDepthAttachmentPixelFormat(pipeline_desc, depth_pixel_format);

    pd_color_attachment := pipeline_desc.colorAttachments(pipeline_desc);
    pd_color0 := pd_color_attachment.objectAtIndexedSubscript(pd_color_attachment, 0);
    pd_color0.setPixelFormat(pd_color0, .MTLPixelFormatBGRA8Unorm);

    pipeline_error: *NSError;
    pipeline_state = device.newRenderPipelineStateWithDescriptor_error(device, pipeline_desc, *pipeline_error);
    if !pipeline_state {
        print("Error: could not create render pipeline state: %\n", pipeline_error);
        return false;
    }

    ds_desc := objc_init(objc_alloc(MTLDepthStencilDescriptor));
    ds_desc.setDepthCompareFunction(ds_desc, .MTLCompareFunctionLess);
    ds_desc.setDepthWriteEnabled(ds_desc, YES);
    depth_stencil_state = xx device.newDepthStencilStateWithDescriptor(device, ds_desc);

    depth_texture = create_depth_using_texture(window_width, window_height);

    //////////////////
    // Text pipeline state
    text_pipeline_desc := objc_init(objc_alloc(MTLRenderPipelineDescriptor));
    text_pipeline_desc.setVertexFunction(text_pipeline_desc, text_vertex_fn);
    text_pipeline_desc.setFragmentFunction(text_pipeline_desc, text_fragment_fn);
    text_pipeline_desc.setDepthAttachmentPixelFormat(text_pipeline_desc, depth_pixel_format);

    text_color0 := text_pipeline_desc.colorAttachments(text_pipeline_desc).objectAtIndexedSubscript(text_pipeline_desc.colorAttachments(text_pipeline_desc), 0);
    text_color0.setPixelFormat(text_color0, .MTLPixelFormatBGRA8Unorm);
    text_color0.setBlendingEnabled(text_color0, YES);
    text_color0.setSourceRGBBlendFactor(text_color0, .MTLBlendFactorSourceAlpha);
    text_color0.setDestinationRGBBlendFactor(text_color0, .MTLBlendFactorOneMinusSourceAlpha);
    text_color0.setSourceAlphaBlendFactor(text_color0, .MTLBlendFactorSourceAlpha);
    text_color0.setDestinationAlphaBlendFactor(text_color0, .MTLBlendFactorOneMinusSourceAlpha);

    text_pipeline_error: *NSError;
    text_pipeline_state = xx device.newRenderPipelineStateWithDescriptor_error(device, text_pipeline_desc, *text_pipeline_error);
    if !text_pipeline_state {
        print("Error: coild not create text pipeline state: %\n", text_pipeline_state);
        return false;
    }

    sampler_desc := objc_init(objc_alloc(MTLSamplerDescriptor));
    sampler_desc.setMinFilter(sampler_desc, .MTLSamplerMinMagFilterLinear);
    sampler_desc.setMagFilter(sampler_desc, .MTLSamplerMinMagFilterLinear);
    text_sampler_state = xx device.newSamplerStateWithDescriptor(device, sampler_desc);

    font_ok: bool;
    font, font_ok = load_font_atlas("/System/Library/Fonts/SFNS.ttf", 48);
    if !font_ok {
        print("Error: coild not load font atlas.\n");
        return false;
    }

    vertices := Vertex.[
        .{ .[0.0, 0.5, 0.0], .[1, 0, 0] },
        .{ .[-0.5, -0.5, 0.0], .[0, 1, 0] },
        .{ .[ 0.5, -0.5, 0.0], .[0, 0, 0] },
    ];

    vertex_buffer = device.newBufferWithBytes_length_options(
        device, vertices.data, size_of(Vertex) * vertices.count, xx 0);
    
    command_queue = MTLDevice.newCommandQueue(device);
    if !command_queue {
        print("Error: Could not create Metal command queue.\n");
        return false;
    }

    view := NSWindow.contentView(window);

    metal_layer = objc_init(objc_alloc(CAMetalLayer));
    CAMetalLayer.setDevice(metal_layer, device);
    CAMetalLayer.setPixelFormat(metal_layer, .MTLPixelFormatBGRA8Unorm);

    NSView.setWantsLayer(view, YES);

    // Attach the CAMetalLayer to the view
    set_layer: (*void, Selector, *CAMetalLayer) -> void #c_call;
    set_layer = xx objc_msgSend;
    set_layer(view, sel_registerName("setLayer:"), metal_layer);

    array_add(*instances, InstanceData.{ .[-0.6,  0.4], 1.0, 0.0 });
    array_add(*instances, InstanceData.{ .[ 0.6,  0.4], -1.5, 0.0 });
    array_add(*instances, InstanceData.{ .[ 0.0, -0.5], 2.5, 0.0 });
    
    start_time = current_time_monotonic();

    return true;
}

glyph_for_codepoint :: (cp: u32) -> Glyph {
    using global_framework;
    if cp >= 32 && cp <= 126 return font.glyphs[cp];
    return font.glyphs[FALLBACK_CHAR];
}

measure_width :: (text: string, start: int, end: int, scale: float32) -> float32 {
    width: float32 = 0;
    i := start;
    while i < end {
        cp := decode_utf8(text, *i);
        g := glyph_for_codepoint(cp);
        width += g.advance * scale;
    }
    return width;
}

draw_text :: (text: string, x: float32, y: float32, screen_w: float32, screen_h: float32, scale: float32 = 1.0, max_width: float32 = -1.0) {
    using global_framework;

    line_height := font.line_height * scale;

    cursor_x := x;
    cursor_y := y;

    i := 0;
    while i < text.count {
        if text[i] == #char "\n" {
            cursor_x = x;
            cursor_y += line_height;
            i += 1;
            continue;
        }

        if text[i] == #char " " {
            g := glyph_for_codepoint(#char " ");
            cursor_x += g.advance * scale;
            i += 1;
            continue;
        }

        // Find the extent of the next word (up to next space/newline).
        word_start := i;
        j := i;
        while j < text.count && text[j] != #char " " && text[j] != #char "\n" {
            j += 1;
        }

        if max_width > 0 {
            word_width := measure_width(text, word_start, j, scale);
            if cursor_x + word_width > x + max_width && cursor_x > x {
                cursor_x = x;
                cursor_y += line_height;
            }
        }

        // Render the word, glyph by glyph, decoding UTF-8 as we go.
        k := word_start;
        while k < j {
            cp := decode_utf8(text, *k);
            g := glyph_for_codepoint(cp);
            append_glyph_quad(*text_batch, g, cursor_x, cursor_y, scale, screen_w, screen_h);
            cursor_x += g.advance * scale;
        }

        i = j;
    }
}

flush_text_batch :: (encoder: *MTLRenderCommandEncoder) {
    using global_framework;

    if text_batch.count == 0 return;

    ensure_text_buffer_capacity(text_batch.count);
    dst := text_vertex_buffer.contents(text_vertex_buffer);
    memcpy(dst, text_batch.data, size_of(Text_Vertex) * text_batch.count);

    encoder.setRenderPipelineState(encoder, xx text_pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx text_vertex_buffer, 0, 0);
    encoder.setFragmentTexture_atIndex(encoder, xx font.texture, 0);
    encoder.setFragmentSamplerState_atIndex(encoder, xx text_sampler_state, 0);
    encoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, xx text_batch.count);
}

update_framework :: () {
    using global_framework;

    update_window_events();

    for event : events_this_frame {
        if event.type == .QUIT quit = true;
        if event.type == .KEYBOARD {
            if event.key_code == .ESCAPE && event.key_pressed quit = true;
        }
    }

    resizes := get_window_resizes();
    for resize : resizes {
        if resize.window != window continue; // ignore other windows, if any exist

        window_width  = resize.width;
        window_height = resize.height;

        CAMetalLayer.setDrawableSize(metal_layer, CGSize.{xx window_width, xx window_height});

        // release_object(depth_texture);
        depth_texture = create_depth_using_texture(window_width, window_height);
    }
}
