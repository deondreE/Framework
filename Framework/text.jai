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