const std = @import("std");

const ui = @import("ui");
const graphics = ui.graphics;
const Vec3 = ui.Vec3;
const Vertex = ui.Vertex;
const common = ui.common;
const Ui = ui.Ui;
const math = ui.math;
const Box = ui.Box;

var main_program: *Program = undefined;
var global_ally: std.mem.Allocator = undefined;

const Program = struct {
    color: graphics.ColoredRect,
    chat_background: graphics.ColoredRect,
    input_box: graphics.ColoredRect,
    char_test: ui.TextBox,
    text_region: ui.Region,
    text: std.ArrayList(u8),
    state: *Ui,
    ally: std.mem.Allocator,

    border: NineRectSprite,
    text_border: NineRectSprite,
    root: *Box,

    pub fn init(state: *Ui) !Program {
        const ally = global_ally;
        const color = try graphics.ColoredRect.init(&state.scene, comptime try math.color.parseHexRGBA("c0c0c0"));
        const input_box = try graphics.ColoredRect.init(&state.scene, comptime try math.color.parseHexRGBA("8e8eb9"));
        const char_test = ui.TextBox.init(try graphics.TextFt.init(global_ally, "resources/fonts/Fairfax.ttf", 12, 1, 250));

        const text_region: ui.Region = .{ .transform = input_box.transform };

        const text_border = NineRectSprite{
            .top_left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/top_left.png", .{}),
            .bottom_left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/bottom_left.png", .{}),
            .top_right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/top_right.png", .{}),
            .bottom_right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/bottom_right.png", .{}),
            .top = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/top.png", .{}),
            .bottom = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/bottom.png", .{}),
            .left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/left.png", .{}),
            .right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_1/right.png", .{}),
        };

        const border = NineRectSprite{
            .top_left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/top_left.png", .{}),
            .bottom_left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/bottom_left.png", .{}),
            .top_right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/top_right.png", .{}),
            .bottom_right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/bottom_right.png", .{}),
            .top = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/top.png", .{}),
            .bottom = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/bottom.png", .{}),
            .left = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/left.png", .{}),
            .right = try graphics.Texture.initFromPath(ally, state.main_win, "resources/ui/box_2/right.png", .{}),
        };

        return .{
            .color = color,
            .chat_background = try graphics.ColoredRect.init(&state.scene, comptime try math.color.parseHexRGBA("ffffff")),
            .input_box = input_box,
            .char_test = char_test,
            .text_region = text_region,
            .text = std.ArrayList(u8).init(global_ally),
            .state = state,
            .ally = global_ally,
            .border = border,
            .text_border = text_border,
            .root = undefined,
        };
    }

    pub fn initPtr(program: *Program) !void {
        try program.state.callback.elements.append(.{ @ptrCast(program), .{
            .key_func = keyInput,
            .char_func = textInput,
            .region = &program.text_region,
        } });
        const margins = 10;
        //const text_margin = 20;

        var root = try Box.create(program.ally, .{
            .size = .{ 1920, 1080 },
            .children = &.{
                try Box.create(program.ally, .{
                    .expand = .{ .vertical = true, .horizontal = true },
                    .callbacks = &.{ui.getColorCallback(&program.color)},
                }),
                try ui.MarginBox(program.ally, .{ .top = margins, .bottom = margins, .left = margins, .right = margins }, try Box.create(program.ally, .{
                    .expand = .{ .vertical = true, .horizontal = true },
                    .flow = .{ .vertical = true },
                    .children = &.{
                        try program.border.init(&program.state.scene, program.ally, try Box.create(program.ally, .{
                            .expand = .{ .vertical = true, .horizontal = true },
                            .flow = .{ .vertical = true },
                            .callbacks = &.{.{}},
                        })),
                        try Box.create(program.ally, .{ .size = .{ 1000, 10 } }),
                        try program.text_border.init(&program.state.scene, program.ally, try Box.create(program.ally, .{
                            .label = "Text",
                            .expand = .{ .horizontal = true },
                            .size = .{ 0, 30 },
                            .callbacks = &.{
                                ui.getColorCallback(&program.input_box),
                                ui.getRegionCallback(&program.text_region),
                                program.char_test.getTextCallback(),
                            },
                        })),
                    },
                })),
            },
        });

        try root.resolve();
        root.print(0);
        program.root = root;
    }

    pub fn deinit(program: Program) void {
        program.text.deinit();
        program.root.deinit();
    }
};

pub fn frameUpdate(width: i32, height: i32) !void {
    main_program.root.fixed_size = .{ @floatFromInt(width), @floatFromInt(height) };
    main_program.root.current_size = .{ @floatFromInt(width), @floatFromInt(height) };
    try main_program.root.resolve();
}

fn keyInput(program_ptr: *anyopaque, _: *ui.Callback, key: i32, scancode: i32, action: graphics.Action, mods: i32) !void {
    _ = scancode;
    _ = mods;
    const program: *Program = @alignCast(@ptrCast(program_ptr));

    if (key == graphics.glfw.GLFW_KEY_ENTER and action == .press) {
        std.debug.print("woop \"{s}\"\n", .{program.text.items});
        program.text.clearRetainingCapacity();
        try program.char_test.text.clear(&program.state.scene, program.ally);
    }
}

fn textInput(program_ptr: *anyopaque, _: *ui.Callback, codepoint: u32) !void {
    var program: *Program = @alignCast(@ptrCast(program_ptr));

    var buf: [4]u8 = undefined;
    const string = buf[0..try std.unicode.utf8Encode(@intCast(codepoint), &buf)];
    for (string) |c| try program.text.append(c);
    try program.char_test.text.print(&program.state.scene, program.ally, .{ .text = string, .color = .{ 0.0, 0.0, 0.0 } });
}

const NineInfo = struct {
    top_left: *Box,
    left: *Box,
    bottom_left: *Box,
    top: *Box,
    bottom: *Box,
    top_right: *Box,
    right: *Box,
    bottom_right: *Box,
};

const NineRectSprite = struct {
    top_left: graphics.Texture,
    left: graphics.Texture,
    bottom_left: graphics.Texture,
    top: graphics.Texture,
    bottom: graphics.Texture,
    top_right: graphics.Texture,
    right: graphics.Texture,
    bottom_right: graphics.Texture,

    top_left_sprite: ?graphics.Sprite = null,
    left_sprite: ?graphics.Sprite = null,
    bottom_left_sprite: ?graphics.Sprite = null,
    top_sprite: ?graphics.Sprite = null,
    bottom_sprite: ?graphics.Sprite = null,
    top_right_sprite: ?graphics.Sprite = null,
    right_sprite: ?graphics.Sprite = null,
    bottom_right_sprite: ?graphics.Sprite = null,

    pub fn init(rect: *NineRectSprite, scene: anytype, ally: std.mem.Allocator, in_box: *Box) !*Box {
        rect.top_left_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.top_left });
        rect.left_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.left });
        rect.bottom_left_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.bottom_left });
        rect.top_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.top });
        rect.bottom_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.bottom });
        rect.top_right_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.top_right });
        rect.right_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.right });
        rect.bottom_right_sprite = try graphics.Sprite.init(scene, .{ .tex = rect.bottom_right });

        return NineRectBox(ally, .{
            .top_left = try Box.create(ally, .{
                .label = "top left",
                .size = .{ rect.top_left_sprite.?.width, rect.top_left_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.top_left_sprite.?)},
            }),
            .bottom_left = try Box.create(ally, .{
                .label = "bottom left",
                .size = .{ rect.bottom_left_sprite.?.width, rect.bottom_left_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.bottom_left_sprite.?)},
            }),
            .top_right = try Box.create(ally, .{
                .label = "top right",
                .size = .{ rect.top_right_sprite.?.width, rect.top_right_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.top_right_sprite.?)},
            }),
            .bottom_right = try Box.create(ally, .{
                .label = "bottom right",
                .size = .{ rect.bottom_right_sprite.?.width, rect.bottom_right_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.bottom_right_sprite.?)},
            }),
            .top = try Box.create(ally, .{
                .label = "top",
                .expand = .{ .horizontal = true },
                .size = .{ rect.top_sprite.?.width, rect.top_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.top_sprite.?)},
            }),
            .bottom = try Box.create(ally, .{
                .label = "bottom",
                .expand = .{ .horizontal = true },
                .size = .{ rect.bottom_sprite.?.width, rect.bottom_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.bottom_sprite.?)},
            }),
            .left = try Box.create(ally, .{
                .label = "left",
                .expand = .{ .vertical = true },
                .size = .{ rect.left_sprite.?.width, rect.left_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.left_sprite.?)},
            }),
            .right = try Box.create(ally, .{
                .label = "right",
                .expand = .{ .vertical = true },
                .size = .{ rect.right_sprite.?.width, rect.right_sprite.?.height },
                .callbacks = &.{ui.getSpriteCallback(&rect.right_sprite.?)},
            }),
        }, in_box);
    }
};

pub fn NineRectBox(ally: std.mem.Allocator, info: NineInfo, box: *Box) !*Box {
    return try Box.create(ally, .{
        .label = "nine rect",
        .flow = .{ .horizontal = true },
        .expand = box.expand,
        .fit = .{ .vertical = true, .horizontal = true },
        .children = &.{
            try Box.create(ally, .{
                .label = "left nine",
                .flow = .{ .vertical = true },
                .expand = .{ .vertical = true },
                .fit = .{ .vertical = true, .horizontal = true },
                .size = .{ 0, 0 },
                .children = &.{
                    info.top_left,
                    info.left,
                    info.bottom_left,
                },
            }),
            try Box.create(ally, .{
                .label = "middle nine",
                .flow = .{ .vertical = true },
                .expand = .{ .vertical = true, .horizontal = true },
                .fit = .{ .vertical = true, .horizontal = true },
                .children = &.{
                    info.top,
                    box,
                    info.bottom,
                },
            }),
            try Box.create(ally, .{
                .label = "right nine",
                .flow = .{ .vertical = true },
                .expand = .{ .vertical = true },
                .fit = .{ .vertical = true, .horizontal = true },
                .size = .{ 0, 0 },
                .children = &.{
                    info.top_right,
                    info.right,
                    info.bottom_right,
                },
            }),
        },
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    global_ally = gpa.allocator();
    const ally = global_ally;

    var state = try Ui.init(ally, .{ .name = "box test", .width = 500, .height = 500, .resizable = true, .preferred_format = .unorm });
    defer state.deinit(ally);

    //var sprite = try graphics.Sprite.init(&state.scene, .{ .tex = tex });

    var program_stack = try Program.init(state);
    try program_stack.initPtr();
    defer program_stack.deinit();
    main_program = &program_stack;

    state.frame_func = frameUpdate;

    while (state.main_win.alive) {
        try state.updateEvents();
        try state.render();
    }
}
