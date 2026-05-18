# Sixel Graphics Support: Progress Report

## 1. Accomplishments
We have successfully enabled the "negotiation" phase between the PTY and applications, which was previously entirely missing.

### 1.1 Terminal Feature Advertising
- **Primary Device Attributes (DA):** Implemented `CSI c` to report Sixel support (`feature 4`). Applications like `neofetch` and `mlterm` now recognize `vtui` as a Sixel-capable terminal.
- **Secondary Device Attributes:** Implemented `CSI > c` to report terminal version, improving compatibility with modern TUI libraries.

### 1.2 PTY Feedback Loop
- Developed a writer callback mechanism in `src/parser.zig`.
- Connected this callback to the `Pty` master file descriptor in `src/main.zig`.
- **Result:** The terminal can now "talk back" to the child process, enabling automated feature detection.

### 1.3 Sixel Parser Robustness (`src/sixel.zig`)
- **Color Logic:** Fixed a critical bug in `processDecgci` where `param_idx` was not resetting, causing subsequent color commands to fail.
- **Single-Parameter Handling:** Added support for `#idx` shorthand (e.g., `#0` to select palette index 0).
- **State Machine Resets:** Fixed state persistence bugs in Repeat Introducers (`!`) and Raster Attributes (`"`).
- **Coordinate Awareness:** Updated the parser to initialize Sixel images at the current cursor position rather than always at `(0,0)`.

---

## 2. Remaining Problems & Blockers

### 2.1 The "Tiny White Pixel" Syndrome
Despite the parser correctly reporting image creation (e.g., `100x72` pixels), the visual output remains a single or tiny group of white pixels in the top-left.
- **Observed:** `Sixel createImage` log confirms the logical-to-physical scaling is working.
- **Observed:** PPM exports show mostly black or empty data even when red is forced.

### 2.2 neofetch Detection
Even with DA responses, `neofetch` still sometimes defaults to ASCII. This likely requires:
- Alignment of the `TERM` environment variable (currently `xterm-256color`).
- Reporting a more complete feature set in the DA response (matching `foot` or `xterm`).

---

## 3. Technical Hypotheses

### Hypothesis A: Buffer Indexing Error
In `src/sixel.zig`, the `drawSixel` function calculates the index as `y * image_width + cursor_x`. If `image_width` is updated via `resizeImage` but the buffer isn't correctly re-mapped or if `alloc_height` is mismanaged, pixels might be written to addresses that are later "trimmed" away by `createImage`.

### Hypothesis B: Alpha Channel/Endianness Mismatch
The renderer uses a software blitter. If the Sixel data is written as `0xFFFF0000` (Red in ARGB) but the screen buffer expects a different format (e.g. RGBA), or if the alpha channel is being misinterpreted by the final blit mask in `src/renderer.zig`, the pixels will be invisible.

### Hypothesis C: Clipping in `blitSixelImage`
The `blitSixelImageDirect` function in `src/renderer.zig` uses SIMD paths. There may be a clipping or stride calculation error that causes it to skip valid pixel data if the image doesn't align perfectly with the screen stride.

---

## 4. Recommendations for Conductor Improvements

To improve the efficiency of this and future tracks, I suggest the following changes to the `conductor/` files:

### 4.1 Update `workflow.md`: Add "State Machine Tracing" Protocol
Complex parsers (Sixel, OSC, CSI) are hard to debug with unit tests alone. The workflow should mandate a "Trace Phase" where:
- A specific debug flag is enabled to dump raw PTY bytes vs. Parser State transitions.
- A "Buffer Dump" tool is used to save intermediate bitmapped states before they hit the renderer.

### 4.2 Update `spec.md` (Template): Visual Baseline Requirements
For graphics tracks, the specification should include a "Reference Raster" requirement—a known Sixel string and its expected pixel hash. This would allow automated verification of the parser without relying on visual inspection of PNGs.

### 4.3 Implementation Plan Refinement
The current plan establishes a baseline, but lacks a "Component Isolation" task. We should add a task to:
- Test the `SixelParser` in a standalone Zig test that dumps a `.ppm` directly, bypassing `Grid`, `Renderer`, and `X11` entirely. This isolates the bug to either the **Parser** or the **Blitter**.
