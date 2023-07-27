const std = @import("std");
const math = @import("math");
const gl = @import("gl");
const img = @import("img");
const geometry = @import("geometry");
const graphics = @import("graphics.zig");
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

pub const Cube = struct {
    pub const vertices = [_]f32{
        0.0, 1.0, 0.0, 1.0,    0.5,  -0.0, 1.0,  -0.0,
        1.0, 1.0, 1.0, 0.6667, 0.75, -0.0, 1.0,  -0.0,
        1.0, 1.0, 0.0, 0.6667, 0.5,  -0.0, 1.0,  -0.0,
        1.0, 1.0, 1.0, 0.6667, 0.75, -0.0, -0.0, 1.0,
        0.0, 0.0, 1.0, 0.3333, 1.0,  -0.0, -0.0, 1.0,
        1.0, 0.0, 1.0, 0.3333, 0.75, -0.0, -0.0, 1.0,
        0.0, 1.0, 1.0, 0.6667, 0.0,  -1.0, -0.0, -0.0,
        0.0, 0.0, 0.0, 0.3333, 0.25, -1.0, -0.0, -0.0,
        0.0, 0.0, 1.0, 0.3333, 0.0,  -1.0, -0.0, -0.0,
        1.0, 0.0, 0.0, 0.3333, 0.5,  -0.0, -1.0, -0.0,
        0.0, 0.0, 1.0, -0.0,   0.75, -0.0, -1.0, -0.0,
        0.0, 0.0, 0.0, -0.0,   0.5,  -0.0, -1.0, -0.0,
        1.0, 1.0, 0.0, 0.6667, 0.5,  1.0,  -0.0, -0.0,
        1.0, 0.0, 1.0, 0.3333, 0.75, 1.0,  -0.0, -0.0,
        1.0, 0.0, 0.0, 0.3333, 0.5,  1.0,  -0.0, -0.0,
        0.0, 1.0, 0.0, 0.6667, 0.25, -0.0, -0.0, -1.0,
        1.0, 0.0, 0.0, 0.3333, 0.5,  -0.0, -0.0, -1.0,
        0.0, 0.0, 0.0, 0.3333, 0.25, -0.0, -0.0, -1.0,
        0.0, 1.0, 0.0, 1.0,    0.5,  -0.0, 1.0,  -0.0,
        0.0, 1.0, 1.0, 1.0,    0.75, -0.0, 1.0,  -0.0,
        1.0, 1.0, 1.0, 0.6667, 0.75, -0.0, 1.0,  -0.0,
        1.0, 1.0, 1.0, 0.6667, 0.75, -0.0, -0.0, 1.0,
        0.0, 1.0, 1.0, 0.6667, 1.0,  -0.0, -0.0, 1.0,
        0.0, 0.0, 1.0, 0.3333, 1.0,  -0.0, -0.0, 1.0,
        0.0, 1.0, 1.0, 0.6667, 0.0,  -1.0, -0.0, -0.0,
        0.0, 1.0, 0.0, 0.6667, 0.25, -1.0, -0.0, -0.0,
        0.0, 0.0, 0.0, 0.3333, 0.25, -1.0, -0.0, -0.0,
        1.0, 0.0, 0.0, 0.3333, 0.5,  -0.0, -1.0, -0.0,
        1.0, 0.0, 1.0, 0.3333, 0.75, -0.0, -1.0, -0.0,
        0.0, 0.0, 1.0, -0.0,   0.75, -0.0, -1.0, -0.0,
        1.0, 1.0, 0.0, 0.6667, 0.5,  1.0,  -0.0, -0.0,
        1.0, 1.0, 1.0, 0.6667, 0.75, 1.0,  -0.0, -0.0,
        1.0, 0.0, 1.0, 0.3333, 0.75, 1.0,  -0.0, -0.0,
        0.0, 1.0, 0.0, 0.6667, 0.25, -0.0, -0.0, -1.0,
        1.0, 1.0, 0.0, 0.6667, 0.5,  -0.0, -0.0, -1.0,
        1.0, 0.0, 0.0, 0.3333, 0.5,  -0.0, -0.0, -1.0,
    };

    pub var indices = [_]u32{
        0,  1,  2,
        3,  4,  5,
        6,  7,  8,
        9,  10, 11,
        12, 13, 14,
        15, 16, 17,
        18, 19, 20,
        21, 22, 23,
        24, 25, 26,
        27, 28, 29,
        30, 31, 32,
        33, 34, 35,
    };

    pub fn makeCube(drawing: *Drawing(.spatial), pos: Vec3) !graphics.SpatialMesh {
        var mesh = try graphics.SpatialMesh.init(drawing, pos, try graphics.Shader.setupShader(@embedFile("shaders/cube/vertex.glsl"), @embedFile("shaders/cube/fragment.glsl")));
        mesh.drawing.bindVertex(&Cube.vertices, &Cube.indices);
        return mesh;
    }
};
