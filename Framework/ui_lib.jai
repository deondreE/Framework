#import "Basic";

Layout_Type :: enum s32 {
    Vertical;
    Horizontal;
}

Layout_Alignment :: enum s32 {
    Start;
    Center;
    End;
}

Rect :: struct {
    x, y, w, h: float32;
}

Layout :: struct {
    type: Layout_Type;
    alignment: Layout_Alignment = .Start;
    pos: Vector2;
    size: Vector2;
    rect: Rect;
    cursor: Vector2;
    mouse: Mouse_State;
    padding: float32 = 8.0;
    spacing: float32 = 4.0;
    parent: *Layout;
}

layout_begin :: (l: *Layout, x: float32, y: float32, w: float32, h: float32, mouse: *Mouse_State) {
    l.rect = .{x, y, w, h};
    l.cursor = .{x + l.padding, y + l.padding};
    l.mouse = mouse;
}

mouse_over_rect :: (mouse: Mouse_State, r: Rect) -> bool {
    return mouse.x >= r.x && mouse.x <= r.x + r.w && 
           mouse.y >= r.y && mouse.y <= r.y + r.h;
}

layout_reserve_space :: (l: *Layout, w: float32, h: float32) -> Rect {
    final_w := w;
    final_h := h;

    // Fixed-axis expansion
    if l.type == .Vertical && w <= 0   final_w = l.rect.w - (l.padding * 2);
    if l.type == .Horizontal && h <= 0 final_h = l.rect.h - (l.padding * 2);

    // Alignment Offsets
    off := Vector2.{0, 0};
    if l.type == .Vertical {
        if l.alignment == .Center off.x = (l.rect.w - final_w) * 0.5 - l.padding;
        if l.alignment == .End    off.x = (l.rect.w - final_w) - (l.padding * 2);
    } else {
        if l.alignment == .Center off.y = (l.rect.h - final_h) * 0.5 - l.padding;
        if l.alignment == .End    off.y = (l.rect.h - final_h) - (l.padding * 2);
    }

    res := Rect.{l.cursor.x + off.x, l.cursor.y + off.y, final_w, final_h};

    // Advance cursor
    if l.type == .Vertical   l.cursor.y += final_h + l.spacing;
    else                     l.cursor.x += final_w + l.spacing;

    return res;
}

layout_begin_child :: (parent: *Layout, type: Layout_Type, w: float32, h: float32) -> Layout {
    child: Layout;
    child.type = type;
    child.mouse = parent.mouse; // Pass mouse state down to child
    
    // Reserve the space in the parent for this child
    r := layout_reserve_space(parent, w, h);
    layout_begin(*child, r.x, r.y, r.w, r.h, *child.mouse);
    return child;
}


layout_end :: (layout: *Layout) {
    // NOTE: Potentially calculate total used height/width for auto-sizing containers
}
