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

Layout :: struct {
    type: Layout_Type;
    alignment: Layout_Alignment = .Start;
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
// INFO: offset = (TotalAvailible - ElementSize) X Factor
layout_reserve_space :: (l: *Layout, w: float32, h: float32) -> (x: float32, y: float32, final_w: float32, final_h: float32){
    final_w := w;
    final_h := h;

    if l.type == .Vertical && w <= 0 {
        final_w = l.size.x - (l.padding * 2);
    } else if l.type == .Horizontal && h <= 0 {
        final_h = l.size.y - (l.padding * 2);
    }

    offset_x: float32 = 0;
    offset_y: float32 = 0;
    
    if l.type == {
        case .Vertical;
        if l.alignment == {
            case .Center;
            offset_x = (l.size.x - final_w) * 0.5 - l.padding;
            case .End;
            offset_y = (l.size.x - final_w) - (l.padding * 2);
          }
        case .Horizontal;
        if l.alignment == {
            case .Center;
            offset_x = (l.size.y - final_h) * 0.5 - l.padding;
            case .End;
            offset_y = (l.size.y - final_h) - (l.padding * 2);
        }
    }

    res_x := l.cursor.x + offset_x;
    res_y := l.cursor.y + offset_y;

    if l.type == {
        case .Vertical;
        l.cursor.y += final_h + l.spacing;
        case .Horizontal;
        l.cursor.x += final_w + l.spacing;
    }

    return res_x, res_y, final_w, final_h;
}

layout_end :: (layout: *Layout) {
    // NOTE: Potentially calculate total used height/width for auto-sizing containers
}
