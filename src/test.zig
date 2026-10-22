const std = @import("std");
const whisper = @import("whisper");

test "whisper initialization with default params" {
    const params = whisper.Context.defaultParams();
    try std.testing.expect(params.use_gpu == true);
}

test "transcript silence" {
    var params = whisper.Context.defaultParams();
    params.use_gpu = false;
    params.flash_attn = false;
    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        params,
    );
    defer context.deinit();

    const samples = [_]f32{0.0} ** 16000;
    try context.transcribe(&samples, .{});
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

test "extract wav samples from file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    
    const samples = try whisper.get_wav_file_samples(
        io, allocator, "assets/president.wav"
    );
    defer allocator.free(samples);

    //try std.testing.expectEqual(null, samples);
}

test "transcript small audio" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    
    var params = whisper.Context.defaultParams();
    params.use_gpu = false;
    params.flash_attn = false;
    var context = try whisper.Context.initFromFile(
        "assets/ggml-tiny.en.bin",
        params,
    );
    defer context.deinit();

    
    const samples = try whisper.get_wav_file_samples(
        io, allocator, "assets/president.wav"
    );
    defer allocator.free(samples);
    try context.transcribe(samples, .{ .language = "pt" });
    const count = context.segmentCount();

    try std.testing.expectEqual(count, 1);
    const segment = context.getSegment(0);

    std.debug.print("/nResultado: {s}\n", .{segment.text});
    try std.testing.expectEqualStrings(" ", segment.text);


    //try std.testing.expectEqual(null, samples);
}

//test "transcript small audio" {
//    var params = whisper.Context.defaultParams();
//    params.use_gpu = false;
//    params.flash_attn = false;
//    var context = try whisper.Context.initFromFile(
//        "assets/ggml-tiny.en.bin",
//        params,
//    );
//    defer context.deinit();
//
//
//    const samples = [_]f32{0.0} ** 16000;
//    try context.transcribe(&samples);
//    const count = context.segmentCount();
//
//    try std.testing.expectEqual(count, 1);
//    const segment = context.getSegment(0);
//    try std.testing.expectEqual(segment.t0, 0);
//    try std.testing.expectEqual(segment.t1, 1000);
//    try std.testing.expectEqualStrings(segment.text, " [BLANK_AUDIO]");
//}
