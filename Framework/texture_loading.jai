#import "Basic";
#import "Hash_Table";
#import "stb_image";
#import "Metal";

Texture_Cache_Entry :: struct {
    texture: *MTLTexture;
    width: s32;
    height: s32;
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