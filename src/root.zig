const std = @import("std");
pub const c = @import("c");

pub const WhisperError = error {
    InitializationError,
    TranscriptionFailed,
};

pub const Segment = struct {
    /// Transcript text
    text: []const u8,
    /// Initial time
    t0: i64,
    /// End time
    t1: i64,
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
    pub fn transcribe(self: *Context, samples: []const f32) WhisperError!void {
        const params = c.whisper_full_default_params(
            c.WHISPER_SAMPLING_GREEDY,
        );
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

