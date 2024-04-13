
const std = @import("std");
const sdl = @import("sdl");
// const sdl = @cImport({
//     @cInclude("SDL2/SDL.h");
// });
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

    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.SDL_Quit();

    const screen = sdl.SDL_CreateWindow("My Game Window", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, 400, 140, sdl.SDL_WINDOW_OPENGL) orelse
        {
        sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyWindow(screen);

    const renderer = sdl.SDL_CreateRenderer(screen, -1, 0) orelse {
        sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);

    const zig_bmp = @embedFile("zig.bmp");
    const rw = sdl.SDL_RWFromConstMem(zig_bmp, zig_bmp.len) orelse {
        sdl.SDL_Log("Unable to get RWFromConstMem: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer assert(sdl.SDL_RWclose(rw) == 0);

    const zig_surface = sdl.SDL_LoadBMP_RW(rw, 0) orelse {
        sdl.SDL_Log("Unable to load bmp: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_FreeSurface(zig_surface);

    const zig_texture = sdl.SDL_CreateTextureFromSurface(renderer, zig_surface) orelse {
        sdl.SDL_Log("Unable to create texture from surface: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.SDL_DestroyTexture(zig_texture);

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
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        _ = sdl.SDL_RenderClear(renderer);
        _ = sdl.SDL_RenderCopy(renderer, zig_texture, null, null);
        sdl.SDL_RenderPresent(renderer);

        sdl.SDL_Delay(17);
    }
}
