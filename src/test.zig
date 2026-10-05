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
        "ggml-tiny.en.bin",
        params,
    );
    defer context.deinit();

    const samples = [_]f32{0.0} ** 16000;
    try context.transcribe(&samples);
    const count = context.segmentCount();

    try std.testing.expectEqual(count, 1);
    const segment = context.getSegment(0);
    try std.testing.expectEqual(segment.t0, 0);
    try std.testing.expectEqual(segment.t1, 1000);
    try std.testing.expectEqualStrings(segment.text, " [BLANK_AUDIO]");
}
