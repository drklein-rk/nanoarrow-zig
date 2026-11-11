const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Link mode") orelse .static;
    const namespace_opt = b.option([]const u8, "namespace", "Namespace for nanoarrow") orelse null;
    const ipc_ext = b.option(bool, "ipc", "Build IPC libraries") orelse false;
    const ipc_with_zstd = b.option(bool, "ipc_with_zstd", "Build IPC libraries with zstd support") orelse false;
    const ipc_with_lz4 = b.option(bool, "ipc_with_lz4", "Build IPC libraries with lz4 support") orelse false;
    const device_ext = b.option(bool, "device", "Build device libraries") orelse false;
    const apps = b.option(bool, "apps", "Build apps (dump_stream)") orelse false;
    const upstream = b.dependency("upstream", .{});

    const nanoarrow_version = nanoarrowVersion();
    const nanoarrow_config_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/nanoarrow/nanoarrow_config.h.in") },
        .include_path = "nanoarrow/nanoarrow_config.h",
    }, .{
        .NANOARROW_VERSION_MAJOR = @as(i64, @intCast(nanoarrow_version.major)),
        .NANOARROW_VERSION_MINOR = @as(i64, @intCast(nanoarrow_version.minor)),
        .NANOARROW_VERSION_PATCH = @as(i64, @intCast(nanoarrow_version.patch)),
        .NANOARROW_VERSION = b.fmt("{f}", .{nanoarrow_version}),
        .NANOARROW_NAMESPACE_DEFINE = if (namespace_opt) |ns| b.fmt("#define NANOARROW_NAMESPACE {s}\n", .{ns}) else "// No namespace defined\n",
    });

    const nanoarrow_lib = b.addLibrary(.{
        .name = "nanoarrow",
        .linkage = linkage,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    nanoarrow_lib.root_module.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = &COMMON_LIB_FILES,
        .flags = &c_flags,
    });

    if (optimize == .debug) {
        nanoarrow_lib.root_module.addCMacro("NANOARROW_DEBUG", "1");
    }

    if (target.result.os.tag == .windows and linkage == .dynamic) {
        nanoarrow_lib.root_module.addCMacro("NANOARROW_BUILD_DLL", "1");
        nanoarrow_lib.root_module.addCMacro("NANOARROW_EXPORT_DLL", "1");
    }

    nanoarrow_lib.installHeader(upstream.path("src/nanoarrow/nanoarrow.h"), "nanoarrow/nanoarrow.h");
    nanoarrow_lib.installHeader(upstream.path("src/nanoarrow/nanoarrow.hpp"), "nanoarrow/nanoarrow.hpp");
    nanoarrow_lib.installHeadersDirectory(upstream.path("src/nanoarrow/common"), "nanoarrow/common", .{ .include_extensions = &.{".h"} });
    nanoarrow_lib.installHeadersDirectory(upstream.path("src/nanoarrow/hpp"), "nanoarrow/hpp", .{ .include_extensions = &.{".hpp"} });
    nanoarrow_lib.installConfigHeader(nanoarrow_config_h);
    nanoarrow_lib.root_module.addConfigHeader(nanoarrow_config_h);
    nanoarrow_lib.root_module.addIncludePath(upstream.path("src"));

    b.installArtifact(nanoarrow_lib);

    const translate_c = b.addTranslateC(.{
        .root_source_file = upstream.path("src/nanoarrow/nanoarrow.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(upstream.path("src"));
    translate_c.addConfigHeader(nanoarrow_config_h);
    const nanoarrow_mod = b.addModule("nanoarrow", .{
        .root_source_file = translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
    });
    nanoarrow_mod.linkLibrary(nanoarrow_lib);

    const smoke_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nanoarrow", .module = nanoarrow_mod }},
        }),
    });
    const test_step = b.step("test", "Run the Zig smoke test (examples/basic.zig)");
    test_step.dependOn(&b.addRunArtifact(smoke_test).step);

    if (device_ext) {
        const nanoarrow_device = b.addLibrary(.{
            .name = "nanoarrow_device",
            .linkage = linkage,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        nanoarrow_device.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &.{"nanoarrow/device/device.c"},
            .flags = &c_flags,
        });

        nanoarrow_device.root_module.linkLibrary(nanoarrow_lib);
        nanoarrow_device.root_module.addIncludePath(upstream.path("src"));
        nanoarrow_device.root_module.addConfigHeader(nanoarrow_config_h);
        if (optimize == .debug) nanoarrow_device.root_module.addCMacro("NANOARROW_DEBUG", "1");
        nanoarrow_device.installHeader(upstream.path("src/nanoarrow/nanoarrow_device.h"), "nanoarrow/nanoarrow_device.h");
        nanoarrow_device.installHeader(upstream.path("src/nanoarrow/nanoarrow_device.hpp"), "nanoarrow/nanoarrow_device.hpp");

        if (device_ext) b.installArtifact(nanoarrow_device);
    }

    if (ipc_ext or apps) {
        const flatcc = b.addLibrary(.{
            .name = "flatcc",
            .linkage = if (target.result.os.tag == .windows) .static else linkage,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        flatcc.root_module.addCSourceFiles(.{
            .root = upstream.path("thirdparty/flatcc/src"),
            .files = &FLATCC_LIB_FILES,
            .flags = &c_flags,
        });

        flatcc.root_module.addIncludePath(upstream.path("thirdparty/flatcc/include"));

        const nanoarrow_ipc = b.addLibrary(.{
            .name = "nanoarrow_ipc",
            .linkage = linkage,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });

        nanoarrow_ipc.root_module.addCSourceFiles(.{
            .root = upstream.path("src"),
            .files = &IPC_LIB_FILES,
            .flags = &c_flags,
        });

        nanoarrow_ipc.root_module.linkLibrary(nanoarrow_lib);
        nanoarrow_ipc.root_module.linkLibrary(flatcc);
        nanoarrow_ipc.root_module.addIncludePath(upstream.path("src"));
        nanoarrow_ipc.root_module.addIncludePath(upstream.path("thirdparty/flatcc/include"));
        nanoarrow_ipc.root_module.addConfigHeader(nanoarrow_config_h);
        if (optimize == .debug) nanoarrow_ipc.root_module.addCMacro("NANOARROW_DEBUG", "1");
        nanoarrow_ipc.installHeader(upstream.path("src/nanoarrow/nanoarrow_ipc.h"), "nanoarrow/nanoarrow_ipc.h");
        nanoarrow_ipc.installHeader(upstream.path("src/nanoarrow/nanoarrow_ipc.hpp"), "nanoarrow/nanoarrow_ipc.hpp");
        nanoarrow_ipc.installHeader(upstream.path("src/nanoarrow/ipc/flatcc_generated.h"), "nanoarrow/ipc/flatcc_generated.h");

        if (ipc_with_zstd) {
            if (b.lazyDependency("zstd", .{
                .target = target,
                .optimize = optimize,
            })) |zstd| {
                nanoarrow_ipc.root_module.linkLibrary(zstd.artifact("zstd"));
            }
            nanoarrow_ipc.root_module.addCMacro("NANOARROW_IPC_WITH_ZSTD", "1");
        }

        if (ipc_with_lz4) {
            if (b.lazyDependency("lz4", .{
                .target = target,
                .optimize = optimize,
            })) |lz4| {
                nanoarrow_ipc.root_module.linkLibrary(lz4.artifact("lz4"));
            }
            nanoarrow_ipc.root_module.addCMacro("NANOARROW_IPC_WITH_LZ4", "1");
        }

        if (ipc_ext or apps) b.installArtifact(nanoarrow_ipc);

        if (ipc_ext) {
            // nanoarrow_ipc.h includes nanoarrow.h, so this module also exposes the core API.
            const translate_ipc = b.addTranslateC(.{
                .root_source_file = upstream.path("src/nanoarrow/nanoarrow_ipc.h"),
                .target = target,
                .optimize = optimize,
            });
            translate_ipc.addIncludePath(upstream.path("src"));
            translate_ipc.addConfigHeader(nanoarrow_config_h);
            const nanoarrow_ipc_mod = b.addModule("nanoarrow_ipc", .{
                .root_source_file = translate_ipc.getOutput(),
                .target = target,
                .optimize = optimize,
            });
            nanoarrow_ipc_mod.linkLibrary(nanoarrow_ipc);

            const ipc_example = b.addTest(.{
                .root_module = b.createModule(.{
                    .root_source_file = b.path("examples/ipc.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{.{ .name = "nanoarrow_ipc", .module = nanoarrow_ipc_mod }},
                }),
            });
            test_step.dependOn(&b.addRunArtifact(ipc_example).step);
        }

        if (apps) {
            const dump_stream = b.addExecutable(.{
                .name = "dump_stream",
                .root_module = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                }),
            });

            dump_stream.root_module.addIncludePath(upstream.path("src"));
            dump_stream.root_module.addConfigHeader(nanoarrow_config_h);
            dump_stream.root_module.addCSourceFiles(.{
                .root = upstream.path("src"),
                .files = &.{"apps/dump_stream.c"},
                .flags = &c_flags,
            });

            dump_stream.root_module.linkLibrary(nanoarrow_ipc);
            b.installArtifact(dump_stream);
        }
    }
}

const common_flags = .{ "-Wall", "-Wextra" };
const c_flags = common_flags ++ .{"-std=c99"};

const COMMON_LIB_FILES = .{
    "nanoarrow/common/array.c",
    "nanoarrow/common/schema.c",
    "nanoarrow/common/array_stream.c",
    "nanoarrow/common/utils.c",
};

const IPC_LIB_FILES = .{
    "nanoarrow/ipc/codecs.c",
    "nanoarrow/ipc/decoder.c",
    "nanoarrow/ipc/encoder.c",
    "nanoarrow/ipc/reader.c",
    "nanoarrow/ipc/writer.c",
};

const FLATCC_LIB_FILES = .{
    "runtime/builder.c",
    "runtime/emitter.c",
    "runtime/refmap.c",
    "runtime/verifier.c",
};

/// Derives the packaged nanoarrow version from this package's own `.version` in build.zig.zon.
/// "X.Y.Z-N" (numeric suffix) is our revision of nanoarrow X.Y.Z; any other pre-release tag,
/// e.g. "0.10.0-SNAPSHOT", is nanoarrow's own and is kept as is.
fn nanoarrowVersion() std.SemanticVersion {
    var v = std.SemanticVersion.parse(@import("build.zig.zon").version) catch @panic("invalid .version in build.zig.zon");
    if (v.pre) |pre| {
        if (std.mem.findNone(u8, pre, "0123456789") == null) v.pre = null;
    }
    v.build = null;
    return v;
}
