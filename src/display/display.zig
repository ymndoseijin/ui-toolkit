const std = @import("std");
const math = @import("math");
const gl = @import("gl");
const numericals = @import("numericals");
const img = @import("img");

pub const Ui = @import("ui.zig").Ui;
pub const Region = @import("ui.zig").Region;

const geometry = @import("geometry");
const graphics = @import("graphics");
const common = @import("common");
const Parsing = @import("parsing");

const BdfParse = Parsing.BdfParse;
const ObjParse = graphics.ObjParse;
const VsopParse = Parsing.VsopParse;

const Mesh = geometry.Mesh;
const Vertex = geometry.Vertex;
const HalfEdge = geometry.HalfEdge;

const Drawing = graphics.Drawing;
const glfw = graphics.glfw;

const Camera = graphics.Camera;
const Cube = graphics.Cube;
const Line = graphics.Line;
const MeshBuilder = graphics.MeshBuilder;

const Mat4 = math.Mat4;
const Vec2 = math.Vec2;
const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Vec3Utils = math.Vec3Utils;

const SpatialPipeline = graphics.SpatialPipeline;

const TAU = 6.28318530718;

const DrawingList = union(enum) {
    line: *Drawing(graphics.LinePipeline),
    flat: *Drawing(graphics.FlatPipeline),
    spatial: *Drawing(graphics.SpatialPipeline),
};

var is_wireframe = false;

fn defaultKeyDown(_: KeyState, _: i32, _: f32) !void {
    return;
}

fn defaultChar(_: u32) !void {
    return;
}

fn defaultScroll(_: f64, _: f64) !void {
    return;
}

fn defaultMouse(_: i32, _: graphics.Action, _: i32) !void {
    return;
}

fn defaultCursor(_: f64, _: f64) !void {
    return;
}

fn defaultFrame(_: i32, _: i32) !void {
    return;
}

fn defaultKey(_: i32, _: i32, _: graphics.Action, _: i32) !void {
    return;
}

pub const KeyState = struct {
    pressed_table: []bool,
    last_interact_table: []f64,
};

pub const State = struct {
    main_win: *graphics.Window,
    scene: graphics.Scene(DrawingList),
    skybox_scene: graphics.Scene(DrawingList),
    flat_scene: graphics.Scene(DrawingList),

    cam: Camera,

    time: f64,

    current_keys: [glfw.GLFW_KEY_MENU + 1]bool = .{false} ** (glfw.GLFW_KEY_MENU + 1),
    last_interact_keys: [glfw.GLFW_KEY_MENU + 1]f64 = .{0} ** (glfw.GLFW_KEY_MENU + 1),

    down_num: usize = 0,
    last_mods: i32 = 0,

    last_time: f32,
    dt: f32,

    ui: Ui,
    bdf: BdfParse,

    key_down: *const fn (KeyState, i32, f32) anyerror!void = defaultKeyDown,

    char_func: *const fn (codepoint: u32) anyerror!void = defaultChar,
    scroll_func: *const fn (xoffset: f64, yoffset: f64) anyerror!void = defaultScroll,
    mouse_func: *const fn (button: i32, action: graphics.Action, mods: i32) anyerror!void = defaultMouse,
    cursor_func: *const fn (xoffset: f64, yoffset: f64) anyerror!void = defaultCursor,
    frame_func: *const fn (width: i32, height: i32) anyerror!void = defaultFrame,
    key_func: *const fn (key: i32, scancode: i32, action: graphics.Action, mods: i32) anyerror!void = defaultKey,

    pub fn init(info: graphics.WindowInfo) !*State {
        var bdf = try BdfParse.init();
        try bdf.parse("b12.bdf");

        try graphics.initGraphics();
        _ = graphics.glfw.glfwWindowHint(graphics.glfw.GLFW_SAMPLES, 4);

        var state = try common.allocator.create(State);

        var main_win = try common.allocator.create(graphics.Window);
        main_win.* = try graphics.Window.initBare(info);

        gl.enable(gl.MULTISAMPLE);
        gl.cullFace(gl.FRONT);
        gl.enable(gl.BLEND);
        gl.lineWidth(2);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        try main_win.addToMap(state);

        main_win.setKeyCallback(keyFunc);
        main_win.setFrameCallback(frameFunc);
        main_win.setCharCallback(charFunc);
        main_win.setScrollCallback(scrollFunc);
        main_win.setCursorCallback(cursorFunc);
        main_win.setMouseButtonCallback(mouseFunc);

        var cam = try Camera.init(0.6, 1, 0.1, 2048);
        cam.move = .{ 0, 0, 0 };
        try cam.updateMat();

        state.* = State{
            .main_win = main_win,
            .cam = cam,
            .bdf = bdf,
            .time = 0,
            .dt = 1,
            .scene = try graphics.Scene(DrawingList).init(),
            .skybox_scene = try graphics.Scene(DrawingList).init(),
            .flat_scene = try graphics.Scene(DrawingList).init(),
            .last_time = @as(f32, @floatCast(graphics.glfw.glfwGetTime())),
            .ui = try Ui.init(common.allocator, main_win),
        };

        return state;
    }

    pub fn charFunc(ptr: *anyopaque, codepoint: u32) !void {
        var state: *State = @ptrCast(@alignCast(ptr));
        try state.ui.getChar(codepoint);
        try state.char_func(codepoint);
    }

    pub fn scrollFunc(ptr: *anyopaque, xoffset: f64, yoffset: f64) !void {
        var state: *State = @ptrCast(@alignCast(ptr));
        try state.ui.getScroll(xoffset, yoffset);
        try state.scroll_func(xoffset, yoffset);
    }

    pub fn mouseFunc(ptr: *anyopaque, button: i32, action: graphics.Action, mods: i32) !void {
        var state: *State = @ptrCast(@alignCast(ptr));
        try state.ui.getMouse(button, action, mods);
        try state.mouse_func(button, action, mods);
    }

    pub fn cursorFunc(ptr: *anyopaque, xoffset: f64, yoffset: f64) !void {
        var state: *State = @ptrCast(@alignCast(ptr));
        try state.ui.getCursor(xoffset, yoffset);
        try state.cursor_func(xoffset, yoffset);
    }

    pub fn updateEvents(state: *State) !void {
        var time = @as(f32, @floatCast(graphics.glfw.glfwGetTime()));

        graphics.waitGraphicsEvent();

        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        time = @as(f32, @floatCast(graphics.glfw.glfwGetTime()));

        state.dt = time - state.last_time;
        state.time = time;

        if (state.down_num > 0) {
            try state.key_down(.{ .pressed_table = &state.current_keys, .last_interact_table = &state.last_interact_keys }, state.last_mods, state.dt);
        }

        state.last_time = time;
    }

    pub fn render(state: *State) !void {
        state.cam.eye = state.cam.eye;
        try state.cam.updateMat();

        gl.disable(gl.DEPTH_TEST);
        gl.disable(gl.CULL_FACE);
        try state.skybox_scene.draw(state.main_win.*);

        gl.enable(gl.DEPTH_TEST);
        //gl.enable(gl.CULL_FACE);
        //gl.cullFace(gl.BACK);
        try state.scene.draw(state.main_win.*);

        gl.disable(gl.DEPTH_TEST);
        gl.disable(gl.CULL_FACE);
        try state.flat_scene.draw(state.main_win.*);

        graphics.glfw.glfwSwapBuffers(state.main_win.glfw_win);
    }

    pub fn deinit(self: *State) void {
        self.ui.deinit();
        self.main_win.deinit();
        self.scene.deinit();
        self.skybox_scene.deinit();
        self.flat_scene.deinit();
        self.bdf.deinit();
        graphics.deinitGraphics();
        common.allocator.destroy(self);
    }

    fn frameFunc(ptr: *anyopaque, width: i32, height: i32) !void {
        var state: *State = @ptrCast(@alignCast(ptr));

        const w: f32 = @floatFromInt(width);
        const h: f32 = @floatFromInt(height);
        try state.cam.setParameters(0.6, w / h, 0.1, 2048);

        try state.ui.getFrame(width, height);
        try state.frame_func(width, height);
    }

    fn keyFunc(ptr: *anyopaque, key: i32, scancode: i32, action: graphics.Action, mods: i32) !void {
        var state: *State = @ptrCast(@alignCast(ptr));

        try state.ui.getKey(key, scancode, action, mods);
        try state.key_func(key, scancode, action, mods);

        if (action == .press) {
            if (key == glfw.GLFW_KEY_C) {
                if (is_wireframe) {
                    gl.polygonMode(gl.FRONT_AND_BACK, gl.FILL);
                    is_wireframe = false;
                } else {
                    gl.polygonMode(gl.FRONT_AND_BACK, gl.LINE);
                    is_wireframe = true;
                }
            }
            state.current_keys[@intCast(key)] = true;
            state.last_interact_keys[@intCast(key)] = state.time;

            state.last_mods = mods;
            state.down_num += 1;
        } else if (action == .release) {
            state.current_keys[@intCast(key)] = false;
            state.last_interact_keys[@intCast(key)] = state.time;

            state.down_num -= 1;
        }
    }
};
