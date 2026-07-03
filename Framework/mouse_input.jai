#import "Basic";
#import "Window_Creation";
#import "Input"; 

Mouse_State :: struct {
    x, y: float32;

    left_down: bool;
    left_pressed: bool;
    left_released: bool;

    right_down: bool;
    right_pressed: bool;
    right_released: bool;

    middle_down: bool;
    middle_pressed: bool;
    middle_released: bool;

    wheel_delta: float32;
}; 

update_mouse_state :: (mouse: *Mouse_State, window: *NSWindow) {
    px, py, ok := get_mouse_pointer_position(window, false);
    if ok {
        mouse.x = cast(float32)px;
        mouse.y = cast(float32)py;
    }

    left   := input_button_states[cast(int)Key_Code.MOUSE_BUTTON_LEFT];
    right  := input_button_states[cast(int)Key_Code.MOUSE_BUTTON_RIGHT];
    middle := input_button_states[cast(int)Key_Code.MOUSE_BUTTON_MIDDLE];

    mouse.left_down      = (left & .DOWN) != 0;
    mouse.left_pressed   = (left & .START) != 0;
    mouse.left_released  = (left & .END) != 0;

    mouse.right_down     = (right & .DOWN) != 0;
    mouse.right_pressed  = (right & .START) != 0;
    mouse.right_released = (right & .END) != 0;

    mouse.middle_down     = (middle & .DOWN) != 0;
    mouse.middle_pressed  = (middle & .START) != 0;
    mouse.middle_released = (middle & .END) != 0;

    mouse.wheel_delta = 0;
    for event : events_this_frame {
        if event.type == .MOUSE_WHEEL {
            mouse.wheel_delta = cast(float32)event.wheel_delta;
        }
    }
}

point_in_rect :: (px: float32, py: float32, x: float32, y: float32, w: float32, h: float32) -> bool {
    return px >= x && px <= x + w && py >= y && py <= y + h;
}

mouse_over_rect :: (mouse: Mouse_State, x: float32, y: float32, w: float32, h: float32) -> bool {
    return point_in_rect(mouse.x, mouse.y, x, y, w, h);
}