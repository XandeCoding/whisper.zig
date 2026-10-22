const std = @import("std");
pub const c = @import("c");

pub const WhisperError = error {
    InitializationError,
    TranscriptionFailed,
    InvalidWavHeader,
    InvalidWavData,
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

pub const TranscribeOptions = struct {
    threads: u8 = 2,
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

    pub const Params = c.whisper_context_params;

    /// Get the default params from Whisper context
    pub fn defaultParams() Params {
        return c.whisper_context_default_params();
    }

    /// Init Whisper context from a file using it's path
    /// - `path` must be null terminated
    /// - `params` can be the default params or a customized struct
    pub fn initFromFile(path: [:0]const u8, params: Params) WhisperError!Context {
        const instance = c.whisper_init_from_file_with_params(path.ptr, params) orelse {
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

    /// Transcribe the text received
    pub fn transcribe(
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
    file_path: []const u8
) ![]f32 {
    const file = try open_file(io, file_path);
    defer file.close(io);

    // Check if has valid Header 
    var header: [12]u8 = undefined;
    _ = try file.readPositionalAll(io, &header, 0);
    if (
        (!std.mem.eql(u8, header[0..4], "RIFF") or
         !std.mem.eql(u8, header[8..12], "WAVE"))
        ) {
        return error.InvalidWavHeader;
    }

    // TODO: LER POR BLOCOS DELIMITADOS POR EOF OU /n - CHECAR
    // TODO: Corrigir tamanho do buffer 
    var buffer: [1024 * 1024]u8 = undefined;
    _ = try file.readPositionalAll(io, &buffer, header.len);

    std.debug.print("\n -- TESTE: {s}", .{ buffer[0..100] });
    const data_start_index = std.mem.indexOf(u8, &buffer, "data");

    if (data_start_index == null) {
        return error.InvalidWavData;
    }

    // How the data it's 16 bits and each item has 8 bit, to calculate it's only
    // necessary to divide for 2
    // TODO: REMOVER ESSE ENFORCE DE TIPO
    const data_index = data_start_index orelse 0;
    const samples_len = (buffer.len - data_index) / 2;
    //const samples_len = 10;
    const samples = try allocator.alloc(f32, samples_len);
    errdefer allocator.free(samples);

    for (0 .. samples_len) |index| {
        var number: [2]u8 = .{ buffer[index], buffer[index+1] };
        const sample = std.mem.readInt(i16, &number, .little);
        std.debug.print("\nNumber: {s} -> {d}", .{ number, sample });
        samples[index] = @as(f32, @floatFromInt(sample));
    }
    
    return samples;
}


