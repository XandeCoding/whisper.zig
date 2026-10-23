const std = @import("std");
const whisper = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // 1. Configure and load the model
    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        .{ .log_level = whisper.LogLevel.ERROR },
    );
    defer context.deinit();

    // 2. Transcribe audio (must be 16kHz mono)
    try context.transcribe(
        io,
        allocator,
        "assets/jfk.wav",
        .{ .language = "en", .threads = 4 },
    );

    // 3. Retrieve segments
    std.log.debug("Transcribed text:", .{});
    for (0..context.segmentCount()) |i| {
        const seg = context.getSegment(i);
        std.log.info("[{d}ms -> {d}ms]: {s}", .{ seg.startMs(), seg.endMs(), seg.text });
    }
}
