# Vtui - Pure ANSI Rendering Engine

**Bytes → Grid → Pixels**

Vtui is a high-performance ANSI-to-pixel converter. It accepts the *language* (ANSI escape sequences) without the *protocol overhead* (terminal emulator).

## Mission

Run existing TUI tools (vim, ratatui apps, etc.) **standalone**, **efficiently**, **without a system terminal**.

## Architecture

```
┌─────────────┐     ┌─────────────────────────────────────┐     ┌──────────┐
│ Legacy App  │────▶│           Vtui Engine               │────▶│  Screen  │
│ (ANSI out)  │     │  Parser → Grid → Renderer → Atlas   │     │  Buffer  │
└─────────────┘     └─────────────────────────────────────┘     └──────────┘
```

### Components

| Component | Role | Implementation |
|-----------|------|----------------|
| **Parser** | ANSI state machine | `src/parser.zig` |
| **Grid** | Screen state (flat Cell array) | `src/grid.zig` |
| **Renderer** | Glyph atlas blitter | `src/renderer.zig` |

### Data Flow

1. **Input**: App writes ANSI sequences (`\x1b[31m`) to stdout
2. **Parse**: Zero-allocation state machine updates Grid
3. **Render**: Glyph atlas blits to RGBA buffer
4. **Output**: Raw pixels ready for display

## Build

```bash
# Build with Zig
zig build

# Or direct compilation
zig build-exe -O ReleaseSmall --name vtui src/main.zig

# Run tests
zig build test
```

## Usage

```bash
# Demo mode - render sample ANSI content
./vtui --demo

# Test parser
./vtui --test-parse

# Test renderer
./vtui --test-render

# Help
./vtui --help
```

## Supported ANSI Codes

### SGR (Select Graphic Rendition)
| Code | Meaning |
|------|---------|
| 0 | Reset all |
| 1 | Bold |
| 4 | Underline |
| 7 | Reverse |
| 30-37 | Foreground colors |
| 38;5;n | 256-color foreground |
| 38;2;r;g;b | Truecolor foreground |
| 40-47 | Background colors |
| 48;5;n | 256-color background |
| 48;2;r;g;b | Truecolor background |
| 90-97 | Bright foreground |
| 100-107 | Bright background |

### Cursor Movement
- `ESC [ H` - Home
- `ESC [ row;col H` - Position
- `ESC [ n A/B/C/D` - Up/Down/Forward/Back
- `ESC [ n G` - Horizontal absolute

### Erase Commands
- `ESC [ J` - Clear screen
- `ESC [ K` - Clear line

## Performance

- **Binary size**: ~3.2 MB (stripped, ReleaseSmall)
- **Parser**: Zero heap allocation, stack-based state
- **Grid**: Flat array, cache-friendly Cell struct (16 bytes)
- **Renderer**: Single-pass blit with glyph atlas

## License

MIT (derived from foot terminal architecture - MIT licensed)

## References

- **foot** (MIT): Data model, parser state machine
- **kitty** (GPL): Glyph atlas concept (ideas only, no code)
