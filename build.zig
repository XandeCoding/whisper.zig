const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const whisper_cpp = b.dependency("whisper_cpp", .{});
    const translate_c = b.addTranslateC(.{
        .root_source_file = whisper_cpp.path("include/whisper.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(whisper_cpp.path("include"));
    translate_c.addIncludePath(whisper_cpp.path("ggml/include"));

    const c_module = translate_c.createModule();
    include_ggml_lib(b, whisper_cpp, c_module);

    const whisper_zig = b.addModule("whisper_zig", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .imports = &.{
        .{ .name = "c", .module = c_module },
    } });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/test.zig"),
            .imports = &.{
                .{ .name = "whisper", .module = whisper_zig },
            },
            .link_libcpp = true,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run tests").dependOn(&run_tests.step);

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "whisper", .module = whisper_zig },
            },
            .link_libcpp = true,
        }),
    });
    exe.root_module.addImport("c", c_module);
    b.installArtifact(exe);

    // Create "run" step for the example
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the example application");
    run_step.dependOn(&run_cmd.step);
}

fn include_ggml_lib(b: *std.Build, dep: *std.Build.Dependency, module: *std.Build.Module) void {
    // Gera o ggml-version.h que o CMake gerava -- Talvez gerar de forma estática no projeto
    const write_files = b.addWriteFiles();
    _ = write_files.add("ggml-version.h",
        \\#pragma once
        \\#define GGML_VERSION "0.1.0"
        \\#define GGML_COMMIT  "unknown"
    );

    module.addIncludePath(write_files.getDirectory());
    module.addIncludePath(dep.path("include"));
    module.addIncludePath(dep.path("ggml/include"));
    module.addIncludePath(dep.path("ggml/src"));
    module.addIncludePath(dep.path("ggml/src/ggml-cpu"));
    module.addCMacro("_GNU_SOURCE", "1");
    module.addCMacro("GGML_USE_CPU", "1");

    module.addCSourceFile(.{
        .file = dep.path("src/whisper.cpp"),
        .flags = &.{
            "-std=c++11",
            "-DWHISPER_VERSION=\"1.9.4\"",
        },
    });

    const c_sources: [6][]const u8 = .{
        "ggml/src/ggml.c",
        "ggml/src/ggml-quants.c",
        "ggml/src/ggml-alloc.c",
        "ggml/src/ggml-cpu/ggml-cpu.c",
        "ggml/src/ggml-cpu/quants.c",
        "ggml/src/ggml-cpu/arch/x86/quants.c",
    };
    for (c_sources) |src| {
        module.addCSourceFile(.{
            .file = dep.path(src),
            .flags = &.{"-fno-sanitize=undefined"},
        });
    }
    // 3. Fontes em C++ (C++17)
    const cpp_sources: [15][]const u8 = .{
        "ggml/src/ggml-threading.cpp",
        "ggml/src/ggml-backend.cpp",
        "ggml/src/ggml-backend-reg.cpp",
        "ggml/src/ggml-backend-dl.cpp",
        "ggml/src/ggml-backend-meta.cpp",
        "ggml/src/ggml-cpu/ggml-cpu.cpp",
        "ggml/src/ggml-cpu/traits.cpp",
        "ggml/src/ggml-cpu/binary-ops.cpp",
        "ggml/src/ggml-cpu/unary-ops.cpp",
        "ggml/src/ggml-cpu/vec.cpp",
        "ggml/src/ggml-cpu/ops.cpp",
        "ggml/src/ggml-cpu/repack.cpp",
        "ggml/src/ggml-cpu/iqp.cpp",
        "ggml/src/ggml-cpu/arch/x86/cpu-feats.cpp",
        "ggml/src/ggml-cpu/arch/x86/repack.cpp",
    };
    for (cpp_sources) |src| {
        module.addCSourceFile(.{
            .file = dep.path(src),
            .flags = &.{ "-std=c++17", "-fno-sanitize=undefined" },
        });
    }
}
