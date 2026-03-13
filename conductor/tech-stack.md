# Vtui Tech Stack

## Core Technologies
*   **Language:** [Zig 0.15.2](https://ziglang.org/) - Utilizing the `root_module` pattern, new `std.Io` non-generic interfaces, and explicit memory management.
*   **Graphics Backend:** [X11](https://www.x.org/) with [Xext (MIT-SHM)](https://www.x.org/releases/current/doc/libXext/shm.html) for zero-copy buffer transport and high-performance RGBA blitting.
*   **I/O Multiplexing:** [posix.poll()](https://man7.org/linux/man-pages/man2/poll.2.html) (Current), transitioning to [io_uring](https://man7.org/linux/man-pages/man7/io_uring.7.html) for asynchronous efficiency.

## Font & Text Rendering
*   **Glyph Loading:** [FreeType2](https://www.freetype.org/) for high-quality glyph bitmap generation and sub-pixel anti-aliasing.
*   **Text Shaping:** [HarfBuzz](https://harfbuzz.github.io/) for precise glyph positioning and ligature support.
*   **Font Discovery:** [fontconfig](https://www.freedesktop.org/wiki/Software/fontconfig/) for system-wide font selection and fallback stacks.

## Performance & Architecture
*   **Data Model:** Flat `[]Cell` array for cache-friendly grid state.
*   **SIMD Acceleration:** Zig `@Vector` in `blitCell` for per-pixel alpha blending and high-speed rendering.
*   **Damage Tracking:** Incremental rendering by tracking changed cells to minimize blit operations.

## Testing & Verification
*   **Unit Testing:** Zig's built-in test runner.
*   **Visual Verification:** `test-render.sh` and `compare-foot.sh` for pixel-accurate comparisons against the `foot` terminal reference.
