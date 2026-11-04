# nanoarrow-zig

[Apache Arrow nanoarrow](https://github.com/apache/arrow-nanoarrow) (v0.9.0) built with the
[Zig build system](https://ziglang.org/learn/build-system/), packaged so it can be used as a
dependency from Zig **and** C projects. No CMake required.

This repository contains only the build logic. The nanoarrow sources are fetched from the
upstream release tarball (see `build.zig.zon`).

Requires **Zig 0.17.0 or newer**.

## Features

| Component | Option | Default |
|-----------|--------|---------|
| `libnanoarrow` (core C library) | always | on |
| `libnanoarrow_ipc` + bundled flatcc (Arrow IPC) | `-Dipc` | off |
| IPC compression with zstd / lz4 | `-Dipc_with_zstd`, `-Dipc_with_lz4` | off |
| `libnanoarrow_device` | `-Ddevice` | off |
| `dump_stream` app | `-Dapps` | off |

Other options: `-Dlinkage=static|dynamic` (default `static`), `-Dnamespace=<Name>` (sets
`NANOARROW_NAMESPACE` to avoid symbol clashes), plus the standard `-Dtarget` and `-Doptimize`.

Not covered yet: Metal/CUDA device backends, the nanoarrow testing extension and the upstream
C++ test suite.

## Build

```sh
zig build                                   # libnanoarrow only
zig build -Dipc -Ddevice -Dapps             # everything
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
```

Libraries and headers (including the generated `nanoarrow/nanoarrow_config.h`) are installed to
`zig-out/lib` and `zig-out/include`.

## Use as a dependency

```sh
zig fetch --save git+https://github.com/drklein-rk/nanoarrow-zig
```

### From Zig

The package exposes a `nanoarrow` module with the translated C API:

```zig
// build.zig
const nanoarrow = b.dependency("nanoarrow", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("nanoarrow", nanoarrow.module("nanoarrow"));
```

```zig
// main.zig
const na = @import("nanoarrow");

pub fn main() !void {
    var schema: na.ArrowSchema = undefined;
    if (na.ArrowSchemaInitFromType(&schema, na.NANOARROW_TYPE_INT32) != 0) return error.Failed;
    defer schema.release.?(&schema);
}
```

The module links `libnanoarrow` automatically.

### From C / C++

```zig
const nanoarrow = b.dependency("nanoarrow", .{ .target = target, .optimize = optimize });
exe.root_module.linkLibrary(nanoarrow.artifact("nanoarrow"));
```

Headers are propagated through `linkLibrary`, so `#include <nanoarrow/nanoarrow.h>` just works.
Optional libraries are enabled by passing the options to the dependency and linking the matching
artifact:

```zig
const nanoarrow = b.dependency("nanoarrow", .{ .ipc = true, .ipc_with_zstd = true });
exe.root_module.linkLibrary(nanoarrow.artifact("nanoarrow_ipc"));
```

## License

The build files are released under the Apache License 2.0, the same as nanoarrow (see `LICENSE`).
nanoarrow, flatcc, zstd and lz4 keep their own licenses.
