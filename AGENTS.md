# AGENTS.md - Vtui AI Agent Context

> **Purpose**: Provide context for AI agents continuing Vtui development. Read this first before making changes.
> **CRITICAL DIRECTIVE**: You MUST explicitly study and use the provided reference implementations (in the `refs/` directory) before making any structural or functional changes.
> **TOOL DIRECTIVE**: **CRITICAL**: Use `rg` (ripgrep) instead of `grep` and `fd` (fd-find) instead of `find` in every possible circumstance. These tools are faster and more efficient for code searching and file finding.

---

## Current Status (March 14, 2026)

**Vtui is a complete and production-ready terminal emulator** with all major features implemented. It follows the standard ANSI communication protocol while providing highly optimized rendering performance.

### ✅ All Major Features Completed

1. **Dynamic Resizing** - ✅ Implemented
   - Handles X11 `ConfigureNotify` events in `src/window.zig`
   - Propagates resize through Grid → Renderer → Window → PTY
   - Debounced `TIOCSWINSZ` calls to prevent excessive resize events

2. **CPU Optimization Plan (The "Foot" Path)** - ✅ **ALL STEPS COMPLETED**
   - **Damage Tracking**: Per-cell dirty flags in `src/grid.zig`
   - **SIMD Acceleration**: Zig `@Vector` in `blitCell` for 16-pixel cells
   - **Zero-Copy Transport**: MIT-SHM shared memory for X11 rendering

---

## Project Mission

**Vtui** is a **Pure ANSI Rendering Engine** that runs TUI tools standalone, efficiently, without a system terminal.

```
Bytes → Grid → Pixels
ANSI   → Cell  → RGBA
```

---

## Architecture Overview

### Core Components (Complete)

| Component | File | Lines | Status |
|-----------|------|-------|--------|
| **Grid** | `src/grid.zig` | ~589 | ✅ Complete (Scrollback + Sixel support) |
| **Parser** | `src/parser.zig` | ~864 | ✅ Complete (Full OSC sequence support) |
| **Renderer** | `src/renderer.zig` | ~534 | ✅ Complete (SIMD + Sixel rendering) |
| **Main** | `src/main.zig` | ~698 | ✅ Complete (io_uring async I/O) |
| **PTY** | `src/pty.zig` | ~185 | ✅ Complete |
| **Window** | `src/window.zig` | ~240 | ✅ Complete (X11 + MIT-SHM) |
| **Font** | `src/font.zig` | ~905 | ✅ Complete (FreeType2 + HarfBuzz) |
| **Input** | `src/input.zig` | ~150 | ✅ Complete (Keyboard/mouse events) |
| **Async I/O** | `src/async_io.zig` | ~200 | ✅ Complete (io_uring integration) |
| **Sixel** | `src/sixel.zig` | ~1077 | ✅ Complete (Full Sixel graphics) |

### Data Flow

```
┌─────────────┐     ┌─────────────────────────────────────┐     ┌──────────┐
│ Legacy App  │────▶│           Vtui Engine               │────▶│  Screen  │
│ (ANSI out)  │     │  Parser → Grid → Renderer → Atlas   │     │  Buffer  │
└─────────────┘     └─────────────────────────────────────┘     └──────────┘
```

---

## Build System (Zig 0.15.2)

Vtui is built using Zig 0.15.2. This version includes major standard library changes:
- **std.Io**: Replaced generic readers/writers with the new non-generic `Io.Reader`/`Io.Writer` interfaces.
- **Async**: Language-level `async/await` has been removed.
- **Formatting**: `std.fmt` now only supports byte-based alignment (Unicode alignment must be handled manually).

### Key API Patterns

```zig
// build.zig - Zig 0.15.2 syntax
const exe = b.addExecutable(.{
    .name = "vtui",
    .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    }),
});

// Direct compilation (alternative)
zig build-exe -O ReleaseSmall --name vtui src/main.zig
```

### Build Commands

```bash
zig build                    # Build to zig-out/bin/vtui
zig build run -- --demo      # Run demo mode
zig build test               # Run unit tests
./zig-out/bin/vtui --help    # Show CLI options
```

### Global Installation

The project includes a script to build and install `vtui` globally to `/usr/local/bin/vtui`.

```bash
# To build and install globally
sudo ./build-install.sh
```

The script builds the project using `ReleaseSmall` optimization and copies the binary to the system path. Always run this after making core changes to ensure the global command reflects the latest code.

---

## Current State

### ✅ What Works

1. **ANSI Parser** (`src/parser.zig`)
   - SGR colors (30-37, 40-47, 256-color, truecolor)
   - Cursor movement (H, A, B, C, D, G)
   - Clear commands (J, K)
   - Attributes (bold, underline, reverse)
   - **Complete OSC sequence support**: 0, 2, 4, 7, 8, 52
   - Full UTF-8 support (including Braille patterns)

2. **Grid System** (`src/grid.zig`)
   - Flat `[]Cell` array (cache-friendly)
   - Cell: `char`, `fg`, `bg`, `flags` (16 bytes)
   - Cursor tracking
   - Scrollback buffer
   - **Sixel image storage and management**

3. **Renderer** (`src/renderer.zig`)
   - Glyph atlas (512x512, built-in patterns)
   - RGBA buffer output
   - Background fill + glyph blit
   - **Sixel rendering** (Direct and Scaled blitting)
   - **SIMD-accelerated blending for 16px wide fonts**

4. **Window System** (`src/window.zig`)
   - X11 display backend
   - **MIT-SHM shared memory for zero-copy rendering**
   - RGBA buffer blitting to screen

5. **Font System** (`src/font.zig`)
   - **FreeType2 font loading**
   - **HarfBuzz glyph shaping**
   - Fallback font support
   - Atlas generation

6. **Input Handling** (`src/input.zig`)
   - Keyboard events
   - Mouse events
   - Modifiers support

7. **PTY System** (`src/pty.zig`)
   - Correct child process session/terminal setup
   - Signal mask/handler resets
   - Non-blocking I/O support
   - Environment variables (TERM, COLORTERM)

8. **Async I/O** (`src/async_io.zig`)
   - **io_uring integration** - replaces posix.poll()
   - Async event loop for PTY, STDIN, and X11

### ✅ All Features Complete

**No major features need fixing. Vtui is fully functional.**

### Rendering System

The rendering system uses a software-based glyph atlas (512x512).
- **Glyph Size**: 16x16 pixels.
- **Atlas Stride**: 512 pixels (2048 bytes).
- **Procedural Support**: Braille patterns are drawn procedurally for high contrast.

### Verification Tools

A script is provided to verify rendering changes by saving a PPM screenshot:
```bash
./test-render.sh [command]  # Defaults to neofetch
```

---

## Reference Implementations

### Location
```
/home/Intro/spectre-enviroment/V-tui/refs/
├── ghostty/     ← Zig terminal (MIT license)
└── foot/        ← C terminal (MIT license)
```

### Key Files to Study

#### PTY Implementation
- `refs/ghostty/src/pty.zig` - Zig PTY open/spawn (400 lines)
- `refs/foot/spawn.c` - Process spawning (205 lines, MIT)

#### Window/Display
- `refs/ghostty/src/apprt/gtk.zig` - GTK window (Linux)
- `refs/foot/wayland.c` - Wayland protocol (complex)
- **Simpler**: Use X11 or `/dev/fb0` framebuffer

#### Font Loading
- `refs/ghostty/src/font/library.zig` - FreeType2 loading
- `refs/ghostty/src/font/face/freetype.zig` - Glyph rendering
- `refs/ghostty/src/font/Atlas.zig` - Texture atlas management

---

## Code Conventions

### Tool Usage
**CRITICAL**: Use `rg` (ripgrep) instead of `grep` and `fd` (fd-find) instead of `find` in every possible circumstance. These tools are faster and more efficient for code searching and file finding.

### Style Guidelines

```zig
// Naming
const CellFlags = struct {};      // Types: PascalCase
const cell_flags: CellFlags;      // Variables: snake_case
fn processByte() void {}          // Functions: camelCase

// Error handling
pub const Error = error{
    OpenFailed,
    ParseFailed,
};

// Struct initialization
const cell = Cell{
    .char = 'A',
    .fg = 0xFF0000,
    .bg = 0x000000,
    .flags = .{},
};

// Unused parameters
fn callback(self: *Self, data: []const u8) void {
    _ = data;  // Mark unused
}
```

### Module Imports

```zig
const std = @import("std");
const Grid = @import("grid.zig").Grid;
const Parser = @import("parser.zig").Parser;
```

---

## Testing Strategy

### Unit Tests

```zig
test "Grid basic operations" {
    const allocator = std.testing.allocator;
    var grid = try Grid.init(allocator, 80, 24);
    defer grid.deinit(allocator);

    grid.setCell(0, 0, 'A', 0xFF0000, 0x000000, .{});
    const cell = grid.cellAt(0, 0).?;
    try std.testing.expectEqual('A', cell.char);
}
```

### CLI Test Modes

```bash
./vtui --demo        # Render sample ANSI
./vtui --test-parse  # Parser unit tests
./vtui --test-render # Renderer output test
./vtui --test-sixel  # Sixel parser and image creation
```

---

## Contact/Continuation

**Last Updated**: March 14, 2026
**Status**: Complete. All major features implemented including io_uring async I/O, full OSC sequence support, Sixel graphics, FreeType2 + HarfBuzz font system. Vtui is a production-ready terminal emulator.

---
