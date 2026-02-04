const std = @import("std");

const Operation = enum {
    map,
    filter,
    take,
};

fn Pipeline(comptime T: type, comptime ops: anytype) type {
    return struct {
        allocator: std.mem.Allocator,
        items: []const T,

        const Self = @This();

        pub fn map(self: Self, comptime transform: anytype) Pipeline(T, ops ++ .{.{ .kind = Operation.map, .data = transform }}) {
            return .{
                .allocator = self.allocator,
                .items = self.items,
            };
        }

        pub fn filter(self: Self, comptime predicate: anytype) Pipeline(T, ops ++ .{.{ .kind = Operation.filter, .data = predicate }}) {
            return .{
                .allocator = self.allocator,
                .items = self.items,
            };
        }

        pub fn take(self: Self, comptime n: usize) Pipeline(T, ops ++ .{.{ .kind = Operation.take, .data = n }}) {
            return .{
                .allocator = self.allocator,
                .items = self.items,
            };
        }

        pub fn collect(self: Self) ![]T {
            if (ops.len == 0) {
                const result = try self.allocator.alloc(T, self.items.len);
                @memcpy(result, self.items);
                return result;
            }

            var result: std.ArrayList(T) = .empty;
            errdefer result.deinit(self.allocator);

            try result.ensureTotalCapacity(self.allocator, @min(self.items.len, 16));

            var take_counts: [ops.len]usize = undefined;
            inline for (0..ops.len) |i| {
                take_counts[i] = 0;
            }

            element_loop: for (self.items) |item| {
                var current = item;

                inline for (ops, 0..) |op, op_idx| {
                    switch (op.kind) {
                        Operation.map => {
                            current = applyTransform(T, op.data, current);
                        },
                        Operation.filter => {
                            if (!op.data.f(current)) {
                                continue :element_loop;
                            }
                        },
                        Operation.take => {
                            if (take_counts[op_idx] >= op.data) {
                                break :element_loop;
                            }
                            take_counts[op_idx] += 1;
                        },
                    }
                }
                try result.append(self.allocator, current);
            }
            return try result.toOwnedSlice(self.allocator);
        }
    };
}

fn applyTransform(comptime T: type, comptime transform: anytype, val: T) T {
    const transform_type_info = @typeInfo(@TypeOf(transform));
    if (transform_type_info == .@"struct" and transform_type_info.@"struct".is_tuple) {
        var result = val;
        inline for (transform) |t| {
            result = t.f(result);
        }
        return result;
    } else {
        return transform.f(val);
    }
}

pub fn pipeline(allocator: std.mem.Allocator) PipelineBuilder {
    return .{ .allocator = allocator };
}

const PipelineBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn from(self: PipelineBuilder, items: anytype) Pipeline(GetElementType(@TypeOf(items)), .{}) {
        return .{
            .allocator = self.allocator,
            .items = items,
        };
    }
};

fn GetElementType(comptime ItemsType: type) type {
    const info = @typeInfo(ItemsType);
    return switch (info) {
        .pointer => |ptr_info| switch (@typeInfo(ptr_info.child)) {
            .array => |array_info| array_info.child,
            else => ptr_info.child,
        },
        .array => |array_info| array_info.child,
        else => @compileError("Expected array or pointer type"),
    };
}

fn mul(comptime factor: anytype) type {
    return struct {
        pub fn f(x: anytype) @TypeOf(x) {
            return x * @as(@TypeOf(x), factor);
        }
    };
}

fn add(comptime amount: anytype) type {
    return struct {
        pub fn f(x: anytype) @TypeOf(x) {
            return x + @as(@TypeOf(x), amount);
        }
    };
}

fn sub(comptime amount: anytype) type {
    return struct {
        pub fn f(x: anytype) @TypeOf(x) {
            return x - @as(@TypeOf(x), amount);
        }
    };
}

fn div(comptime divisor: anytype) type {
    return struct {
        pub fn f(x: anytype) @TypeOf(x) {
            return @divTrunc(x, @as(@TypeOf(x), divisor));
        }
    };
}

fn gt(comptime threshold: anytype) type {
    return struct {
        pub fn f(x: anytype) bool {
            return x > threshold;
        }
    };
}

fn lt(comptime threshold: anytype) type {
    return struct {
        pub fn f(x: anytype) bool {
            return x < threshold;
        }
    };
}

fn even() type {
    return struct {
        pub fn f(x: anytype) bool {
            return @mod(x, 2) == 0;
        }
    };
}

fn odd() type {
    return struct {
        pub fn f(x: anytype) bool {
            return @mod(x, 2) != 0;
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    {
        const result = try pipeline(allocator)
            .from(&[_]i32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
            .filter(odd())
            .map(.{ add(1), add(2) })
            .take(3)
            .map(mul(10))
            .collect();
        defer allocator.free(result);

        for (result) |r| std.debug.print("{} ", .{r});
        std.debug.print("\n", .{});
    }
}
