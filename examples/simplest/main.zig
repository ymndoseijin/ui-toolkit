const std = @import("std");

const ui = @import("ui");
const shaders = @import("shaders");

const graphics = ui.graphics;
const Vec3 = ui.Vec3;
const Vertex = ui.Vertex;
const common = ui.common;

const Ui = ui.Ui;

const math = ui.math;
const gl = ui.gl;

var state: *Ui = undefined;

fn keyDown(key_state: ui.KeyState, mods: i32, dt: f32) !void {
    _ = mods;
    _ = dt;
    if (key_state.pressed_table[graphics.glfw.GLFW_KEY_Q]) {
        state.main_win.alive = false;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    state = try Ui.init(ally, .{ .window = .{ .name = "image test", .width = 1920, .height = 1080, .resizable = false } });
    defer state.deinit(ally);
    state.key_down = keyDown;

    var tex = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ear.qoi", .{ .mag_filter = .linear, .min_filter = .linear, .texture_type = .flat });
    var venus_tex = try graphics.Texture.initFromPath(ally, state.main_win, "resources/cool.png", .{ .mag_filter = .linear, .min_filter = .linear, .texture_type = .flat });
    defer tex.deinit();
    defer venus_tex.deinit();

    var sprite = try graphics.Sprite.init(&state.scene, .{ .tex = tex });

    //try sprite.updateTexture(.{ .tex = venus_tex });

    while (state.main_win.alive) {
        try state.updateEvents();

        sprite.transform.rotation.angle += 0.1;
        sprite.updateTransform();

        try state.render();
    }

    try state.main_win.gc.vkd.deviceWaitIdle(state.main_win.gc.dev);
}
