#import "Basic";
#import "Framework";
#import "Metal";
#import "Objective_C";

main :: () {
    if !init_framework() {
        print("Failed to init framework.\n");
        return;
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

    //////////////////
    // Draw calls
    encoder.setRenderPipelineState(encoder, xx pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, 0);
    encoder.setVertexBytes_length_atIndex(encoder, xx *uniforms, size_of(Uniforms), 1);
    encoder.setVertexBytes_length_atIndex(encoder, instances.data, cast(u64)(size_of(InstanceData) * instances.count), 2);
    encoder.setVertexBytes_length_atIndex(encoder, *screen_uniforms, size_of(Screen_Uniforms), 3);
    encoder.drawPrimitives_vertexStart_vertexCount_instanceCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3, xx instances.count);

    draw_rect(20, 120, 200, 60, .[0.2, 0.4, 0.9, 1.0]); // solid blue-ish panel, pixel-space

    // --- draw_line tests ---

    // Thick diagonal line, to check the perpendicular-offset math at an angle
    draw_line(500, 100, 700, 300, 8.0, .[1.0, 0.3, 0.3, 1.0]);
    draw_line(500, 300, 700, 100, 8.0, .[0.3, 1.0, 0.3, 1.0]);

    // Quadratic — one control point pulling the curve upward
    draw_quadratic_bezier(
        Vector2.{750, 300}, Vector2.{850, 100}, Vector2.{950, 300},
        3.0, .[0.4, 0.8, 1.0, 1.0]);

    // Cubic — S-curve, classic case for testing two independent control points
    draw_cubic_bezier(
        Vector2.{750, 350}, Vector2.{820, 250}, Vector2.{880, 450}, Vector2.{950, 350},
        3.0, .[1.0, 0.6, 0.9, 1.0]);

    flush_quad_batch(encoder);

    draw_text("Jai Metal Framework", 20, 40, cast(float32)window_width, cast(float32)window_height, 1.0, cast(float32)window_width - 40);
    draw_text("Second label, wraps if too long to fit on one line here", 20, 80, cast(float32)window_width, cast(float32)window_height, 1.0, 300);
    flush_text_batch(encoder);

    encoder.endEncoding(encoder);
    cmd_buffer.presentDrawable(cmd_buffer, xx drawable);
    cmd_buffer.commit(cmd_buffer);

    frame_index += 1;
}