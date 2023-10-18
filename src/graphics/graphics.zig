// TODO: remove pub
pub const glfw = @cImport({
    @cInclude("GLFW/glfw3.h");
});

const AREA_SIZE = 512;

const img = @import("img");
const common = @import("common");
const gl = @import("gl");
const std = @import("std");
const math = @import("math");
const freetype = @import("freetype");

pub const Cube = @import("elems/cube.zig").Cube;
pub const Line = @import("elems/line.zig").Line;
pub const Grid = @import("elems/grid.zig").makeGrid;
pub const Axis = @import("elems/axis.zig").makeAxis;
pub const Camera = @import("elems/camera.zig").Camera;
pub const TextBdf = @import("elems/textbdf.zig").Text;
pub const TextFt = @import("elems/textft.zig").Text;
pub const Sprite = @import("elems/sprite.zig").Sprite;
pub const ColoredRect = @import("elems/color_rect.zig").ColoredRect;

pub const MeshBuilder = @import("meshbuilder.zig").MeshBuilder;
pub const SpatialMesh = @import("spatialmesh.zig").SpatialMesh;
pub const ObjParse = @import("obj.zig").ObjParse;
pub const ComptimeMeshBuilder = @import("comptime_meshbuilder.zig").ComptimeMeshBuilder;

pub const Transform2D = struct {
    scale: math.Vec2,
    rotation: struct { angle: f32, center: math.Vec2 },
    translation: math.Vec2,
    pub fn getMat(self: Transform2D) math.Mat3 {
        return math.transform2D(f32, self.scale, self.rotation, self.translation);
    }
    pub fn getInverseMat(self: Transform2D) math.Mat3 {
        return math.transform2D(f32, math.Vec2{ 1, 1 } / self.scale, .{ .angle = -self.rotation.angle, .center = self.rotation.center }, math.Vec2{ -1, -1 } * self.translation);
    }
    pub fn apply(self: Transform2D, v: math.Vec2) math.Vec2 {
        var res: [3]f32 = self.getMat().dot(.{ v[0], v[1], 1 });
        return res[0..2].*;
    }

    pub fn reverse(self: Transform2D, v: math.Vec2) math.Vec2 {
        var res: [3]f32 = self.getInverseMat().dot(.{ v[0], v[1], 1 });
        return res[0..2].*;
    }
};

const Uniform1f = struct {
    name: [:0]const u8,
    value: *f32,
};

const Uniform3f = struct {
    name: [:0]const u8,
    value: *math.Vec3,
};

const Uniform3fv = struct {
    name: [:0]const u8,
    value: *math.Mat3,
};

const Uniform4fv = struct {
    name: [:0]const u8,
    value: *math.Mat4,
};

pub const Image = struct {
    width: u32,
    height: u32,
    data: []img.color.Rgba32,
};

pub const TextureInfo = struct {
    const FilterEnum = enum {
        nearest,
        linear,

        pub fn getGL(self: FilterEnum) i32 {
            switch (self) {
                .nearest => return gl.NEAREST,
                .linear => return gl.LINEAR,
            }
        }
    };
    const TextureType = enum {
        cubemap,
        flat,

        pub fn getGL(self: TextureType) u32 {
            switch (self) {
                .cubemap => return gl.TEXTURE_CUBE_MAP,
                .flat => return gl.TEXTURE_2D,
            }
        }
    };

    texture_type: TextureType,
    mag_filter: FilterEnum,
    min_filter: FilterEnum,
};

pub const Texture = struct {
    texture_id: u32,
    info: TextureInfo,

    pub fn init(info: TextureInfo) Texture {
        var texture_id: u32 = undefined;
        gl.genTextures(1, &texture_id);

        const texture_type = info.texture_type.getGL();

        gl.bindTexture(texture_type, texture_id);

        gl.texParameteri(texture_type, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
        gl.texParameteri(texture_type, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);

        gl.texParameteri(texture_type, gl.TEXTURE_MIN_FILTER, info.mag_filter.getGL());
        gl.texParameteri(texture_type, gl.TEXTURE_MAG_FILTER, info.min_filter.getGL());

        return .{
            .texture_id = texture_id,
            .info = info,
        };
    }

    pub fn setFromRgba(self: Texture, rgba: anytype, flip: bool) !void {
        const texture_type = self.info.texture_type.getGL();
        gl.bindTexture(texture_type, self.texture_id);
        if (flip) {
            var flipped: @TypeOf(rgba.data) = try common.allocator.dupe(@TypeOf(rgba.data[0]), rgba.data);
            defer common.allocator.free(flipped);
            for (0..rgba.height) |i| {
                for (0..rgba.width) |j| {
                    const pix = rgba.data[(rgba.height - i - 1) * rgba.width + j];
                    flipped[i * rgba.width + j] = pix;
                }
            }

            gl.texImage2D(texture_type, 0, gl.RGBA8, @intCast(rgba.width), @intCast(rgba.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &flipped[0]);
        } else {
            gl.texImage2D(texture_type, 0, gl.RGBA8, @intCast(rgba.width), @intCast(rgba.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &rgba.data[0]);
        }
    }
};

pub const Shader = struct {
    program: u32,
    const Self = Shader;

    pub fn setUniformFloat(self: *Self, name: [:0]const u8, value: f32) void {
        gl.useProgram(self.program);
        const loc: i32 = gl.getUniformLocation(self.program, name);
        gl.uniform1f(loc, value);
    }

    pub fn setUniformVec3(self: *Self, name: [:0]const u8, value: math.Vec3) void {
        gl.useProgram(self.program);
        const loc: i32 = gl.getUniformLocation(self.program, name);
        gl.uniform3f(loc, value[0], value[1], value[2]);
    }

    pub fn setUniformVec4(self: *Self, name: [:0]const u8, value: math.Vec4) void {
        gl.useProgram(self.program);
        const loc: i32 = gl.getUniformLocation(self.program, name);
        gl.uniform4f(loc, value[0], value[1], value[2], value[3]);
    }

    pub fn setUniformMat3(self: *Self, name: [:0]const u8, value: math.Mat3) void {
        gl.useProgram(self.program);
        const loc: i32 = gl.getUniformLocation(self.program, name);

        gl.uniformMatrix3fv(loc, 1, gl.FALSE, &value.columns[0][0]);
    }

    pub fn setUniformMat4(self: *Self, name: [:0]const u8, value: math.Mat4) void {
        gl.useProgram(self.program);
        const loc: i32 = gl.getUniformLocation(self.program, name);
        gl.uniformMatrix4fv(loc, 1, gl.FALSE, &value.columns[0][0]);
    }

    pub fn compileShader(comptime source: [:0]const u8, shader_type: gl.Enum) !Shader {
        const shader: u32 = gl.createShader(shader_type);

        const version_idx = comptime std.mem.indexOf(u8, source, "\n").?;
        const processed_source = source[0..version_idx] ++ "\n" ++ @embedFile("common.glsl") ++ source[version_idx..];
        gl.shaderSource(shader, 1, @ptrCast(&processed_source), null);
        gl.compileShader(shader);
        var response: i32 = 1;
        gl.getShaderiv(shader, gl.COMPILE_STATUS, &response);

        var infoLog: [512]u8 = undefined;
        if (response <= 0) {
            gl.getShaderInfoLog(shader, 512, null, &infoLog[0]);
            std.debug.print("Couldn't compile {s} from source: {s} file\n", .{ processed_source, infoLog });
            std.os.exit(255);
        }

        return .{
            .program = shader,
        };
    }

    pub fn linkShaders(shaders: []const Shader) !Shader {
        const program: u32 = gl.createProgram();

        for (shaders) |shader| {
            gl.attachShader(program, shader.program);
        }

        gl.linkProgram(program);

        var response: i32 = 1;
        gl.getShaderiv(program, gl.LINK_STATUS, &response);
        var infoLog: [4096]u8 = undefined;
        if (response <= 0) {
            gl.getShaderInfoLog(program, 512, null, &infoLog[0]);
            std.debug.print("Couldn't compile from source: {s}\n", .{infoLog});
            std.os.exit(255);
        }

        for (shaders) |shader| {
            gl.deleteShader(shader.program);
        }

        return .{
            .program = program,
        };
    }

    pub fn setupShader(comptime vertex_path: [:0]const u8, comptime fragment_path: [:0]const u8) !Shader {
        const vertex = try compileShader(vertex_path, gl.VERTEX_SHADER);
        const fragment = try compileShader(fragment_path, gl.FRAGMENT_SHADER);

        return try linkShaders(&[_]Shader{ vertex, fragment });
    }
};

pub fn Scene(comptime pipelines_union: anytype) type {
    const DrawingList = common.FieldArrayList(pipelines_union);
    return struct {
        drawing_array: DrawingList,

        const Self = @This();
        pub fn init() !Self {
            return Self{
                .drawing_array = try DrawingList.init(common.allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            inline for (DrawingList.Enums) |field| {
                for (self.drawing_array.array(field).items) |elem| {
                    elem.deinit();
                    common.allocator.destroy(elem);
                }
            }

            self.drawing_array.deinit(common.allocator);
        }

        pub fn fieldFromPipeline(comptime pipeline: RenderPipeline) DrawingList.Field {
            for (DrawingList.Enums) |field| {
                const res = comptime std.meta.eql(@typeInfo(DrawingList.FieldType(field)).Pointer.child.Pipeline, pipeline);
                if (res) return field;
            }
            @compileError("Pipeline not in Scene.");
        }

        pub fn new(self: *Self, comptime pipeline: RenderPipeline) !*Drawing(pipeline) {
            const render = comptime fieldFromPipeline(pipeline);
            var val = try common.allocator.create(@typeInfo(DrawingList.FieldType(render)).Pointer.child);
            try self.drawing_array.array(render).append(val);
            return val;
        }

        pub fn delete(self: *Self, drawing: anytype) !void {
            const T = @TypeOf(drawing);
            const field = comptime fieldFromPipeline(@typeInfo(T).Pointer.child.Pipeline);
            var arr = self.drawing_array.array(field);
            const idx = std.mem.indexOfScalar(T, arr.items, drawing) orelse return error.DeletedDrawingNotInScene;

            var rem = arr.swapRemove(idx);

            rem.deinit();
            common.allocator.destroy(rem);

            return;
        }

        pub fn draw(self: *Self, win: Window) !void {
            inline for (DrawingList.Enums) |field| {
                for (self.drawing_array.array(field).items) |*elem| {
                    try elem.*.draw(win);
                }
            }
        }
    };
}

const RenderType = enum {
    line,
    triangle,
};

const VertexAttribute = struct {
    attribute: enum {
        float,
        short,

        pub fn getType(comptime self: @This()) type {
            switch (self) {
                .float => return f32,
                .short => return i16,
            }
        }

        pub fn getGL(self: @This()) c_uint {
            switch (self) {
                .float => return gl.FLOAT,
                .short => return gl.SHORT,
            }
        }
    } = .float,
    size: comptime_int,
};

const CullType = enum {
    front,
    back,
    front_and_back,
};

const Framebuffer = struct {
    framebuffer_id: u32,
    shader_id: u32,
};

const RenderPipeline = struct {
    vertex_attrib: []const VertexAttribute,
    render_type: RenderType,
    depth_test: bool,
    cull_face: bool,
    cull_type: CullType = .back,
    framebuffer: ?[]Framebuffer = null,

    pub fn getAttributeType(comptime pipeline: RenderPipeline) type {
        var types: []const type = &.{};
        for (pipeline.vertex_attrib) |attrib| {
            const t = attrib.attribute.getType();
            for (0..attrib.size) |_| types = types ++ .{t};
        }
        return std.meta.Tuple(types);
    }
};

pub const FlatPipeline = RenderPipeline{
    .vertex_attrib = &[_]VertexAttribute{ .{ .size = 3 }, .{ .size = 2 } },
    .render_type = .triangle,
    .depth_test = false,
    .cull_face = false,
};

pub const SpatialPipeline = RenderPipeline{
    .vertex_attrib = &[_]VertexAttribute{ .{ .size = 3 }, .{ .size = 2 }, .{ .size = 3 } },
    .render_type = .triangle,
    .depth_test = true,
    .cull_face = false,
};

pub const LinePipeline = RenderPipeline{
    .vertex_attrib = &[_]VertexAttribute{ .{ .size = 3 }, .{ .size = 3 } },
    .render_type = .line,
    .depth_test = true,
    .cull_face = false,
};

pub fn Drawing(comptime pipeline: RenderPipeline) type {
    return struct {
        vao: u32,
        vbo: u32,
        ebo: u32,
        shader: Shader,

        uniform1f_array: std.ArrayList(Uniform1f),
        uniform3f_array: std.ArrayList(Uniform3f),

        uniform3fv_array: std.ArrayList(Uniform3fv),
        uniform4fv_array: std.ArrayList(Uniform4fv),

        textures: std.ArrayList(u32),
        cube_textures: std.ArrayList(u32),

        vert_count: usize,

        const Self = @This();
        pub const Pipeline = pipeline;
        pub const Attribute = pipeline.getAttributeType();

        pub fn addUniformFloat(self: *Self, name: [:0]const u8, f: *f32) !void {
            try self.uniform1f_array.append(.{ .name = name, .value = f });
        }

        pub fn addUniformVec3(self: *Self, name: [:0]const u8, v: *math.Vec3) !void {
            try self.uniform3f_array.append(.{ .name = name, .value = v });
        }

        pub fn addUniformMat4(self: *Self, name: [:0]const u8, m: *math.Mat4) !void {
            try self.uniform4fv_array.append(.{ .name = name, .value = m });
        }

        pub fn addUniformMat3(self: *Self, name: [:0]const u8, m: *math.Mat3) !void {
            try self.uniform3fv_array.append(.{ .name = name, .value = m });
        }

        pub fn init(shader: Shader) Self {
            var drawing: Self = undefined;

            drawing.shader = shader;

            gl.genVertexArrays(1, &drawing.vao);
            gl.genBuffers(1, &drawing.vbo);
            gl.genBuffers(1, &drawing.ebo);

            drawing.uniform1f_array = std.ArrayList(Uniform1f).init(common.allocator);
            drawing.uniform3f_array = std.ArrayList(Uniform3f).init(common.allocator);
            drawing.uniform3fv_array = std.ArrayList(Uniform3fv).init(common.allocator);
            drawing.uniform4fv_array = std.ArrayList(Uniform4fv).init(common.allocator);

            drawing.cube_textures = std.ArrayList(u32).init(common.allocator);
            drawing.textures = std.ArrayList(u32).init(common.allocator);

            drawing.vert_count = 0;

            return drawing;
        }

        pub fn deinit(self: *Self) void {
            self.uniform1f_array.deinit();
            self.uniform3f_array.deinit();
            self.uniform3fv_array.deinit();
            self.uniform4fv_array.deinit();

            self.textures.deinit();
            self.cube_textures.deinit();
        }

        const cubemapOrientation = enum { xp, yp, zp, xm, ym, zm };

        pub fn cubemapFromRgba(self: *Self, sides: anytype, width: usize, height: usize) !void {
            var texture_id: u32 = undefined;
            gl.genTextures(1, &texture_id);
            gl.bindTexture(gl.TEXTURE_CUBE_MAP, texture_id);

            gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
            gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
            gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

            inline for (sides, 0..) |data, i| {
                gl.texImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + i, 0, gl.RGBA8, @intCast(width), @intCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &data.data[0]);
            }

            //gl.generateMipmap(gl.TEXTURE_2D);

            try self.cube_textures.append(texture_id);
        }

        pub fn getIthTexture(comptime T: type, i: usize) !T {
            if (i > 31) return error.TooManyTextures;
            return @intCast(0x84C0 + i);
        }

        pub fn addTexture(self: *Self, texture: Texture) !void {
            switch (texture.info.texture_type) {
                .flat => try self.textures.append(texture.texture_id),
                .cubemap => try self.cube_textures.append(texture.texture_id),
            }
        }

        pub fn textureFromPath(self: *Self, path: []const u8) !struct { usize, usize } {
            var read_image = try img.Image.fromFilePath(common.allocator, path);
            defer read_image.deinit();

            switch (read_image.pixels) {
                .rgba32 => |data| {
                    const tex = Texture.init(.{ .mag_filter = .linear, .min_filter = .linear, .texture_type = .flat });
                    try tex.setFromRgba(.{
                        .width = read_image.width,
                        .height = read_image.height,
                        .data = data,
                    }, true);

                    try self.addTexture(tex);
                },
                else => return error.InvalidImage,
            }

            return .{ read_image.width, read_image.height };
        }

        pub fn bindVertex(self: *Self, vertices: []const Attribute, indices: []const u32) void {
            gl.bindVertexArray(self.vao);

            gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
            gl.bufferData(gl.ARRAY_BUFFER, @intCast(@sizeOf(Attribute) * vertices.len), &vertices[0], gl.STATIC_DRAW);

            gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, self.ebo);
            gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @intCast(@sizeOf(u32) * indices.len), &indices[0], gl.STATIC_DRAW);

            self.vert_count = indices.len;

            gl.bindVertexArray(self.vao);

            var sum_size: usize = 0;
            inline for (pipeline.vertex_attrib) |attrib| {
                sum_size += attrib.size * @sizeOf(attrib.attribute.getType());
            }

            var offset: usize = 0;
            inline for (pipeline.vertex_attrib, 0..) |attrib, i| {
                gl.vertexAttribPointer(i, attrib.size, attrib.attribute.getGL(), gl.FALSE, @intCast(sum_size), @ptrFromInt(offset));
                gl.enableVertexAttribArray(i);
                offset += attrib.size * @sizeOf(attrib.attribute.getType());
            }
        }

        pub fn draw(self: *Self, window: Window) !void {
            if (pipeline.depth_test) {
                gl.enable(gl.DEPTH_TEST);
            } else {
                gl.disable(gl.DEPTH_TEST);
            }

            if (pipeline.cull_face) {
                gl.enable(gl.CULL_FACE);
                switch (pipeline.cull_type) {
                    .back => gl.cullFace(gl.BACK),
                    .front => gl.cullFace(gl.FRONT),
                    .front_and_back => gl.cullFace(gl.FRONT_AND_BACK),
                }
            } else {
                gl.disable(gl.CULL_FACE);
            }

            if (pipeline.framebuffer) |framebuffer| {
                gl.bindFramebuffer(gl.FRAMEBUFFER, framebuffer.id);
            } else {
                gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
            }

            gl.useProgram(self.shader.program);
            const time = @as(f32, @floatCast(glfw.glfwGetTime()));
            const now: f32 = 2 * time;

            const resolutionLoc: i32 = gl.getUniformLocation(self.shader.program, "in_resolution");
            gl.uniform2f(resolutionLoc, @floatFromInt(window.viewport_width), @floatFromInt(window.viewport_height));

            const timeUniformLoc: i32 = gl.getUniformLocation(self.shader.program, "time");
            gl.uniform1f(timeUniformLoc, now);

            for (self.uniform1f_array.items) |uni| {
                const loc: i32 = gl.getUniformLocation(self.shader.program, uni.name);
                gl.uniform1f(loc, uni.value.*);
            }

            for (self.uniform3f_array.items) |uni| {
                const loc: i32 = gl.getUniformLocation(self.shader.program, uni.name);
                gl.uniform3f(loc, uni.value[0], uni.value[1], uni.value[2]);
            }

            for (self.uniform4fv_array.items) |uni| {
                const loc: i32 = gl.getUniformLocation(self.shader.program, uni.name);
                gl.uniformMatrix4fv(loc, 1, gl.FALSE, &uni.value.columns[0][0]);
            }

            for (self.uniform3fv_array.items) |uni| {
                const loc: i32 = gl.getUniformLocation(self.shader.program, uni.name);

                gl.uniformMatrix3fv(loc, 1, gl.FALSE, &uni.value.columns[0][0]);
            }

            for (self.cube_textures.items, 0..) |texture, index| {
                gl.activeTexture(try getIthTexture(c_uint, index));
                gl.bindTexture(gl.TEXTURE_CUBE_MAP, texture);

                //const textureUniformLoc: i32 = gl.getUniformLocation(self.shader.program, "texture0");
                //gl.uniform1i(textureUniformLoc, 0);
            }

            for (self.textures.items, 0..) |texture, index| {
                gl.activeTexture(try getIthTexture(c_uint, index));
                gl.bindTexture(gl.TEXTURE_2D, texture);

                var buff: [64]u8 = undefined;
                const res = try std.fmt.bufPrintZ(&buff, "texture{}", .{index});
                const textureUniformLoc: i32 = gl.getUniformLocation(self.shader.program, res);
                gl.uniform1i(textureUniformLoc, @intCast(index));
            }

            gl.bindVertexArray(self.vao);

            switch (pipeline.render_type) {
                .triangle => gl.drawElements(gl.TRIANGLES, @intCast(self.vert_count), gl.UNSIGNED_INT, null),
                .line => gl.drawElements(gl.LINES, @intCast(self.vert_count), gl.UNSIGNED_INT, null),
            }

            inline for (0..pipeline.vertex_attrib.len) |i| {
                gl.bindVertexArray(i);
            }
        }
    };
}

var gl_dispatch_table: gl.DispatchTable = undefined;

pub const GLProc = *const fn () callconv(.C) void;
pub fn getProcAddress(proc_name: [*:0]const u8) callconv(.C) ?GLProc {
    if (glfw.glfwGetProcAddress(proc_name)) |proc_address| return proc_address;
    return null;
}

const MapType = struct {
    *anyopaque,
    *Window,
};

var windowMap: ?std.AutoHashMap(*glfw.GLFWwindow, MapType) = null;

pub var ft_lib: freetype.Library = undefined;

pub fn initGraphics() !void {
    if (glfw.glfwInit() == glfw.GLFW_FALSE) return GlfwError.FailedGlfwInit;

    windowMap = std.AutoHashMap(*glfw.GLFWwindow, MapType).init(common.allocator);

    glfw.glfwWindowHint(glfw.GLFW_SAMPLES, 4); // 4x antialiasing
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 4); // We want OpenGL 3.3
    glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 6);
    glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE); // We don't want the old OpenGL

    ft_lib = try freetype.Library.init();
}

pub fn deinitGraphics() void {
    windowMap.?.deinit();
    ft_lib.deinit();
}

const GlfwError = error{
    FailedGlfwInit,
    FailedGlfwWindow,
};

pub const Square = struct {
    pub const vertices = [_]f32{
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
        1.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0,
    };
    pub const indices = [_]u32{
        0, 1, 2, 2, 3, 0,
    };
};

pub fn getGlfwCursorPos(win_or: ?*glfw.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        if (win.events.cursor_func) |fun| {
            fun(map[0], xpos, ypos) catch {
                @panic("error!");
            };
        }
    }
}

pub const Action = enum(i32) {
    release = 0,
    press = 1,
    repeat = 2,
};

pub fn getGlfwMouseButton(win_or: ?*glfw.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        if (win.events.mouse_func) |fun| {
            fun(map[0], button, @enumFromInt(action), mods) catch {
                @panic("error!");
            };
        }
    }
}

pub fn getGlfwKey(win_or: ?*glfw.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        if (win.events.key_func) |fun| {
            fun(map[0], key, scancode, @enumFromInt(action), mods) catch {
                @panic("error!");
            };
        }
    }
}

pub fn getGlfwChar(win_or: ?*glfw.GLFWwindow, codepoint: c_uint) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        if (win.events.char_func) |fun| {
            fun(map[0], codepoint) catch {
                @panic("error!");
            };
        }
    }
}

pub fn getFramebufferSize(win_or: ?*glfw.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        gl.viewport(0, 0, width, height);

        win.frame_width = width;
        win.frame_height = 1080;

        if (win.events.frame_func) |fun| {
            fun(map[0], width, height) catch {
                @panic("error!");
            };
        }
    }
}

pub fn getScroll(win_or: ?*glfw.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.C) void {
    const glfw_win = win_or orelse return;

    if (windowMap.?.get(glfw_win)) |map| {
        var win = map[1];
        if (win.events.scroll_func) |fun| {
            fun(map[0], xoffset, yoffset) catch {
                @panic("error!");
            };
        }
    }
}

pub fn waitGraphicsEvent() void {
    glfw.glfwPollEvents();
}

pub const EventTable = struct {
    key_func: ?*const fn (*anyopaque, i32, i32, Action, i32) anyerror!void,
    char_func: ?*const fn (*anyopaque, u32) anyerror!void,
    frame_func: ?*const fn (*anyopaque, i32, i32) anyerror!void,
    scroll_func: ?*const fn (*anyopaque, f64, f64) anyerror!void,
    mouse_func: ?*const fn (*anyopaque, i32, Action, i32) anyerror!void,
    cursor_func: ?*const fn (*anyopaque, f64, f64) anyerror!void,
};

pub const WindowInfo = struct {
    width: i32 = 256,
    height: i32 = 256,
    resizable: bool = true,
    name: [:0]const u8 = "default name",
};

pub const Window = struct {
    glfw_win: *glfw.GLFWwindow,
    alive: bool,
    frame_width: i32,
    frame_height: i32,

    viewport_width: i32,
    viewport_height: i32,

    events: EventTable,

    pub fn setScrollCallback(self: *Window, fun: *const fn (*anyopaque, f64, f64) anyerror!void) void {
        self.events.scroll_func = fun;
    }

    pub fn setKeyCallback(self: *Window, fun: *const fn (*anyopaque, i32, i32, Action, i32) anyerror!void) void {
        self.events.key_func = fun;
    }

    pub fn setCharCallback(self: *Window, fun: *const fn (*anyopaque, u32) anyerror!void) void {
        self.events.char_func = fun;
    }

    pub fn setFrameCallback(self: *Window, fun: *const fn (*anyopaque, i32, i32) anyerror!void) void {
        self.events.frame_func = fun;
    }

    pub fn setMouseButtonCallback(self: *Window, fun: *const fn (*anyopaque, i32, Action, i32) anyerror!void) void {
        self.events.mouse_func = fun;
    }

    pub fn setCursorCallback(self: *Window, fun: *const fn (*anyopaque, f64, f64) anyerror!void) void {
        self.events.cursor_func = fun;
    }

    pub fn addToMap(self: *Window, elem: *anyopaque) !void {
        try windowMap.?.put(self.glfw_win, .{ elem, self });
    }

    pub fn setSize(self: Window, width: u32, height: u32) void {
        glfw.glfwSetWindowSize(self.glfw_win, @intCast(width), @intCast(height));
    }

    pub fn init(info: WindowInfo) !*Window {
        var win = try common.allocator.create(Window);
        win.* = try initBare(info);
        try win.addToMap(win);
        return win;
    }

    pub fn initBare(info: WindowInfo) !Window {
        glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, if (info.resizable) glfw.GLFW_TRUE else glfw.GLFW_FALSE);
        const win_or = glfw.glfwCreateWindow(info.width, info.height, info.name, null, null);

        const glfw_win = win_or orelse return GlfwError.FailedGlfwWindow;

        glfw.glfwMakeContextCurrent(glfw_win);
        glfw.glfwSetWindowAspectRatio(glfw_win, 16, 9);
        _ = glfw.glfwSetKeyCallback(glfw_win, getGlfwKey);
        _ = glfw.glfwSetCharCallback(glfw_win, getGlfwChar);
        _ = glfw.glfwSetFramebufferSizeCallback(glfw_win, getFramebufferSize);
        _ = glfw.glfwSetMouseButtonCallback(glfw_win, getGlfwMouseButton);
        _ = glfw.glfwSetCursorPosCallback(glfw_win, getGlfwCursorPos);
        _ = glfw.glfwSetScrollCallback(glfw_win, getScroll);

        if (!gl_dispatch_table.init(getProcAddress)) return error.GlInitFailed;

        gl.makeDispatchTableCurrent(&gl_dispatch_table);

        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

        const events: EventTable = .{
            .key_func = null,
            .char_func = null,
            .scroll_func = null,
            .frame_func = null,
            .mouse_func = null,
            .cursor_func = null,
        };

        return Window{
            .glfw_win = glfw_win,
            .events = events,
            .alive = true,
            .viewport_width = info.width,
            .frame_width = info.width,
            .viewport_height = info.height,
            .frame_height = info.height,
        };
    }

    pub fn deinit(self: *Window) void {
        glfw.glfwDestroyWindow(self.glfw_win);
        gl.makeDispatchTableCurrent(null);
        glfw.glfwTerminate();
        common.allocator.destroy(self);
    }
};
