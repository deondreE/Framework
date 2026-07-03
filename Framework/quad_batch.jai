#import "Basic";
#import "Metal";

Quad_Vertex :: struct {
    position: [2] float32;
    uv: [2] float32;
    color: [4] float32;
}

Screen_Uniforms :: struct {
    screen_size: [2] float32;
}

quad_batch: [..] Quad_Vertex;

white_texture: *MTLTexture;

make_white_texture :: () -> *MTLTexture {
    using global_framework;

    desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        .MTLPixelFormatRGBA8Unorm, 1, 1, NO);
    desc.setUsage(desc, .MTLTextureUsageShaderRead);

    tex : *MTLTexture = xx (device.newTextureWithDescriptor(device, desc));

    pixel: [4] u8 = .[255, 255, 255, 255];
    region := MTLRegion.{ .{0,0,0}, .{1,1,1} };
    tex.replaceRegion_mipmapLevel_withBytes_bytesPerRow(tex, region, 0, pixel.data, 4);
    return tex;
}

QUAD_BUFFER_INITIAL_CAPACITY :: 4096;

ensure_quad_buffer_capacity :: (needed_verts: int) {
    using global_framework;

    if needed_verts <= quad_vertex_buffer_capacity return;

    new_capacity := max(needed_verts, quad_vertex_buffer_capacity * 2);
    if new_capacity < QUAD_BUFFER_INITIAL_CAPACITY new_capacity = QUAD_BUFFER_INITIAL_CAPACITY;

    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        quad_vertex_buffers[i] = device.newBufferWithLength_options(
            device, xx (size_of(Quad_Vertex) * new_capacity), xx 0);
    }

    quad_vertex_buffer_capacity = new_capacity;
}

draw_rect :: (x: float32, y: float32, w: float32, h: float32, color: [4] float32) {
    x0 := x;      y0 := y;
    x1 := x + w;  y1 := y + h;

    array_add(*quad_batch, Quad_Vertex.{ .[x0, y0], .[0, 0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x0, y1], .[0, 1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y1], .[1, 1], color });

    array_add(*quad_batch, Quad_Vertex.{ .[x0, y0], .[0, 0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y1], .[1, 1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y0], .[1, 0], color });
}