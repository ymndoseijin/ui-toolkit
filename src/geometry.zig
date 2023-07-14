const math = @import("math.zig");
const std = @import("std");
const testing = std.testing;

const Vec3 = math.Vec3;
const Vec2 = math.Vec2;

pub const Vertex = struct {
    pos: Vec3,
    uv: Vec2,
    pub const Zero = Vertex{ .pos = .{ 0, 0, 0 }, .uv = .{ 0, 0 } };
};

// potential footgun, face holds a pointer to vertices, so if you change it you might change it to other faces as well
pub const Face = struct {
    vertices: []*Vertex,

    pub fn init(alloc: std.mem.Allocator, vertices: []const *Vertex) !*Face {
        var face = try alloc.create(Face);
        face.vertices = try alloc.dupe(*Vertex, vertices);

        return face;
    }
};

pub const HalfEdge = struct {
    next: ?*HalfEdge,
    twin: ?*HalfEdge,

    vertex: *Vertex,
    face: *Face,

    pub fn makeTri(mut: *HalfEdge, allocator: std.mem.Allocator, tri: []const *Vertex) !void {
        var b = try allocator.create(HalfEdge);
        var c = try allocator.create(HalfEdge);

        mut.* = HalfEdge{
            .vertex = tri[0],
            .next = b,
            .twin = mut.twin, // temp
            .face = try Face.init(allocator, tri),
        };

        b.* = HalfEdge{
            .vertex = tri[1],
            .next = c,
            .twin = null,
            .face = try Face.init(allocator, tri),
        };
        c.* = HalfEdge{
            .vertex = tri[2],
            .next = mut,
            .twin = null,
            .face = try Face.init(allocator, tri),
        };
    }

    pub fn halfVert(self: HalfEdge) Vertex {
        if (self.next) |next_edge| {
            var a = self.vertex;
            var b = next_edge.vertex;
            const pos = (b.pos - a.pos) / @splat(3, @as(f32, 2)) + a.pos;
            const uv = (b.uv - a.uv) / @splat(2, @as(f32, 2)) + a.uv;
            return Vertex{ .pos = pos, .uv = uv };
        }
        return Vertex.Zero;
    }
};

pub const Mesh = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(alloc: std.mem.Allocator) Mesh {
        var arena = std.heap.ArenaAllocator.init(alloc);
        return Mesh{
            .arena = arena,
        };
    }

    pub fn deinit(self: *Mesh) void {
        self.arena.deinit();
    }

    pub fn syncEdges(a: *HalfEdge, b: *HalfEdge, twins: [2]*HalfEdge) void {
        if (twins[0].vertex == a.vertex) {
            std.debug.print("Setting as equal\n", .{});
            twins[0].twin = a;
            a.twin = twins[0];

            twins[1].twin = b;
            b.twin = twins[1];
        } else {
            std.debug.print("Setting as different\n", .{});
            twins[1].twin = a;
            a.twin = twins[1];

            twins[0].twin = b;
            b.twin = twins[0];
        }
    }

    pub const SubdivideEdge = enum {
        fucked,
        ok,
    };

    pub const SubdivideValue = struct { SubdivideEdge, [2]*HalfEdge };

    // only for triangles rn
    pub fn subdivide(self: *Mesh, half_edge: *HalfEdge, map: *std.AutoHashMap(?*HalfEdge, [2]*HalfEdge)) !void {
        const allocator = self.arena.allocator();
        var face: [3]*HalfEdge = .{ half_edge, half_edge.next.?, half_edge.next.?.next.? };

        inline for (face) |elem| {
            if (map.get(elem)) |_| {
                return;
            }
        }

        var a_vert: *Vertex = undefined;
        var b_vert: *Vertex = undefined;
        var c_vert: *Vertex = undefined;

        var new_verts = .{ &a_vert, &b_vert, &c_vert };

        inline for (new_verts, 0..) |vert, i| {
            if (map.get(face[i].twin)) |twins| {
                vert.* = twins[1].vertex;
            } else {
                vert.* = try allocator.create(Vertex);
                vert.*.* = face[i].halfVert();
            }
        }

        var inner_triangle = try allocator.create(HalfEdge);
        try inner_triangle.makeTri(allocator, &[_]*Vertex{ a_vert, b_vert, c_vert });

        try face[0].makeTri(allocator, &[_]*Vertex{ face[0].vertex, a_vert, c_vert });
        try face[1].makeTri(allocator, &[_]*Vertex{ face[1].vertex, b_vert, a_vert });
        try face[2].makeTri(allocator, &[_]*Vertex{ face[2].vertex, c_vert, b_vert });

        try map.put(face[0], .{ face[0], face[1].next.?.next.? });
        try map.put(face[1], .{ face[1], face[2].next.?.next.? });
        try map.put(face[2], .{ face[2], face[0].next.?.next.? });

        try map.put(face[0].next.?.next.?, .{ face[2], face[0].next.?.next.? });
        try map.put(face[1].next.?.next.?, .{ face[0], face[1].next.?.next.? });
        try map.put(face[2].next.?.next.?, .{ face[1], face[2].next.?.next.? });

        const faces_left = .{ face[0], face[1], face[2] };
        const faces_right = .{ face[1], face[2], face[0] };

        inline for (faces_left, faces_right) |left, right| {
            if (map.get(left.twin)) |twins| {
                Mesh.syncEdges(left, right.next.?.next.?, .{ twins[0], twins[1] });
            } else {
                if (left.twin) |twin| {
                    try self.subdivide(twin, map);
                }
            }
        }

        inner_triangle.next.?.next.?.twin = face[0].next;
        face[0].next.?.twin = inner_triangle.next.?.next;

        inner_triangle.next.?.twin = face[2].next;
        face[2].next.?.twin = inner_triangle.next;

        inner_triangle.twin = face[1].next;
        face[1].next.?.twin = inner_triangle;
    }

    const Pair = struct { usize, usize };
    const Format = struct {
        uv_offset: usize,
        pos_offset: usize,
        length: usize,
    };

    pub fn makeFrom(self: *Mesh, vertices: []const f32, in_indices: []const u32, comptime format: Format, comptime n: comptime_int) !*HalfEdge {
        const allocator = self.arena.allocator();

        var indices = try allocator.dupe(u32, in_indices);

        var seen = std.ArrayList(struct { Vec3, usize }).init(self.arena.allocator());
        defer seen.deinit();

        var converted = std.ArrayList(Vertex).init(self.arena.allocator());
        defer converted.deinit();

        for (0..@divExact(vertices.len, format.length)) |i| {
            var pos: Vec3 = .{
                vertices[i * format.length + format.pos_offset],
                vertices[i * format.length + format.pos_offset + 1],
                vertices[i * format.length + format.pos_offset + 2],
            };

            var uv: Vec2 = .{
                vertices[i * format.length + format.uv_offset],
                vertices[i * format.length + format.uv_offset + 1],
            };

            var copy = false;
            for (seen.items) |candidate| {
                if (@reduce(.And, candidate[0] == pos)) {
                    copy = true;
                    for (indices) |*mut| {
                        if (mut.* == i) {
                            mut.* = @intCast(candidate[1]);
                        }
                    }
                    break;
                }
            }
            if (!copy) {
                try seen.append(.{ pos, i });
            }

            try converted.append(.{
                .pos = pos,
                .uv = uv,
            });
        }

        var res = self.makeNgon(converted.items, indices, n);
        return res;
    }

    // this merges the vertices with the same pos rather than doing it properly
    pub fn makeNgon(self: *Mesh, in_vert: []const Vertex, indices: []const u32, comptime n: comptime_int) !*HalfEdge {
        const allocator = self.arena.allocator();

        var vertices = try allocator.dupe(Vertex, in_vert);

        var face = try allocator.create(Face);
        face.vertices = try allocator.alloc(*Vertex, n);
        var face_i: usize = 0;

        var half_edge: *HalfEdge = undefined;
        var start: *HalfEdge = undefined;

        var first_face: *HalfEdge = undefined;
        var first_index: usize = undefined;

        var begin = true;

        var map = std.AutoHashMap(Pair, *HalfEdge).init(allocator);
        defer map.deinit();

        for (indices, 0..) |index, i| {
            var current_vertex = &vertices[index];
            var next_or: ?usize = if (i < indices.len - 1) indices[i + 1] else null;

            var previous_edge = half_edge;
            half_edge = try allocator.create(HalfEdge);

            half_edge.vertex = current_vertex;

            half_edge.face = face;

            half_edge.next = null;
            half_edge.twin = null;

            face.vertices[face_i] = current_vertex;
            if (face_i == 0) {
                first_face = half_edge;
                first_index = index;
            } else {
                previous_edge.next = half_edge;
            }

            if (face_i == n - 1) {
                half_edge.next = first_face;
                next_or = first_index;

                previous_edge.next = half_edge;

                face = try allocator.create(Face);
                face.vertices = try allocator.alloc(*Vertex, n);

                face_i = 0;
            } else {
                face_i += 1;
            }

            if (begin) {
                begin = false;
                start = half_edge;
            }

            if (next_or) |next_vertex| {
                var key: Pair = if (index > next_vertex) .{ index, next_vertex } else .{ next_vertex, index };
                if (map.get(key)) |half_twin| {
                    if (half_twin.twin != null) {
                        return error.TooManyTwins;
                    }
                    half_twin.twin = half_edge;
                    half_edge.twin = half_twin;
                    //std.debug.print("\nFound twin at {d:.4} {any:.4}\n", .{ half_twin.vertex.pos, half_twin.twin });
                } else {
                    //std.debug.print("adding twin candidate at {any} {any}\n", .{ key, half_edge });
                    try map.put(key, half_edge);
                }
            }
        }

        return start;
    }
};

pub fn main() !void {
    var mesh = Mesh.init(@import("common.zig").allocator);
    defer mesh.deinit();

    var vertices = [_]Vertex{
        .{ .pos = .{ 0, 0, 0 } },
        .{ .pos = .{ 0, 1, 0 } },
        .{ .pos = .{ 0, 1, 1 } },
        .{ .pos = .{ 1, 1, 1 } },
    };

    var indices = [_]usize{ 0, 1, 2, 1, 2, 3 };

    std.debug.print("{}\n", .{try mesh.make(&vertices, &indices)});
}

test "half edge" {
    const ally = testing.allocator;
    var mesh = Mesh.init(ally);
    defer mesh.deinit();

    var vertices = [_]Vertex{
        .{ .pos = .{ 0, 0, 0 } },
        .{ .pos = .{ 0, 1, 0 } },
        .{ .pos = .{ 0, 1, 1 } },
        .{ .pos = .{ 1, 1, 1 } },
    };

    var indices = [_]usize{ 0, 1, 2, 1, 2, 3 };

    var edge: ?*HalfEdge = try mesh.make(&vertices, &indices);

    var i: usize = 0;
    while (edge) |actual| {
        std.debug.print("half edge at {}: {any:.4} {any:.4}\n", .{ i, actual.vertex.pos, actual.twin != null });
        edge = actual.next;
        i += 1;
    }
}
