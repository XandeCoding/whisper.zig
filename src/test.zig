const std = @import("std");
const whisper = @import("whisper");

test "whisper initialization with default params" {
    const options = whisper.ContextOptions.toC(.{});
    try std.testing.expect(options.use_gpu == false);
    try std.testing.expect(options.flash_attn == false);
}

test "extract wav samples from file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const samples = try whisper.get_wav_file_samples(io, allocator, "assets/jfk.wav");
    defer allocator.free(samples);

    try std.testing.expectEqual(176000, samples.len);
    try std.testing.expectEqual(0.000030517578, samples[1000]);
    try std.testing.expectEqual(-0.003967285, samples[50000]);
    try std.testing.expectEqual(-0.013916016, samples[175999]);
}

test "receive error extracting invalid wav sample" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    try std.testing.expectError(
        error.InvalidWavData,
        whisper.get_wav_file_samples(io, allocator, "assets/invalid_audio.wav"),
    );
}

test "transcript silence" {
    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        .{},
    );
    defer context.deinit();

    const samples: [16000]f32 = @splat(0.0);
    try context.transcribeSamples(&samples, .{});
    const count = context.segmentCount();

    try std.testing.expectEqual(count, 1);
    const segment = context.getSegment(0);
    try std.testing.expectEqual(segment.t0, 0);
    try std.testing.expectEqual(segment.startMs(), 0);
    try std.testing.expectEqual(segment.t1, 1000);
    try std.testing.expectEqual(segment.endMs(), 10000);
    try std.testing.expectEqualStrings(segment.text, " [BLANK_AUDIO]");
    try std.testing.expectEqual(segment.durationMs(), 10000);
}

test "transcript small audio" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        .{},
    );
    defer context.deinit();

    try context.transcribe(io, allocator, "assets/jfk.wav", .{ .language = "en" });

    try std.testing.expectEqual(2, context.segmentCount());
    try std.testing.expectEqualStrings(
        " And so my fellow Americans ask not what your country can do for you",
        context.getSegment(0).text,
    );
    try std.testing.expectEqual(8000, context.getSegment(0).durationMs());
    try std.testing.expectEqualStrings(
        " ask what you can do for your country.",
        context.getSegment(1).text,
    );
    try std.testing.expectEqual(3000, context.getSegment(1).durationMs());
}
