#import "Basic";

Layout_Type :: enum s32 {
    Vertical;
    Horizontal;
}

Layout :: struct {
    type: Layout_Type;
    pos: Vector2;
    size: Vector2;
    cursor: Vector2;
    mouse: Mouse_State;
    padding: float32 = 8.0;
    spacing: float32 = 4.0;
    parent: *Layout;
}

layout_begin :: (l: *Layout, x: float32, y: float32, w: float32, h: float32) {
    l.pos = .{x, y};
    l.size = .{w, h};
    l.cursor = .{x + l.padding, y + l.padding};
}

layout_begin_child :: (parent: *Layout, type: Layout_Type, w: float32, h: float32) -> Layout {
    child: Layout;
    child.type = type;
    child.parent = parent;

    x, y, actual_w, actual_h := layout_reserve_space(parent, w, h);
    layout_begin(*child, x, y, actual_w, actual_h);
    return child;
}

// NOTE: Reserves required space for the ui layout that this is.
layout_reserve_space :: (l: *Layout, w: float32, h: float32) -> (x: float32, y: float32) {
    res_x := l.cursor.x;
    res_y := l.cursor.y;
    final_w := w;
    final_h := h;

    if l.type == {
        case .Vertical;
          // INFO If user passes 0 or -1, auto-fill to layout width;
          if w <= 0 then final_w = (l.pos.x + l.size.x) - l.padding - res_x;
          l.cursor.y += h + l.spacing;
        case .Horizontal;
          if h <= 0 then final_h = (l.pos.y + l.size.y) - l.padding - res_y;
          l.cursor.x += w + l.spacing;
    }

    return res_x, res_y;
}

layout_end :: (layout: *Layout) {
    // NOTE: Potentially calculate total used height/width for auto-sizing containers
}
