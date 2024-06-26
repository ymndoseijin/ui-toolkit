const std = @import("std");
const math = @import("math");
const gl = @import("gl");
const img = @import("img");
const geometry = @import("geometry");
const graphics = @import("../graphics.zig");
const common = @import("common");

const BdfParse = @import("parsing").BdfParse;

const Mesh = geometry.Mesh;
const Vertex = geometry.Vertex;
const HalfEdge = geometry.HalfEdge;

const Drawing = graphics.Drawing;
const glfw = graphics.glfw;
const Mat4 = math.Mat4;
const Vec3 = math.Vec3;
const Vec3Utils = math.Vec3Utils;

const fs = 15;

const elem_shaders = @import("elem_shaders");

pub fn bdfToRgba(res: []bool) ![fs * fs]img.color.Rgba32 {
    var buf: [fs * fs]img.color.Rgba32 = undefined;
    for (res, 0..) |val, i| {
        if (val) {
            buf[i] = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
        } else {
            buf[i] = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        }
    }
    return buf;
}

pub const Image = struct {
    width: u32,
    height: u32,
    data: []img.color.Rgba32,
};

pub const BdfUniform: graphics.DataDescription = .{ .type = extern struct { pod: math.Vec3 } };

pub const BdfPipeline = graphics.RenderPipeline{
    .vertex_description = .{
        .vertex_attribs = &.{ .{ .size = 3 }, .{ .size = 2 } },
    },
    .render_type = .triangle,
    .depth_test = false,
    .cull_face = false,
    .uniform_sizes = &.{ graphics.GlobalUniform.getSize(), BdfUniform.getSize() },
    .global_ubo = true,
};

pub const Text = struct {
    drawing: *Drawing,
    bdf: BdfParse,
    atlas: Image,
    pos: Vec3,
    width: f32,
    height: f32,
    texture: graphics.Texture,

    pub fn makeAtlas(ally: std.mem.Allocator, bdf: BdfParse) !Image {
        const count = bdf.map.items.len;

        const count_float: f32 = @floatFromInt(count);

        const size: u32 = @intFromFloat(@ceil(@sqrt(count_float)));

        const side_size: u32 = size * bdf.width;

        var atlas = try ally.alloc(img.color.Rgba32, side_size * side_size);
        for (atlas) |*elem| {
            elem.* = .{ .r = 30, .g = 100, .b = 100, .a = 255 };
        }

        for (bdf.map.items, 0..) |search, i| {
            const atlas_x = (i % size) * bdf.width;
            const atlas_y = @divFloor(i, size) * bdf.width;
            const rgba = try bdfToRgba(search[1]);

            for (rgba, 0..) |color, j| {
                const char_x = j % bdf.width;
                const char_y = @divFloor(j, bdf.width);
                atlas[(atlas_y + char_y) * side_size + atlas_x + char_x] = color;
            }
        }

        return Image{ .data = atlas, .width = side_size, .height = side_size };
    }

    pub fn printFmt(self: *Text, comptime fmt: []const u8, fmt_args: anytype) !void {
        var buf: [4098]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, fmt, fmt_args);
        try self.print(str);
    }

    pub fn print(self: *Text, ally: std.mem.Allocator, text: []const u8) !void {
        if (text.len == 0) return;

        const Attribute = BdfPipeline.getAttributeType();
        var vertices = std.ArrayList(Attribute).init(ally);
        var indices = std.ArrayList(u32).init(ally);
        defer vertices.deinit();
        defer indices.deinit();

        const width: f32 = @floatFromInt(self.bdf.width);

        var x: f32 = 0;
        var y: f32 = 0;

        var x_int: u32 = 0;

        var utf8 = (try std.unicode.Utf8View.init(text)).iterator();

        var is_start = true;

        var final_width: f32 = 0;
        var final_height: f32 = 0;

        while (utf8.nextCodepoint()) |c| : (x_int += 1) {
            if (c == '\n') {
                x = 0;
                is_start = true;
                y -= width;
                x_int -= 1;
                continue;
            }
            const count_float: f32 = @floatFromInt(self.bdf.map.items.len);
            const size: u32 = @intFromFloat(@ceil(@sqrt(count_float)));
            const size_f: f32 = @ceil(@sqrt(count_float));

            for (self.bdf.map.items, 0..) |search, i| {
                if (search[0] == c) {
                    const bbx_width: f32 = @floatFromInt(search[2] + 2);
                    if (!is_start) {
                        x += bbx_width;
                    } else {
                        is_start = false;
                    }

                    const atlas_x: f32 = @floatFromInt(i % size);
                    const atlas_y: f32 = @floatFromInt(@divFloor(i, size) + 1);

                    const c_vert = [_]Attribute{
                        .{ .{ x, y, 0 }, .{ atlas_x, size_f - atlas_y } },
                        .{ .{ x + width, y, 0 }, .{ atlas_x + 1, size_f - atlas_y } },
                        .{ .{ x + width, y + width, 0 }, .{ atlas_x + 1, size_f - atlas_y + 1 } },
                        .{ .{ x, y + width, 0 }, .{ atlas_x, size_f - atlas_y + 1 } },
                    };

                    final_width = x + width;
                    final_height = y + width;

                    const start: u32 = x_int * 4;

                    try indices.append(start);
                    try indices.append(start + 1);
                    try indices.append(start + 2);
                    try indices.append(start);
                    try indices.append(start + 2);
                    try indices.append(start + 3);

                    inline for (c_vert) |val| {
                        try vertices.append(val);
                    }
                    break;
                }
            }
        }

        self.width = final_width;
        self.height = final_height;

        try BdfPipeline.vertex_description.bindVertex(self.drawing, vertices.items, indices.items);
    }

    pub fn deinit(self: *Text, ally: std.mem.Allocator) void {
        ally.free(self.atlas.data);
        self.texture.deinit();
    }

    pub fn init(scene: anytype, bdf: BdfParse, pos: Vec3) !Text {
        const atlas = try makeAtlas(bdf);

        var tex = try graphics.Texture.init(scene.window, atlas.width, atlas.height, .{ .mag_filter = .linear, .min_filter = .linear, .texture_type = .flat });
        try tex.setFromRgba(atlas);

        var drawing = try scene.new();

        var pipeline = BdfPipeline;
        pipeline.samplers = &.{tex};

        try drawing.init(scene.window, &scene.window.default_shaders.text_shaders, pipeline);

        const res = Text{
            .bdf = bdf,
            .pos = pos,
            .drawing = drawing,
            .atlas = atlas,
            .width = 0,
            .height = 0,
            .texture = tex,
        };

        return res;
    }
};
