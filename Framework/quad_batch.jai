#import "Basic";
#import "Metal";
#import "Math";

Quad_Vertex :: struct {
    position: [2] float32;
    uv: [2] float32;
    color: [4] float32;
}

Screen_Uniforms :: struct {
    screen_size: [2] float32;
}

Quad_Draw_Range :: struct {
    texture: *MTLTexture;
    start: int;
    count: int;
}

Vector2 :: struct {
    x,y: float32;
}

quad_batch: [..] Quad_Vertex;
quad_draw_ranges: [..] Quad_Draw_Range;

make_white_texture :: () -> *MTLTexture {
    using global_framework;
    desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        .MTLPixelFormatRGBA8Unorm, 1, 1, xx 0);
    desc.setUsage(desc, .MTLTextureUsageShaderRead);

    tex : *MTLTexture = xx (device.newTextureWithDescriptor(device, desc));

    pixel: [4] u8 = .[255, 255, 255, 255];
    region := MTLRegion.{ .{0,0,0}, .{1,1,1} };
    tex.replaceRegion_mipmapLevel_withBytes_bytesPerRow(tex, region, 0, pixel.data, 4);
    return tex;
}

push_quad_range :: (texture: *MTLTexture, vert_count: int) {
    if quad_draw_ranges.count > 0 {
        last := *quad_draw_ranges[quad_draw_ranges.count - 1];
        if last.texture == texture {
            last.count += vert_count;
            return;
        }
    }

    range: Quad_Draw_Range;
    range.texture = texture;
    range.start = quad_batch.count - vert_count;
    range.count = vert_count;
    array_add(*quad_draw_ranges, range);
}

QUAD_BUFFER_INITIAL_CAPACITY :: 4096;

ensure_quad_buffer_capacity :: (needed_verts: int) {
    using global_framework;
    
    if needed_verts <= quad_vertex_buffer_capacity return;

    new_capacity := max(needed_verts, quad_vertex_buffer_capacity * 2);
    if new_capacity < QUAD_BUFFER_INITIAL_CAPACITY new_capacity = QUAD_BUFFER_INITIAL_CAPACITY;

    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        quad_vertex_buffers[i] = device.newBufferWithLength_options(
            global_framework.device, xx (size_of(Quad_Vertex) * new_capacity), xx 0);
    }

    quad_vertex_buffer_capacity = new_capacity;
}

draw_rect :: (x: float32, y: float32, w: float32, h: float32, color: [4] float32) {
   draw_textured_rect(x, y, w, h, .[0,0], .[1,1], global_framework.white_texture, color);
}

draw_textured_rect :: (x: float32, y: float32, w: float32, h: float32,
                        uv_min: [2] float32, uv_max: [2] float32,
                        texture: *MTLTexture, color: [4] float32 = .[1,1,1,1])  {
    x0 := x;      y0 := y;
    x1 := x + w;  y1 := y + h;

    u0 := uv_min[0]; v0 := uv_min[1];
    u1 := uv_max[0]; v1 := uv_max[1];

    array_add(*quad_batch, Quad_Vertex.{ .[x0, y0], .[u0, v0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x0, y1], .[u0, v1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y1], .[u1, v1], color });

    array_add(*quad_batch, Quad_Vertex.{ .[x0, y0], .[u0, v0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y1], .[u1, v1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[x1, y0], .[u1, v0], color });

    push_quad_range(texture, 6);
}

draw_line :: (x0: float32, y0: float32, x1: float32, y1: float32, thickness: float32, color: [4] float32) {
    dx := x1 - x0;
    dy := y1 - y0;
    length := sqrt(dx * dx + dy * dy);
    if length < 0.0001 return;
    // Perpendicular unit vector, scaled to half-thickness
    nx := (-dy / length) * (thickness * 0.5);
    ny := (dx / length) * (thickness * 0.5);
    
    p0 := Vector2.{x0 + nx, y0 + ny};
    p1 := Vector2.{x0 - nx, y0 - ny};
    p2 := Vector2.{x1 - nx, y1 - ny};
    p3 := Vector2.{x1 + nx, y1 + ny};

    array_add(*quad_batch, Quad_Vertex.{ .[p0.x, p0.y], .[0, 0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[p1.x, p1.y], .[0, 1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[p2.x, p2.y], .[1, 1], color });

    array_add(*quad_batch, Quad_Vertex.{ .[p0.x, p0.y], .[0, 0], color });
    array_add(*quad_batch, Quad_Vertex.{ .[p2.x, p2.y], .[1, 1], color });
    array_add(*quad_batch, Quad_Vertex.{ .[p3.x, p3.y], .[1, 0], color });

    push_quad_range(global_framework.white_texture, 6);
}

evaluate_quadratic_bezier :: (p0: Vector2, p1: Vector2, p2: Vector2, t: float32) -> Vector2 {
    u := 1.0 - t;
    x := u*u*p0.x + 2*u*t*p1.x + t*t*p2.x;
    y := u*u*p0.y + 2*u*t*p1.y + t*t*p2.y;
    return Vector2.{x, y};
}

draw_quadratic_bezier :: (p0: Vector2, p1: Vector2, p2: Vector2, thickness: float32, color: [4] float32, segments: int = 24) {
    prev := p0;
    for i : 1..segments {
        t := cast(float32)i / cast(float32)segments;
        curr := evaluate_quadratic_bezier(p0, p1, p2, t);
        draw_line(prev.x, prev.y, curr.x, curr.y, thickness, color);
        prev = curr;
    }
}

evaluate_cubic_bezier :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float32) -> Vector2 {
    u := 1.0 - t;
    x := u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x;
    y := u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y;
    return Vector2.{x, y};
}

draw_cubic_bezier :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, thickness: float32, color: [4] float32, segments: int = 32) {
    prev := p0;
    for i : 1..segments {
        t := cast(float32)i / cast(float32)segments;
        curr := evaluate_cubic_bezier(p0, p1, p2, p3, t);
        draw_line(prev.x, prev.y, curr.x, curr.y, thickness, color);
        prev = curr;
    }
}
