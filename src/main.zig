const std = @import("std");
const whisper = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // 1. Configure and load the model
    var params = whisper.Context.defaultParams();
    params.use_gpu = false;
    params.flash_attn = false;

    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        params,
    );
    defer context.deinit();

    // 2. Load audio samples (16kHz mono)
    const samples = try whisper.get_wav_file_samples(io, allocator, "assets/jfk.wav");
    defer allocator.free(samples);

    // 3. Transcribe
    try context.transcribe(samples, .{ .language = "en" });

    // 4. Retrieve segments
    std.log.debug("Transcribed text:", .{});
    for (0..context.segmentCount()) |i| {
        const seg = context.getSegment(i);
        std.log.info("[{d}ms -> {d}ms]: {s}", .{ seg.startMs(), seg.endMs(), seg.text });
    }
}
