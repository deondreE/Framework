#import "freetype";
#import "Basic";

Glyph :: struct {
    uv_min: [2] float32;
    uv_max: [2] float32;
    size: [2] float32;
    bearing: [2] float32;
    advance: float32;
}

Font_Atlas :: struct {
    texture: *MTLTexture;
    glyphs: [128] Glyph;
    atlas_size: s32;
    line_height: float32;
}

load_font_atlas :: (path: string, pixel_height: u32) -> Font_Atlas, bool {
    atlas: Font_Atlas;
    atlas.atlas_size = 1024;

    lib: FT_Library;
    if FT_Init_FreeType(*lib) {
        print("Error: could not init Freetype.\n");
        return atlas, false;
    }
    defer FT_Done_FreeType(lib);

    c_path := temp_c_string(path);

    face: FT_Face;
    if FT_New_Face(lib, c_path, 0, *face) {
        print("Error: could not load font '%'.\n", path);
        return atlas, false;
    }
    defer FT_Done_Face(face);

    FT_Set_Pixel_Sizes(face, 0, pixel_height);
    atlas.line_height = cast(float32)(face.size.metrics.height >> 6);

    pixels := NewArray(atlas.atlas_size * atlas.atlas_size, u8);
    defer array_free(pixels);
    memset(pixels.data, 0, pixels.count);

    pen_x, pen_y: s32;
    row_height: s32;

    for code : 32..126 {
        if FT_Load_Char(face, cast(u64)code, FT_LOAD_RENDER) {
            print("Warning could not load glyph for char %.\n", code);
            continue;
        }

        slot := face.glyph;
        bmp  := slot.bitmap;

        if pen_x + cast(s32)bmp.width >= atlas.atlas_size {
            pen_x = 0;
            pen_y += row_height + 1;
            row_height = 0;
        }

        if bmp.buffer != null {
            for y : 0..cast(s32)bmp.rows - 1 {
                for x : 0..cast(s32)bmp.width - 1 {
                    src := bmp.buffer[y * bmp.pitch + x];
                    dst_x := pen_x + x;
                    dst_y := pen_y + y;
                    pixels[dst_y * atlas.atlas_size + dst_x] = src;
                }
            }
        }

        g := *atlas.glyphs[code];
        g.uv_min  = .[cast(float32)pen_x / atlas.atlas_size, cast(float32)pen_y / atlas.atlas_size];
        g.uv_max  = .[cast(float32)(pen_x + cast(s32)bmp.width) / atlas.atlas_size, cast(float32)(pen_y + cast(s32)bmp.rows) / atlas.atlas_size];
        g.size    = .[cast(float32)bmp.width, cast(float32)bmp.rows];
        g.bearing = .[cast(float32)slot.bitmap_left, cast(float32)slot.bitmap_top];
        g.advance = cast(float32)(slot.metrics.horiAdvance >> 6);

        pen_x += cast(s32)bmp.width + 1;
        row_height = max(row_height, cast(s32)bmp.rows);
    }
    
    tex_desc := MTLTextureDescriptor.texture2DDescriptorWithPixelFormat_width_height_mipmapped(
        .MTLPixelFormatR8Unorm, xx atlas.atlas_size, xx atlas.atlas_size, NO);
    tex_desc.setUsage(tex_desc, .MTLTextureUsageShaderRead);

    atlas.texture = xx global_framework.device.newTextureWithDescriptor(global_framework.device, tex_desc);

    region := MTLRegion.{ .{0,0,0}, .{xx atlas.atlas_size, xx atlas.atlas_size, 1} };
    atlas.texture.replaceRegion_mipmapLevel_withBytes_bytesPerRow(
        atlas.texture, region, 0, pixels.data, xx atlas.atlas_size);

    return atlas, true;
}