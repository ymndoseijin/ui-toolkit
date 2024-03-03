const std = @import("std");
const math = @import("math");
const gl = @import("gl");
const img = @import("img");
const geometry = @import("geometry");
const graphics = @import("../graphics.zig");
const common = @import("common");
const freetype = @import("freetype");

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

const Image = graphics.Image;

pub const Text = struct {
    characters: std.ArrayList(Character),
    face: freetype.Face,

    width: f32,
    height: f32,

    size: f32,
    line_spacing: f32,
    bounding_width: f32,
    bounding_height: f32,

    // 2D structure
    transform: graphics.Transform2D,
    opacity: f32,

    codepoints: std.ArrayList(u32),

    const CharacterInfo = struct {
        char: u32,
        index: usize,
        count: usize,
        shaders: ?[]graphics.Shader = null,
        pipeline: graphics.RenderPipeline = CharacterPipeline,
    };

    const CharacterUniform: graphics.UniformDescription = .{ .type = extern struct {
        transform: math.Mat4,
        opacity: f32,
        index: u32,
        count: u32,
        color: math.Vec3,
    } };

    const CharacterPipeline = graphics.RenderPipeline{
        .vertex_description = .{
            .vertex_attribs = &.{ .{ .size = 3 }, .{ .size = 2 } },
        },
        .render_type = .triangle,
        .depth_test = false,
        .uniform_sizes = &.{ graphics.GlobalUniform.getSize(), CharacterUniform.getSize() },
        .global_ubo = true,
    };

    pub const Character = struct {
        image: Image,
        sprite: graphics.CustomSprite(CharacterUniform),
        offset: math.Vec2,
        advance: f32,
        parent: *Text,

        texture: graphics.Texture,

        pub fn setOpacity(self: *Character, opacity: f32) void {
            self.sprite.setOpacity(opacity);
        }

        pub fn init(scene: anytype, ally: std.mem.Allocator, parent: *Text, info: CharacterInfo) !Character {
            try parent.face.loadChar(info.char, .{ .render = true });
            const glyph = parent.face.glyph();
            const bitmap = glyph.bitmap();

            var image: Image = .{
                .data = try ally.alloc(img.color.Rgba32, bitmap.rows() * bitmap.width()),
                .width = bitmap.width(),
                .height = bitmap.rows(),
            };

            const metrics = glyph.metrics();
            var offset: math.Vec2 = .{ @floatFromInt(metrics.horiBearingX), @floatFromInt(-metrics.height + metrics.horiBearingY) };
            offset[1] *= -1;

            const metrics_scale: math.Vec2 = @splat(1.0 / 64.0);
            offset *= metrics_scale;

            const advance: f32 = @floatFromInt(metrics.horiAdvance);

            for (0..bitmap.rows()) |i| {
                for (0..bitmap.width()) |j| {
                    const s: u8 = bitmap.buffer().?[i * bitmap.width() + j];
                    image.data[i * image.width + j] = .{ .r = 255, .g = 255, .b = 255, .a = s };
                }
            }

            var tex = try graphics.Texture.init(scene.window, image.width, image.height, .{ .mag_filter = .linear, .min_filter = .linear, .texture_type = .flat });
            try tex.setFromRgba(image);

            const sprite = try graphics.CustomSprite(CharacterUniform).init(scene, .{
                .tex = tex,
                .shaders = info.shaders orelse &scene.window.default_shaders.textft_shaders,
                .pipeline = info.pipeline,
            });

            CharacterUniform.setUniformField(sprite.drawing, 1, .index, @as(u32, @intCast(info.index)));
            CharacterUniform.setUniformField(sprite.drawing, 1, .count, @as(u32, @intCast(info.count)));
            CharacterUniform.setUniformField(sprite.drawing, 1, .opacity, parent.opacity);

            return .{
                .image = image,
                .parent = parent,
                .sprite = sprite,
                .offset = offset,
                .advance = advance / 64,
                .texture = tex,
            };
        }

        pub fn deinit(self: Character, ally: std.mem.Allocator) void {
            ally.free(self.image.data);
            self.texture.deinit();
        }
    };

    const TextInfo = struct {
        text: []const u8,
        color: math.Vec3 = .{ 1.0, 1.0, 1.0 },
        shaders: ?[]graphics.Shader = null,
        pipeline: graphics.RenderPipeline = CharacterPipeline,
    };

    pub fn printFmt(self: *Text, scene: anytype, ally: std.mem.Allocator, comptime fmt: []const u8, fmt_args: anytype) !void {
        var buf: [4098]u8 = undefined;
        const str = try std.fmt.bufPrint(&buf, fmt, fmt_args);
        try self.print(scene, ally, .{ .text = str });
    }

    pub fn setOpacity(self: *Text, opacity: f32) void {
        self.opacity = opacity;
        for (self.characters.items) |*c| {
            c.setOpacity(opacity);
        }
    }

    pub fn clear(self: *Text, scene: anytype, ally: std.mem.Allocator) !void {
        for (self.characters.items) |c| {
            scene.delete(ally, c.sprite.drawing);
            c.deinit(ally);
        }
        self.characters.clearRetainingCapacity();
        self.codepoints.clearRetainingCapacity();
    }

    pub fn getExtent(self: Text, unicode: []const u32) !f32 {
        var res: f32 = 0;
        for (unicode) |c| {
            try self.face.loadChar(c, .{ .render = true });
            const glyph = self.face.glyph();
            const metrics = glyph.metrics();
            const advance: f32 = @floatFromInt(metrics.horiAdvance);
            res += advance / 64;
        }
        return res;
    }

    pub fn print(self: *Text, scene: anytype, ally: std.mem.Allocator, info: TextInfo) !void {
        if (info.text.len == 0) return;

        var unicode = (try std.unicode.Utf8View.init(info.text)).iterator();

        while (unicode.nextCodepoint()) |c| {
            try self.codepoints.append(c);
        }

        var index: usize = self.codepoints.items.len - 1;

        unicode = (try std.unicode.Utf8View.init(info.text)).iterator();

        while (unicode.nextCodepoint()) |c| {
            defer index += 1;
            if (c == '\n' or c == 32) {
                continue;
            }
            const char = try Character.init(scene, ally, self, .{
                .char = c,
                .shaders = info.shaders,
                .count = self.codepoints.items.len,
                .index = index,
                .pipeline = info.pipeline,
            });
            CharacterUniform.setUniformField(char.sprite.drawing, 1, .color, info.color);
            try self.characters.append(char);
        }

        try self.update();

        for (self.characters.items) |c| {
            CharacterUniform.setUniformField(c.sprite.drawing, 1, .count, @as(u32, @intCast(self.codepoints.items.len)));
        }
    }

    pub fn update(self: *Text) !void {
        if (self.characters.items.len == 0) return;
        var start: math.Vec2 = self.transform.translation;
        start[1] += self.line_spacing;

        const space_width: f32 = 10;

        var it = std.mem.splitScalar(u32, self.codepoints.items, ' ');

        var character_index: usize = 0;

        var height = self.line_spacing;

        while (it.next()) |word| {
            if (try self.getExtent(word) + start[0] > self.bounding_width + self.transform.translation[0] and self.codepoints.items.len != 0) {
                start = .{ self.transform.translation[0], start[1] + self.line_spacing };
                height += self.line_spacing;
            }

            for (word) |c| {
                if (c == '\n') {
                    start = .{ self.transform.translation[0], start[1] + self.line_spacing };
                    height += self.line_spacing;
                    continue;
                }

                var char = &self.characters.items[character_index];

                if (char.advance + start[0] > self.bounding_width + self.transform.translation[0]) {
                    start = .{ self.transform.translation[0], start[1] + self.line_spacing };
                    height += self.line_spacing;
                }

                char.sprite.transform.translation = start + char.offset - math.Vec2{ 0, @floatFromInt(char.image.height) };
                char.sprite.transform.scale = .{ @floatFromInt(char.image.width), @floatFromInt(char.image.height) };
                char.sprite.updateTransform();
                start += .{ char.advance, 0 };
                character_index += 1;
            }
            if (it.peek() != null) {
                start += .{ space_width, 0 };
            }
        }

        self.bounding_height = height;
    }

    pub fn deinit(self: *Text, ally: std.mem.Allocator) void {
        for (self.characters.items) |c| {
            c.deinit(ally);
        }
        self.characters.deinit();
        self.codepoints.deinit();
    }

    pub fn init(ally: std.mem.Allocator, path: [:0]const u8, size: f32, line_spacing: f32, bounding_width: f32) !Text {
        var face = try graphics.ft_lib.createFace(path, 0);
        try face.setCharSize(@intFromFloat(size * 64), 0, 0, 0);
        return .{
            .width = 0,
            .height = 0,
            .opacity = 1,
            .bounding_width = bounding_width,
            .bounding_height = size * line_spacing,
            .face = face,
            .size = size,
            .line_spacing = size * line_spacing,
            .characters = std.ArrayList(Character).init(ally),
            .codepoints = std.ArrayList(u32).init(ally),
            .transform = .{
                .scale = .{ 1, 1 },
                .rotation = .{ .angle = 0, .center = .{ 0.5, 0.5 } },
                .translation = .{ 0, 0 },
            },
        };
    }
};
