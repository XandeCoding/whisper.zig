const std = @import("std");
pub const c = @import("c");

var LOG_LEVEL = LogLevel.DEBUG;
pub const MAX_F32_NUMBER: f32 = 32768.0;

pub const WhisperError = error{
    InitializationError,
    TranscriptionFailed,
    InvalidWavHeader,
    InvalidWavData,
};

pub const LogLevel = enum(u8) {
    NONE = 0,
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    CONT = 5,
};

pub const Segment = struct {
    /// Transcript text
    text: []const u8,
    /// Initial time in hundredths of a second
    t0: i64,
    /// End time in hundredths of a second
    t1: i64,

    /// Returns the start time in milliseconds
    pub fn startMs(self: Segment) i64 {
        return self.t0 * 10;
    }

    /// Returns the end time in milliseconds
    pub fn endMs(self: Segment) i64 {
        return self.t1 * 10;
    }

    // Returns the total duration in milliseconds
    pub fn durationMs(self: Segment) i64 {
        return (self.t1 - self.t0) * 10;
    }
};

pub const ContextOptions = struct {
    use_gpu: bool = false,
    flash_attn: bool = false,
    log_level: LogLevel = LogLevel.DEBUG,

    pub fn toC(self: ContextOptions) c.whisper_context_params {
        var params = c.whisper_context_default_params();
        params.use_gpu = self.use_gpu;
        params.flash_attn = self.flash_attn;

        return params;
    }
};

pub const TranscribeOptions = struct {
    threads: u8 = 4,
    translate: bool = false,
    language: ?[:0]const u8 = null, // DEFAULT = AUTO_DETECT

    pub fn toC(self: TranscribeOptions) c.whisper_full_params {
        var params = c.whisper_full_default_params(
            c.WHISPER_SAMPLING_GREEDY,
        );
        params.n_threads = @as(c_int, self.threads);
        params.translate = self.translate;

        if (self.language) |language| {
            params.language = language.ptr;
        } else {
            params.language = null;
        }

        return params;
    }
};

pub const Context = struct {
    instance: *c.whisper_context,

    /// Init Whisper context from a file using it's path
    /// - `path` must be null terminated
    /// - `params` can be the default params or a customized struct
    pub fn initFromFile(path: [:0]const u8, options: ContextOptions) WhisperError!Context {
        // TODO: IMPROVE THIS GLOBAL USAGE
        LOG_LEVEL = options.log_level;
        c.whisper_log_set(handleLog, null);
        const instance = c.whisper_init_from_file_with_params(path.ptr, options.toC()) orelse {
            return error.InitializationError;
        };

        return Context{ .instance = instance };
    }

    /// Free the Whisper context
    pub fn deinit(self: *Context) void {
        c.whisper_free(self.instance);
    }

    /// Bring hardware information
    pub fn systemInfo() []const u8 {
        const info_ptr = c.whisper_print_system_info();
        return std.mem.span(info_ptr);
    }

    /// Transcribe the audio received
    // TODO: AFTER THE AUDIO REFACT ADD WHISPERERROR AGAIN TO RETURN
    pub fn transcribe(
        self: *Context,
        io: std.Io,
        allocator: std.mem.Allocator,
        audio_path: []const u8,
        options: TranscribeOptions,
    ) !void {
        const samples = try get_wav_file_samples(io, allocator, audio_path);
        defer allocator.free(samples);
        try self.transcribeSamples(samples, options);
    }

    /// Transcribe the audio samples received
    pub fn transcribeSamples(
        self: *Context,
        samples: []const f32,
        options: TranscribeOptions,
    ) WhisperError!void {
        const params = options.toC();
        const result = c.whisper_full(
            self.instance,
            params,
            samples.ptr,
            @intCast(samples.len),
        );

        // All results different from zero are a not successful response
        if (result != 0) return error.TranscriptionFailed;
    }

    /// Count how many segments it's in the context
    pub fn segmentCount(self: *Context) usize {
        return @intCast(c.whisper_full_n_segments(self.instance));
    }

    /// Get a segment from context by it's index
    pub fn getSegment(self: *Context, index: usize) Segment {
        const i: c_int = @intCast(index);
        return Segment{
            .text = std.mem.span(c.whisper_full_get_segment_text(self.instance, i)),
            .t0 = c.whisper_full_get_segment_t0(self.instance, i),
            .t1 = c.whisper_full_get_segment_t1(self.instance, i),
        };
    }
};

/// Module to handle Logs
fn handleLog(
    level: c.ggml_log_level,
    text: [*c]const u8,
    user_data: ?*anyopaque,
) callconv(.c) void {
    if (LOG_LEVEL == LogLevel.NONE or level < @backingInt(LOG_LEVEL)) return;
    _ = user_data;

    switch (level) {
        @backingInt(LogLevel.DEBUG) => std.log.debug("{s}", .{ text }),
        @backingInt(LogLevel.INFO) => std.log.info("{s}", .{ text }),
        @backingInt(LogLevel.WARN) => std.log.warn("{s}", .{ text }),
        @backingInt(LogLevel.ERROR) => std.log.err("{s}", .{ text }),
        // TODO: MUST BE DEBUG?
        @backingInt(LogLevel.CONT) => std.log.debug("{s}", .{ text}),
        else => {}
    }

}


/// Module to handle audio files
/// REFACT TO HANDLE FILES AND STREAMING
fn open_file(io: std.Io, file_path: []const u8) !std.Io.File {
    // TODO: HANDLE ABSOLUTE PATH
    const directory = std.Io.Dir.cwd();
    const file = try directory.openFile(io, file_path, .{});

    return file;
}

pub fn get_wav_file_samples(
    io: std.Io,
    allocator: std.mem.Allocator,
    file_path: []const u8,
) ![]f32 {
    const file = try open_file(io, file_path);
    defer file.close(io);

    // Check if has valid Header
    var header: [12]u8 = undefined;
    _ = try file.readPositionalAll(io, &header, 0);

    if ((!std.mem.eql(u8, header[0..4], "RIFF") or
        !std.mem.eql(u8, header[8..12], "WAVE")))
    {
        return error.InvalidWavHeader;
    }

    const file_length = try file.length(io) - header.len;
    const buffer = try allocator.alloc(u8, file_length);
    defer allocator.free(buffer);

    _ = try file.readPositionalAll(io, buffer, header.len);

    // Validating the format received
    const fmt_header_index = std.mem.indexOf(u8, buffer, "fmt") orelse {
        return error.InvalidWavData;
    };

    const audio_format = std.mem.readInt(
        u16,
        buffer[fmt_header_index + 8 .. fmt_header_index + 10][0..2],
        .little,
    );
    const channels = std.mem.readInt(u16, buffer[fmt_header_index + 10 .. fmt_header_index + 12][0..2], .little);
    const sample_rate = std.mem.readInt(u32, buffer[fmt_header_index + 12 .. fmt_header_index + 16][0..4], .little);
    const bits_sample = std.mem.readInt(u16, buffer[fmt_header_index + 22 .. fmt_header_index + 24][0..2], .little);

    if (audio_format != 1) return error.InvalidWavData;
    if (channels != 1) return error.InvalidWavData;
    if (sample_rate != 16000) return error.InvalidWavData;
    if (bits_sample != 16) return error.InvalidWavData;

    const data_header_index = std.mem.indexOf(u8, buffer, "data") orelse {
        return error.InvalidWavData;
    };

    // The data size info it's after the data header and has 4 bytes
    const audio_start_index = data_header_index + 8;
    const data_size_header = buffer[data_header_index + 4 .. audio_start_index];
    const data_size = std.mem.readInt(
        u32,
        data_size_header[0..4],
        .little,
    );
    // How the data it's 16 bits and each item has 8 bit, to calculate it's only
    // necessary to divide for 2
    const chunks_len = data_size / 2;
    const samples = try allocator.alloc(f32, chunks_len);
    errdefer allocator.free(samples);

    for (0..chunks_len) |index| {
        const buffer_index = audio_start_index + (index * 2);
        const sample = std.mem.readInt(
            i16,
            &[_]u8{ buffer[buffer_index], buffer[buffer_index + 1] },
            .little,
        );
        // Whisper uses a number between -1 and 1, for this it's necessary to divide
        // for the greater number possible handled in a f32 type
        samples[index] = @as(f32, @floatFromInt(sample)) / MAX_F32_NUMBER;
    }

    return samples;
}
