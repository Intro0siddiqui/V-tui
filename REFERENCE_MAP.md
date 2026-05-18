# Vtui Reference Map

Key files from **Ghostty** (Zig) and **foot** (C, MIT) to study for Vtui implementation.

---

## What Vtui Needs Next (Updated March 10, 2026)

| Priority | Feature | Ghostty Reference | foot Reference |
|----------|---------|-------------------|----------------|
| 1 | **Font Loading** | `src/font/` (700KB total) | N/A (uses fontconfig) |
| 2 | **Input Handling** | `src/input/` (450KB total) | `input.c` (126K lines) |
| 3 | **io_uring Integration** | `src/termio/Exec.zig` | N/A (C not relevant) |

**Completed (Phases 1-8)**:
- ✅ PTY/Subprocess: `src/pty.zig` (151 lines) - COMPLETE
- ✅ Window Output: `src/window.zig` (140 lines) - COMPLETE (X11 backend)

---

## 1. PTY / Subprocess (Priority: HIGH)

### Ghostty: `src/pty.zig`
- **Size**: 14KB, ~400 lines
- **Purpose**: PTY creation, process spawning
- **Key functions**:
  - `openPty()` - Create PTY master/slave pair
  - `spawn()` - Fork and exec child process
  - `read()`/`write()` - PTY I/O

### foot: `slave.c`, `spawn.c`
- **slave.c**: PTY slave setup (15KB)
- **spawn.c**: Process spawning (205 lines)
- **License**: MIT - can adapt directly

---

## 2. Window Output (Priority: HIGH)

### Ghostty: `src/apprt/` (Application Runtime)
```
src/apprt/
  ├── cocoa.zig      (macOS)
  ├── gtk.zig        (Linux GTK)
  ├── wasm.zig       (WebAssembly)
  └── apprt.zig      (Main interface)
```

### Ghostty: `src/renderer/`
```
src/renderer/
  ├── gpu/           (GPU rendering)
  ├── software.zig   (Software blit)
  └── renderer.zig   (Main renderer)
```

### foot: `wayland.c`, `render.c`
- **wayland.c**: Wayland protocol (2.8K lines) - complex
- **render.c**: Rendering logic (5.4K lines) - study for algorithm
- **License**: MIT

---

## 3. Font Loading (Priority: MEDIUM)

### Ghostty: `src/font/` (Comprehensive)
```
src/font/
  ├── Atlas.zig           (512 lines)
  ├── Collection.zig      (1.5K lines)
  ├── discovery.zig       (1.2K lines)
  ├── face.zig            (900 lines)
  ├── library.zig         (Font loading)
  └── Metrics.zig         (Font metrics)
```

**Key file**: `src/font/library.zig` - FreeType2 loading

### foot: Uses fontconfig + FreeType2
- Study `render.c` for font rasterization

---

## 4. Input Handling (Priority: MEDIUM)

### Ghostty: `src/input/`
```
src/input/
  ├── Binding.zig         (4K lines)
  ├── key.zig             (800 lines)
  ├── keyboard.zig        (100 lines)
  └── keycodes.zig        (1K lines)
```

### foot: `input.c` (126K lines)
- Very comprehensive, includes IME, compose, etc.
- Can extract minimal keyboard handling

---

## 5. Terminal State (Already Done in Vtui)

### Ghostty: `src/terminal/`
```
src/terminal/
  ├── Parser.zig          (1K lines) - ANSI parser
  ├── page.zig            (4K lines) - Grid pages
  ├── color.zig           (1.4K lines) - Color handling
  └── csi.zig, osc.zig    - CSI/OSC handlers
```

### foot: `terminal.c`, `grid.c`, `csi.c`
- **terminal.c**: 147K lines - full terminal emulation
- **grid.c**: 55K lines - scrollback, selection
- **csi.c**: 75K lines - CSI sequence handling

**Vtui already has basic parser** - can study these for extended sequences.

---

## Minimal Implementation Plan (Updated March 10, 2026)

### Completed Phases

**Phase 7: PTY Wrapper (COMPLETE)**
- ✅ `src/pty.zig` - PTY creation and process spawning

**Phase 8: Window Output (COMPLETE)**
- ✅ `src/window.zig` - X11 display backend

### Remaining Phases

### Phase 9: Font Loading (NEXT)
1. Study `ghostty/src/font/library.zig`
2. Load TTF with FreeType2
3. Generate atlas at startup

### Phase 10: Input Handling
1. Capture keyboard events from X11
2. Translate to ANSI/escape sequences
3. Write to PTY master

### Phase 11: io_uring Integration (Advanced)
1. Study `refs/ghostty/src/termio/Exec.zig` for patterns
2. Replace `posix.poll()` with `io_uring_enter()`
3. Batch PTY read/write operations
4. Handle keyboard input asynchronously

---

## File Locations

```
/home/Intro/spectre-enviroment/V-tui/refs/
├── ghostty/           ← Full src/ kept for Zig reference
│   └── src/
│       ├── pty.zig              ← PTY/spawn
│       ├── apprt/gtk.zig        ← Window (Linux)
│       ├── renderer/            ← Rendering
│       └── font/                ← Font loading
└── foot/              ← Full repo kept for reference
    ├── slave.c                  ← PTY slave (MIT) - KEY
    ├── spawn.c                  ← Process spawn (MIT) - KEY
    ├── render.c                 ← Rendering (MIT) - KEY
    ├── terminal.c               ← Terminal state - KEY
    └── grid.c                   ← Grid data structure - KEY
```

**Note**: Full foot repo retained (~25MB) for future reference. Key files marked above.

---

## License Notes

| Source | License | Can Copy? |
|--------|---------|-----------|
| Ghostty | MIT | Yes, with attribution |
| foot | MIT | Yes, with attribution |
| kitty | GPL | Ideas only, no code |
