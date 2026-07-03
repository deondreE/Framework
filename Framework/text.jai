#import "Basic";
Text_Vertex :: struct {
    position: [2] float32;
    uv: [2] float32;
}

// Decodes one UTF-8 codepoint starting at byte index *i, advances *i past it.
// Malformed sequences decode to U+FFFD and advance by 1 byte, so we never
// get stuck in an infinite loop on bad input.
decode_utf8 :: (s: string, i: *int) -> u32 {
    b0 := s[i.*];

    if b0 < 0x80 {
        i.* += 1;
        return cast(u32)b0;
    }

    if (b0 & 0xE0) == 0xC0 && i.* + 1 < s.count {
        b1 := s[i.* + 1];
        cp := (cast(u32)(b0 & 0x1F) << 6) | cast(u32)(b1 & 0x3F);
        i.* += 2;
        return cp;
    }

    if (b0 & 0xF0) == 0xE0 && i.* + 2 < s.count {
        b1 := s[i.* + 1];
        b2 := s[i.* + 2];
        cp := (cast(u32)(b0 & 0x0F) << 12) | (cast(u32)(b1 & 0x3F) << 6) | cast(u32)(b2 & 0x3F);
        i.* += 3;
        return cp;
    }

    if (b0 & 0xF8) == 0xF0 && i.* + 3 < s.count {
        b1 := s[i.* + 1];
        b2 := s[i.* + 2];
        b3 := s[i.* + 3];
        cp := (cast(u32)(b0 & 0x07) << 18) | (cast(u32)(b1 & 0x3F) << 12) | (cast(u32)(b2 & 0x3F) << 6) | cast(u32)(b3 & 0x3F);
        i.* += 4;
        return cp;
    }

    // Malformed / truncated sequence.
    i.* += 1;
    return 0xFFFD;
}

append_glyph_quad :: (verts: *[..] Text_Vertex, g: Glyph, cursor_x: float32, y: float32, scale: float32, screen_w: float32, screen_h: float32) {
    gx := cursor_x + g.bearing[0] * scale;
    gy := y - g.bearing[1] * scale;
    gw := g.size[0] * scale;
    gh := g.size[1] * scale;

    x0 := (gx / screen_w) * 2.0 - 1.0;
    y0 := 1.0 - (gy / screen_h) * 2.0;
    x1 := ((gx + gw) / screen_w) * 2.0 - 1.0;
    y1 := 1.0 - ((gy + gh) / screen_h) * 2.0;

    u0 := g.uv_min[0]; v0 := g.uv_min[1];
    u1 := g.uv_max[0]; v1 := g.uv_max[1];

    array_add(verts, Text_Vertex.{ .[x0, y0], .[u0, v0] });
    array_add(verts, Text_Vertex.{ .[x0, y1], .[u0, v1] });
    array_add(verts, Text_Vertex.{ .[x1, y1], .[u1, v1] });

    array_add(verts, Text_Vertex.{ .[x0, y0], .[u0, v0] });
    array_add(verts, Text_Vertex.{ .[x1, y1], .[u1, v1] });
    array_add(verts, Text_Vertex.{ .[x1, y0], .[u1, v0] });
}

TEXT_BUFFER_INITIAL_CAPACITY :: 4096;

ensure_text_buffer_capacity :: (needed_verts: int) {
    using global_framework;

    if needed_verts <= text_vertex_buffer_capacity return;

    new_capacity := max(needed_verts, text_vertex_buffer_capacity * 2);
    if new_capacity < TEXT_BUFFER_INITIAL_CAPACITY new_capacity = TEXT_BUFFER_INITIAL_CAPACITY;

    for i : 0..MAX_FRAMES_IN_FLIGHT - 1 {
        text_vertex_buffers[i] = device.newBufferWithLength_options(
            device, xx (size_of(Text_Vertex) * new_capacity), xx 0);
    }

    text_vertex_buffer_capacity = new_capacity;
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