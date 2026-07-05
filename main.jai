#import "Basic";
#import "Framework";
#import "Metal";
#import "Objective_C";
#import "Thread";

main :: () {
    if !init_framework() {
        print("Failed to init framework.\n");
        return;
    }
    audio_sys := audio_init();

    print("Background loading started... doing other things.\n");
    
    bg_sound_1, success_1 := load_sound_from_file("Assets/Sounds/Pickup5.wav");
    if success_1 {
        play_sound(audio_sys, *bg_sound_1, volume=0.7, looping=true);
    } else {
        print("FAILED TO LOAD SOUND\n");
    }
    
    print("Framework runing...");

    while !global_framework.quit {
        reset_temporary_storage();

        pool := objc_init(objc_alloc(objc_getClass("NSAutoReleasePool")));

        update_framework();
        render_pass();

        release_pool: (*void, Selector) -> void #c_call;
        release_pool = xx objc_msgSend;
        release_pool(pool, sel_registerName("release"));
    }
    
    audio_shutdown(audio_sys);
}

render_pass :: () {
    using global_framework;

    array_reset(*text_batch);
    array_reset(*quad_batch);
    array_reset(*quad_draw_ranges);

    // Get the next drawable to render into
    drawable := metal_layer.nextDrawable(metal_layer);
    if !drawable return;

    pass_descriptor := MTLRenderPassDescriptor.renderPassDescriptor();
    color_attachments := pass_descriptor.colorAttachments(pass_descriptor);
    color_attachment := color_attachments.objectAtIndexedSubscript(color_attachments, 0);

    color_attachment.setTexture(color_attachment, drawable.texture(drawable));
    color_attachment.setLoadAction(color_attachment, .MTLLoadActionClear);
    color_attachment.setStoreAction(color_attachment, .MTLStoreActionStore);
    color_attachment.setClearColor(color_attachment, MTLClearColor.{0.1, 0.1, 0.15, 1.0});

    cmd_buffer := command_queue.commandBuffer(command_queue);
    encoder := cmd_buffer.renderCommandEncoderWithDescriptor(cmd_buffer, pass_descriptor);

    now := current_time_monotonic();
    elapsed := cast(float32)to_float64_seconds(now - start_time);

    uniforms: Uniforms;
    uniforms.time = elapsed;

    screen_uniforms: Screen_Uniforms;
    screen_uniforms.screen_size = .[cast(float32)window_width, cast(float32)window_height];

    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Draw calls
    encoder.setRenderPipelineState(encoder, xx pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, 0);
    encoder.setVertexBytes_length_atIndex(encoder, xx *uniforms, size_of(Uniforms), 1);
    encoder.setVertexBytes_length_atIndex(encoder, instances.data, cast(u64)(size_of(InstanceData) * instances.count), 2);
    encoder.setVertexBytes_length_atIndex(encoder, *screen_uniforms, size_of(Screen_Uniforms), 3);
    encoder.drawPrimitives_vertexStart_vertexCount_instanceCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3, xx instances.count);

    // TODO: Make the layout be able to change the native cursor type.
    screen: Layout;
    layout_begin(*screen, 0, 0, cast(float32)window_width, cast(float32)window_height, *mouse);

    settings_menu := layout_begin_child(*screen, .Vertical, 300, 500);
    settings_menu.alignment = .Center;

    bg_r := layout_reserve_space(*settings_menu, 0, 0); 
    draw_rect(bg_r.x, bg_r.y, bg_r.w, bg_r.h, .[0.2, 0.2, 0.2, 1.0]);

    tr := layout_reserve_space(*settings_menu, 100, 40);
    panel_color: [4] float32 = .[1, 0, 0, 1];

    if mouse_over_rect(mouse, tr) { // Using the Rect 'tr' directly
        panel_color = .[0.2, 0.4, 0.9, 1.0];
        if mouse.left_pressed {
            print("Panel clicked %, %\n", mouse.x, mouse.y);
        }
    }
    draw_rect(tr.x, tr.y, tr.w, tr.h, panel_color);

    txt_r := layout_reserve_space(*settings_menu, 100, 20);
    draw_text("Settings Menu", txt_r.x, txt_r.y, cast(float32)window_width, cast(float32)window_height, 1.0, 300);

    layout_end(*settings_menu);
    layout_end(*screen);
    
    // --- draw_line tests ---

    // Thick diagonal line, to check the perpendicular-offset math at an angle
    //draw_line(500, 100, 700, 300, 8.0, .[1.0, 0.3, 0.3, 1.0]);
    //draw_line(500, 300, 700, 100, 8.0, .[0.3, 1.0, 0.3, 1.0]);

    // Quadratic — one control point pulling the curve upward
    //*draw_quadratic_bezier(
    //    Vector2.{750, 300}, Vector2.{850, 100}, Vector2.{950, 300},
    //    3.0, .[0.4, 0.8, 1.0, 1.0]);
    //    // Cubic — S-curve, classic case for testing two independent control points
    //draw_cubic_bezier(
    //    Vector2.{750, 350}, Vector2.{820, 250}, Vector2.{880, 450}, Vector2.{950, 350},
    // 3.0, .[1.0, 0.6, 0.9, 1.0]);

    flush_quad_batch(encoder);
    flush_text_batch(encoder);

    encoder.endEncoding(encoder);
    cmd_buffer.presentDrawable(cmd_buffer, xx drawable);
    cmd_buffer.commit(cmd_buffer);

    frame_index += 1;
}
