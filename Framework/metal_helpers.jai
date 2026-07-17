#import "Objective_C";

ns_string :: (s: string) -> *NSString {
    return NSString.initWithString(objc_alloc(NSString), s);
}

ndc_x :: (px: float32, screen_w: float32) -> float32 {
    return (px / screen_w) * 2.0 - 1.0;
}

ndc_y :: (py: float32, screen_h: float32) -> float32 {
    return 1.0 - (py / screen_h) * 2.0;
}
