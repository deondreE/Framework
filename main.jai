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

    //////////////////
    // Draw calls
    encoder.setRenderPipelineState(encoder, xx pipeline_state);
    encoder.setVertexBuffer_offset_atIndex(encoder, xx vertex_buffer, 0, 0);
    encoder.setVertexBytes_length_atIndex(encoder, xx *uniforms, size_of(Uniforms), 1);
    encoder.setVertexBytes_length_atIndex(encoder, instances.data, cast(u64)(size_of(InstanceData) * instances.count), 2);
    encoder.drawPrimitives_vertexStart_vertexCount_instanceCount(encoder, .MTLPrimitiveTypeTriangle, 0, 3, xx instances.count);

    draw_rect(20, 120, 200, 60, .[0.2, 0.4, 0.9, 1.0]); // solid blue-ish panel, pixel-space
    flush_quad_batch(encoder);

    draw_text("Jai Metal Framework", 20, 40, cast(float32)window_width, cast(float32)window_height, 1.0, cast(float32)window_width - 40);
    draw_text("Second label, wraps if too long to fit on one line here", 20, 80, cast(float32)window_width, cast(float32)window_height, 1.0, 300);
    flush_text_batch(encoder);

    encoder.endEncoding(encoder);
    cmd_buffer.presentDrawable(cmd_buffer, xx drawable);
    cmd_buffer.commit(cmd_buffer);

    frame_index += 1;
}