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


    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            // TODO: ADICIONAR TEST.ZIG
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "c", .module = c_module },
            },
            .link_libcpp = true,
        }),
    });

    // Gera o ggml-version.h que o CMake gerava -- Talvez gerar de forma estática no projeto
    const write_files = b.addWriteFiles();
    _ = write_files.add("ggml-version.h",
        \\#pragma once
        \\#define GGML_VERSION "0.1.0"
        \\#define GGML_COMMIT  "unknown"
    );

    tests.root_module.addIncludePath(write_files.getDirectory());
    tests.root_module.addIncludePath(whisper_cpp.path("include"));
    tests.root_module.addIncludePath(whisper_cpp.path("ggml/include"));
    tests.root_module.addIncludePath(whisper_cpp.path("ggml/src"));
    tests.root_module.addIncludePath(whisper_cpp.path("ggml/src/ggml-cpu"));
    tests.root_module.addCMacro("_GNU_SOURCE", "1");
    tests.root_module.addCMacro("GGML_USE_CPU", "1");

    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("src/whisper.cpp"),
        .flags = &.{
            "-std=c++11",
            "-DWHISPER_VERSION=\"1.9.4\"",
        },
    });

    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml.c"),
    });

    // GGML Base
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-quants.c"),
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-threading.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-backend.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-backend-reg.cpp"),
        .flags = &.{ "-std=c++17" },
    });

    // GGML CPU Backend
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/ggml-cpu.c"),
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/ggml-cpu.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/quants.c"),
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/traits.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/binary-ops.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/unary-ops.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/vec.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/ops.cpp"),
        .flags = &.{ "-std=c++17" },
    });


    
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-alloc.c"),
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-backend-dl.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-backend-meta.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/arch/x86/quants.c"),
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/arch/x86/cpu-feats.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/arch/x86/repack.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/repack.cpp"),
        .flags = &.{ "-std=c++17" },
    });
    tests.root_module.addCSourceFile(.{
        .file = whisper_cpp.path("ggml/src/ggml-cpu/iqp.cpp"),
        .flags = &.{ "-std=c++17" },
    });

    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run tests").dependOn(&run_tests.step);
}
