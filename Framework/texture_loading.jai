#import "Basic";
#import "Hash_Table";
#import "stb_image";
#import "Metal";

// A single frame's UV coordinates within a sprite sheet texture.
Sprite_Frame :: struct {
    uv_min: [2] float32;  // top-left  UV (0..1)
    uv_max: [2] float32;  // bottom-right UV (0..1)
}

// A sprite sheet loaded from a single texture file, sliced into a uniform grid of frames.
// Frames are ordered left-to-right, top-to-bottom.
Sprite_Sheet :: struct {
    texture:      *MTLTexture;
    frames:       [] Sprite_Frame;  // allocated slice; caller owns lifetime
    frame_width:  s32;  // pixel width of one frame
    frame_height: s32;  // pixel height of one frame
    columns:      s32;
    rows:         s32;
}

Texture_Cache_Entry :: struct {
    texture: *MTLTexture;
    width: s32;
    height: s32;
}

AnimatedSprite :: struct {
    texture: *MTLTexture;
    frame_count: s32;
    frame_width: s32;
    frame_height: s32;
    frame_duration: float32;
    frame_offsets: []s32;
}

texture_cache: Table(string, Texture_Cache_Entry);

load_texture :: (path: string) -> *MTLTexture, bool {
    using global_framework;

    found, cached := table_find(*texture_cache, path);
    if found return cached.texture, true;

    c_path := temp_c_string(path);

    w, h, channels_in_file: s32;
    pixels := stbi_load(c_path, *w, *h, *channels_in_file, xx STBI.rgb_alpha);
    if !pixels {
        reason := stbi_failure_reason();
        print("Error: could not load texture '%': %\n", path, to_string(reason));
        return null, false;
    }
    defer stbi_image_free(pixels);

    stbi_set_flip_vertically_on_load(0);

    desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        .MTLPixelFormatRGBA8Unorm, xx w, xx h, NO);
    desc.setUsage(desc, .MTLTextureUsageShaderRead);

    tex : *MTLTexture = xx device.newTextureWithDescriptor(device, desc);

    region := MTLRegion.{ .{0,0,0}, .{xx w, xx h, 1} };
    tex.replaceRegion_mipmapLevel_withBytes_bytesPerRow(tex, region, 0, pixels, xx (w * 4));

    entry: Texture_Cache_Entry;
    entry.texture = tex;
    entry.width = w;
    entry.height = h;

    table_add(*texture_cache, copy_string(path), entry);

    return tex, true;
}

// Load a sprite sheet from `path`, slicing it into `columns` x `rows` uniform frames.
// Returns false and a zeroed sheet on failure.
// The returned `sheet.frames` slice is heap-allocated; free it with `array_free` when done.
load_sprite_sheet :: (path: string, columns: s32, rows: s32) -> Sprite_Sheet, bool {
    sheet: Sprite_Sheet;

    tex, ok := load_texture(path);
    if !ok return sheet, false;

    // Retrieve dimensions from the cache entry that load_texture just populated.
    _, cached := table_find(*texture_cache, path);

    sheet.texture      = tex;
    sheet.columns      = columns;
    sheet.rows         = rows;
    sheet.frame_width  = cached.width  / columns;
    sheet.frame_height = cached.height / rows;

    total := columns * rows;
    frames := NewArray(total, Sprite_Frame);

    inv_w := 1.0 / cast(float32) cached.width;
    inv_h := 1.0 / cast(float32) cached.height;

    for row : 0..rows - 1 {
        for col : 0..columns - 1 {
            idx := row * columns + col;
            x0 := cast(float32)(col     * sheet.frame_width)  * inv_w;
            y0 := cast(float32)(row     * sheet.frame_height) * inv_h;
            x1 := cast(float32)((col+1) * sheet.frame_width)  * inv_w;
            y1 := cast(float32)((row+1) * sheet.frame_height) * inv_h;
            frames[idx].uv_min = .[x0, y0];
            frames[idx].uv_max = .[x1, y1];
        }
    }

    sheet.frames = frames;
    return sheet, true;
}

// Return the UV rect for `frame_index` (0-based, left-to-right then top-to-bottom).
// Clamps the index to the valid range.
get_sprite_frame :: (sheet: Sprite_Sheet, frame_index: int) -> Sprite_Frame {
    idx := clamp(frame_index, 0, sheet.frames.count - 1);
    return sheet.frames[idx];
}
