const std = @import("std");
const whisper = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var params = whisper.Context.defaultParams();
    params.use_gpu = false;
    params.flash_attn = false;

    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        params,
    );
    defer context.deinit();

    const samples = try whisper.get_wav_file_samples(io, allocator, "assets/jfk.wav");
    defer allocator.free(samples);
    try context.transcribe(samples, .{ .language = "en" });

    std.log.debug("Transcribed text:", .{});

    for (0..context.segmentCount()) |count| {
        std.log.debug("{s}", .{context.getSegment(count).text});
    }
}
