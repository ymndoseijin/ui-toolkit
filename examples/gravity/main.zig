const std = @import("std");

const ui = @import("ui");
const shaders = @import("shaders");

const graphics = ui.graphics;
const Ui = ui.Ui;
const math = ui.math;
const gl = ui.gl;

var state: *Ui = undefined;

const Toy = struct {
    zoom: f32,
    is_pan: bool = false,
    press_time: f32 = 0,
    speed: f32 = 1.0,

    offset: math.Vec2 = math.Vec2.init(.{ 0, 0 }),

    last_pos: math.Vec2,
    text: graphics.TextFt,

    pub fn getZoom(toy: Toy) f32 {
        return toy.zoom * toy.zoom;
    }

    pub fn getOffset(toy: Toy) math.Vec2 {
        return toy.offset.scale(-1);
    }

    pub fn updateText(toy: *Toy) !void {
        try toy.text.clear();
        try toy.text.printFmt(state.main_win.ally, "{d}x speed {d:.4}x zoom", .{ toy.speed, 20 / toy.zoom });
    }
};

var bad_code: *Toy = undefined;

fn keyDown(key_state: ui.KeyState, mods: i32, dt: f32) !void {
    _ = mods;
    _ = dt;
    if (key_state.pressed_table[graphics.glfw.GLFW_KEY_Q]) {
        state.main_win.alive = false;
    }

    const toy = bad_code;

    const factor = toy.speed;

    if (state.time - toy.press_time > 0.3) {
        if (key_state.pressed_table[graphics.glfw.GLFW_KEY_RIGHT]) {
            toy.speed += 0.5 * state.dt * factor;
            try toy.updateText();
        } else if (key_state.pressed_table[graphics.glfw.GLFW_KEY_LEFT]) {
            toy.speed -= 0.5 * state.dt * factor;
            try toy.updateText();
        }
    }
}

fn cursorMove(toy_ptr: *anyopaque, _: *ui.Callback, x: f64, y: f64) !void {
    const toy: *Toy = @alignCast(@ptrCast(toy_ptr));
    const pos = math.Vec2.init(.{ @floatCast(x), @floatCast(y) });

    if (toy.is_pan) {
        const offset = pos.sub(toy.last_pos).scale(2).div(state.main_win.getSize());
        toy.offset = toy.offset.add(offset.scale(toy.getZoom()));
    }
    toy.last_pos = pos;
}

fn mouseAction(toy_ptr: *anyopaque, _: *ui.Callback, button: i32, action: graphics.Action, _: i32) !void {
    const toy: *Toy = @alignCast(@ptrCast(toy_ptr));

    if (button == 2) {
        if (action == .press) toy.is_pan = true;
        if (action == .release) toy.is_pan = false;
    }
}

fn keyAction(toy_ptr: *anyopaque, _: *ui.Callback, button: i32, _: i32, action: graphics.Action, _: i32) !void {
    const toy: *Toy = @alignCast(@ptrCast(toy_ptr));

    if (button == graphics.glfw.GLFW_KEY_RIGHT) {
        if (action == .press) {
            toy.speed += 0.5;
            toy.press_time = @floatCast(state.time);
            try toy.updateText();
        }
    } else if (button == graphics.glfw.GLFW_KEY_LEFT) {
        if (action == .press) {
            toy.speed -= 0.5;
            toy.press_time = @floatCast(state.time);
            try toy.updateText();
        }
    }
}

fn zoomScroll(toy_ptr: *anyopaque, _: *ui.Callback, _: f64, y: f64) !void {
    const toy: *Toy = @alignCast(@ptrCast(toy_ptr));
    const factor = toy.zoom * 0.09 + 1;
    toy.zoom += @as(f32, @floatCast(y)) * factor;
    toy.zoom = @max(0.01, toy.zoom);
    try toy.updateText();
}

pub fn main() !void {
    const ally = std.heap.c_allocator;

    state = try Ui.init(ally, .{ .window = .{ .name = "Gravity Toy", .width = 800, .height = 800, .resizable = true } });
    defer state.deinit(ally);

    const gc = &state.main_win.gc;
    const win = state.main_win;
    state.key_down = keyDown;

    const ComputeUniform: graphics.DataDescription = .{
        .T = extern struct {
            delta: f32,
            mouse_on: bool,
            mouse_pos: [2]f32 align(4 * 2),
            particle_count: u32,
            switch_particles: bool,
        },
    };

    const Particle = extern struct {
        pos: [2]f32 align(4 * 2),
        vel: [2]f32 align(4 * 2),
    };

    const ParticleBuffer: graphics.DataDescription = .{
        .T = extern struct {
            particle: Particle,
        },
    };

    const ComputeDescription: graphics.ComputeDescription = .{
        .sets = &.{.{ .bindings = &.{
            .{ .uniform = .{ .size = ComputeUniform.getSize() } },
            .{ .storage = .{ .size = ParticleBuffer.getSize() } },
            .{ .storage = .{ .size = ParticleBuffer.getSize() } },
        } }},
    };
    const compute_shader = try graphics.Shader.init(win.gc, &shaders.compute, .compute);
    defer compute_shader.deinit(gc.*);

    var compute_pipeline = try graphics.ComputePipeline.init(ally, .{
        .description = ComputeDescription,
        .shader = compute_shader,
        .gc = &win.gc,
        .flipped_z = true,
    });
    defer compute_pipeline.deinit(&win.gc);
    var compute = try graphics.Compute.init(ally, .{ .win = win, .pipeline = compute_pipeline });
    defer compute.deinit(ally);

    const particle_count = 102400;
    compute.setCount(particle_count / 256, 1, 1);

    const compute_buffer = try graphics.BufferHandle.init(gc, .{ .size = ParticleBuffer.getSize() * particle_count, .buffer_type = .storage });
    defer compute_buffer.deinit(gc);

    const previous_buffer = try graphics.BufferHandle.init(gc, .{ .size = ParticleBuffer.getSize() * particle_count, .buffer_type = .storage });
    defer previous_buffer.deinit(gc);

    const particles = try ally.alloc(Particle, particle_count);
    defer ally.free(particles);

    var xoshiro = std.Random.Xoshiro256.init(252);
    const random = xoshiro.random();

    for (particles) |*particle| {
        const r = 0.25 * @sqrt(random.float(f32));
        const theta = random.float(f32) * 2 * 3.14159265358979323846;
        const x = r * @cos(theta);
        const y = r * @sin(theta);
        const vec = math.Vec2.init(.{ x, y });

        const box_length = 20000.0;

        particle.pos = .{ random.float(f32) * box_length - box_length / 2.0, random.float(f32) * box_length - box_length / 2.0 };
        particle.vel = vec.norm().scale(0.1).val;
    }

    try compute_buffer.setStorage(ParticleBuffer, gc, win.pool, .{ .data = particles, .index = 0 });
    try previous_buffer.setStorage(ParticleBuffer, gc, win.pool, .{ .data = particles, .index = 0 });

    try compute.descriptor.updateDescriptorSets(ally, .{ .storage = &.{.{ .idx = 1, .buffer = compute_buffer }} });
    try compute.descriptor.updateDescriptorSets(ally, .{ .storage = &.{.{ .idx = 2, .buffer = compute_buffer }} });

    const points_vert = try graphics.Shader.init(win.gc, &shaders.points_vert, .vertex);
    defer points_vert.deinit(win.gc);

    const points_frag = try graphics.Shader.init(win.gc, &shaders.points_frag, .fragment);
    defer points_frag.deinit(win.gc);

    const PushConstants: graphics.DataDescription = .{ .T = extern struct {
        cam_pos: [3]f32 align(4 * 4),
        cam_transform: math.Mat4 align(4 * 4),
        light_count: i32,
    } };

    const PointsUniform: graphics.DataDescription = .{ .T = extern struct {
        zoom: f32,
        offset: [2]f32 align(2 * 4),
    } };

    const points_description: graphics.PipelineDescription = comptime .{
        .vertex_description = .{
            .vertex_attribs = &.{ .{ .size = 2 }, .{ .size = 2 } },
        },
        .render_type = .point,
        .depth_test = false,
        .cull_type = .none,
        .sets = &.{.{ .bindings = &.{
            .{ .uniform = .{ .size = PointsUniform.getSize() } },
            .{ .storage = .{ .size = ParticleBuffer.getSize() } },
        } }},
        .constants_size = PushConstants.getSize(),
    };

    var points_pipeline = try graphics.RenderPipeline.init(ally, .{
        .description = points_description,
        .shaders = &.{ points_vert, points_frag },
        .rendering = state.main_win.rendering_options,
        .gc = &win.gc,
        .flipped_z = true,
    });
    defer points_pipeline.deinit(gc);

    const points_drawing = try ally.create(graphics.Drawing);
    defer ally.destroy(points_drawing);

    try points_drawing.init(ally, .{
        .win = win,
        .pipeline = points_pipeline,
    });
    defer points_drawing.deinit(ally);

    points_drawing.vertex_buffer = compute_buffer;
    points_drawing.vert_count = particle_count;

    try points_drawing.descriptor.updateDescriptorSets(ally, .{ .storage = &.{.{ .idx = 1, .buffer = compute_buffer }} });

    var pressed: bool = false;

    var toy: Toy = .{
        .zoom = 20,
        .last_pos = win.getCursorPos(),
        .text = try graphics.TextFt.init(ally, .{
            .path = "resources/cmunrm.ttf",
            .size = 25,
            .line_spacing = 1,
            .bounding_width = 2500,
            .flip_y = false,
            .scene = &state.scene,
        }),
    };
    defer toy.text.deinit();

    bad_code = &toy;

    toy.text.transform.translation = math.Vec2.init(.{ 10, 10 });
    try toy.updateText();

    state.callback.focused = .{ @ptrCast(&toy), .{
        .scroll_func = zoomScroll,
        .cursor_func = cursorMove,
        .mouse_func = mouseAction,
        .key_func = keyAction,
    } };
    var zoom: f32 = toy.zoom;

    var switch_val: bool = false;

    while (win.alive) {
        const frame = graphics.tracy.namedFrame("Frame");
        defer frame.end();

        try state.updateEvents();

        switch_val = !switch_val;

        if (win.getMouseButton(0) == .press) pressed = true;
        if (win.getMouseButton(0) == .release) pressed = false;

        const target_zoom = toy.getZoom();
        const dist = target_zoom - zoom;
        zoom += 5 * dist * state.dt;

        compute.descriptor.getUniformOr(0, 0, 0).?.setAsUniform(ComputeUniform, .{
            .delta = state.dt * toy.speed,
            .mouse_on = pressed,
            .mouse_pos = win.getCursorPos().div(win.getSize()).scale(2).sub(math.Vec2.init(.{ 1, 1 })).scale(zoom).add(toy.getOffset()).val,
            .particle_count = particle_count,
            .switch_particles = switch_val,
        });

        points_drawing.descriptor.getUniformOr(0, 0, 0).?.setAsUniform(PointsUniform, .{
            .zoom = zoom,
            .offset = toy.getOffset().val,
        });

        const builder = &state.command_builder;
        const frame_id = builder.frame_id;
        const swapchain = &win.swapchain;
        const extent = swapchain.extent;

        // compute compute
        const compute_builder = &state.compute_builder;
        try compute.wait(frame_id);

        const compute_trace = graphics.tracy.traceNamed(@src(), "Compute Builder");
        try compute_builder.beginCommand(gc);
        try compute.dispatch(compute_builder.getCurrent(), .{ .bind_pipeline = true, .frame_id = 0 });
        try compute_builder.endCommand(gc);
        compute_trace.end();

        try compute.submit(ally, compute_builder.*, .{});

        // render graphics

        try swapchain.wait(gc, frame_id);

        try state.scene.queue.execute();

        state.image_index = try swapchain.acquireImage(gc, frame_id);

        const builder_trace = graphics.tracy.traceNamed(@src(), "Color Builder");
        try builder.beginCommand(gc);

        try builder.transitionLayout(gc, swapchain.getImage(state.image_index), .{
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
        });

        try builder.transitionLayoutTexture(gc, &state.post_color_tex, .{
            .old_layout = .undefined,
            .new_layout = .color_attachment_optimal,
        });

        const data = .{
            .cam_pos = state.cam.move.val,
            .cam_transform = state.cam.transform_mat,
            .light_count = 0,
        };
        builder.push(PushConstants, gc, points_pipeline.pipeline, &data);
        // first
        try builder.setViewport(gc, .{ .flip_z = state.scene.flip_z, .width = extent.width, .height = extent.height });
        builder.beginRendering(gc, .{
            .color_attachments = &.{state.post_color_tex.getAttachment()},
            .region = .{
                .x = 0,
                .y = 0,
                .width = extent.width,
                .height = extent.height,
            },
        });
        try points_drawing.draw(builder.getCurrent(), .{
            .frame_id = builder.frame_id,
            .bind_pipeline = true,
        });
        try state.scene.draw(builder);
        builder.endRendering(gc);

        try builder.transitionLayoutTexture(gc, &state.post_color_tex, .{
            .old_layout = .color_attachment_optimal,
            .new_layout = state.post_color_tex.getIdealLayout(),
        });
        builder.pipelineBarrier(gc, .{
            .src_stage = .{ .color_attachment_output_bit = true },
            .dst_stage = .{ .color_attachment_output_bit = true },
        });

        // post
        try builder.setViewport(gc, .{ .flip_z = false, .width = extent.width, .height = extent.height });
        builder.beginRendering(gc, .{
            .color_attachments = &.{swapchain.getAttachment(state.image_index)},
            .region = .{
                .x = 0,
                .y = 0,
                .width = extent.width,
                .height = extent.height,
            },
        });
        try state.post_scene.draw(builder);
        builder.endRendering(gc);

        try builder.transitionLayout(gc, swapchain.getImage(state.image_index), .{
            .old_layout = .color_attachment_optimal,
            .new_layout = .present_src_khr,
        });

        try builder.endCommand(gc);
        builder_trace.end();

        try swapchain.submit(gc, state.command_builder, .{ .wait = &.{
            .{ .semaphore = compute.compute_semaphores[frame_id], .type = .vertex },
            .{ .semaphore = swapchain.image_acquired[frame_id], .type = .color },
        } });
        try swapchain.present(gc, .{ .wait = &.{swapchain.render_finished[frame_id]}, .image_index = state.image_index });
    }

    try win.gc.vkd.deviceWaitIdle(win.gc.dev);
}