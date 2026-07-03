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
#load "quad_batch.jai";
#load "texture_loading.jai";

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

MAX_FRAMES_IN_FLIGHT :: 3;
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

    frame_index: int;
    text_vertex_buffers: [MAX_FRAMES_IN_FLIGHT] *MTLBuffer;
    text_vertex_buffer_capacity: int;

    quad_pipeline_state: *MTLRenderPipelineState;
    quad_vertex_buffers: [MAX_FRAMES_IN_FLIGHT] *MTLBuffer;
    quad_vertex_buffer_capacity: int;

    font: Font_Atlas;
    white_texture: *MTLTexture;

    text_batch: [..] Text_Vertex;
    FALLBACK_CHAR :: #char "?";

    quit := false;
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
    quad_vertex_fn := library.newFunctionWithName(library, ns_string("vertex_quad"));
    quad_fragment_fn := library.newFunctionWithName(library, ns_string("fragment_quad"));

    if !vertex_fn || !fragment_fn || !text_vertex_fn || !text_fragment_fn {
        print("Error: Could not create shader lib missing func.\n");
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

    //////////////////
    // User Interface pipeline state
    quad_pipeline_desc := objc_init(objc_alloc(MTLRenderPipelineDescriptor));
    quad_pipeline_desc.setVertexFunction(quad_pipeline_desc, quad_vertex_fn);
    quad_pipeline_desc.setFragmentFunction(quad_pipeline_desc, quad_fragment_fn);
    quad_pipeline_desc.setDepthAttachmentPixelFormat(quad_pipeline_desc, depth_pixel_format);

    quad_color0 := quad_pipeline_desc.colorAttachments(quad_pipeline_desc).objectAtIndexedSubscript(quad_pipeline_desc.colorAttachments(quad_pipeline_desc), 0);
    quad_color0.setPixelFormat(quad_color0, .MTLPixelFormatBGRA8Unorm);
    quad_color0.setBlendingEnabled(quad_color0, YES);
    quad_color0.setSourceRGBBlendFactor(quad_color0, .MTLBlendFactorSourceAlpha);
    quad_color0.setDestinationRGBBlendFactor(quad_color0, .MTLBlendFactorOneMinusSourceAlpha);
    quad_color0.setSourceAlphaBlendFactor(quad_color0, .MTLBlendFactorSourceAlpha);
    quad_color0.setDestinationAlphaBlendFactor(quad_color0, .MTLBlendFactorOneMinusSourceAlpha);

    quad_pipeline_error: *NSError;
    quad_pipeline_state = xx device.newRenderPipelineStateWithDescriptor_error(device, quad_pipeline_desc, *quad_pipeline_error);
    if !quad_pipeline_state {
        print("Error: could not create quad pipeline state: %\n", quad_pipeline_error);
        return false;
    }

    white_texture = make_white_texture();

    vertices := Vertex.[
        .{ .[0.0, 60.0, 0.0], .[1, 0, 0] },
        .{ .[-60.0, -60.0, 0.0], .[0, 1, 0] },
        .{ .[ 60.0, -60.0, 0.0], .[0, 0, 0] },
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

    array_add(*instances, InstanceData.{ .[-200.0,  150.0], 1.0, 0.0 });
    array_add(*instances, InstanceData.{ .[ 200.0,  150.0], -1.5, 0.0 });
    array_add(*instances, InstanceData.{ .[ 0.0, -150.0], 2.5, 0.0 });

    start_time = current_time_monotonic();

    return true;
}

flush_text_batch :: (encoder: *MTLRenderCommandEncoder) {
    using global_framework;

    if text_batch.count == 0 return;

    ensure_text_buffer_capacity(text_batch.count);
    current_buffer := text_vertex_buffers[frame_index % MAX_FRAMES_IN_FLIGHT];

    dst := current_buffer.contents(current_buffer);
    memcpy(dst, text_batch.data, size_of(Text_Vertex) * text_batch.count);

    encoder.setRenderPipelineState(encoder, xx text_pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx current_buffer, 0, 0);
    encoder.setFragmentTexture_atIndex(encoder, xx font.texture, 0);
    encoder.setFragmentSamplerState_atIndex(encoder, xx text_sampler_state, 0);
    encoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, 0, xx text_batch.count);
}

flush_quad_batch :: (encoder: *MTLRenderCommandEncoder) {
    using global_framework;

    if quad_batch.count == 0 return;

    ensure_quad_buffer_capacity(quad_batch.count);

    current_buffer := quad_vertex_buffers[frame_index % MAX_FRAMES_IN_FLIGHT];
    dst := current_buffer.contents(current_buffer);
    memcpy(dst, quad_batch.data, size_of(Quad_Vertex) * quad_batch.count);

    screen_uniforms: Screen_Uniforms;
    screen_uniforms.screen_size = .[cast(float32)window_width, cast(float32)window_height];

    encoder.setRenderPipelineState(encoder, xx quad_pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx current_buffer, 0, 0);
    encoder.setVertexBytes_length_atIndex(encoder, *screen_uniforms, size_of(Screen_Uniforms), 1);
    encoder.setFragmentSamplerState_atIndex(encoder, xx text_sampler_state, 0);

    for range : quad_draw_ranges {
        encoder.setFragmentTexture_atIndex(encoder, xx range.texture, 0);
        encoder.drawPrimitives_vertexStart_vertexCount(encoder, .MTLPrimitiveTypeTriangle, xx range.start, xx range.count);
    }
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

        depth_texture = create_depth_using_texture(window_width, window_height);
    }
}
