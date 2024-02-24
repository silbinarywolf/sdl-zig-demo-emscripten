const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

// NOTE(jae): 2024-02-24
// Force allocator to use c_allocator for emscripten, this is a workaround that resolves memory issues with Emscripten
// getting a OutOfMemory error when logging/etc
//
// Not sure yet as to why we need to do this.
pub const os = if (builtin.os.tag != .emscripten and builtin.os.tag != .wasi) std.os else struct {
    pub const heap = struct {
        pub const page_allocator = std.heap.c_allocator;
    };
};

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{
        .safety = true,
    }){};
    defer _ = gp.deinit();

    // set current working directory
    if (builtin.os.tag == .emscripten or builtin.os.tag == .wasi) {
        const dir = try std.fs.cwd().openDir("/wasm_data", .{});
        if (builtin.os.tag == .emscripten) {
            try dir.setAsCwd();
        } else if (builtin.os.tag == .wasi) {
            @panic("setting the default current working directory in wasi requires overriding defaultWasiCwd()");
        }
    } else {
        const dir = try std.fs.cwd().openDir("assets", .{});
        try dir.setAsCwd();
    }

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("My Game Window", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 400, 140, c.SDL_WINDOW_OPENGL) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    const zig_bmp = @embedFile("zig.bmp");
    const rw = c.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
        c.SDL_Log("Unable to get RWFromConstMem: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer assert(c.SDL_RWclose(rw) == 0);

    const zig_surface = c.SDL_LoadBMP_RW(rw, 0) orelse {
        c.SDL_Log("Unable to load bmp: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_FreeSurface(zig_surface);

    const zig_texture = c.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(zig_texture);

    // Load a file from the /assets/ folder
    const asset_file = try std.fs.cwd().openFile("text_file.txt", .{});
    defer asset_file.close();
    const stat = try asset_file.stat();
    const text_file_contents = try asset_file.readToEndAlloc(gp.allocator(), @intCast(stat.size));
    // NOTE(jae): 2024-02-24
    // Look in the Developer Console for your browser of choice, Chrome/Firefox and you should see
    // this printed on start-up.
    std.debug.print("text_file.txt: {s}\n", .{text_file_contents});
    defer gp.allocator().free(text_file_contents);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderCopy(renderer, zig_texture, null, null);
        c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}
