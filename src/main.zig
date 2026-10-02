const std = @import("std");
const c = @import("c");

test "main" {
    _ = c.printf("Hello from C!\n");
    const teste = c.whisper_context_default_params();

    std.debug.print("\n\nTeste: {any}", .{teste});
}
