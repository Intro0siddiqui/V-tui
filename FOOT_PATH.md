# FOOT_PATH.md - CPU Optimization Strategy

**Goal**: Reach the rendering performance and efficiency of the `foot` terminal by utilizing pure CPU power and zero-copy memory techniques.

## Current Progress
- [x] **Step 1: Cell-Level Damage Tracking**: Only redraw cells that have changed. (Completed March 12, 2026)
- [x] **Step 2: SIMD Acceleration**: Use Zig `@Vector` for blitting and alpha blending. (Completed March 12, 2026)
- [x] **Step 3: MIT-SHM (X11 Shared Memory)**: Eliminate the final copy from terminal to X11 server. (Completed March 12, 2026)

## Step 3 Implementation Plan (MIT-SHM)
1. **Extension Detection**: Use `XShmQueryExtension` to verify availability.
2. **Segment Allocation**:
   - Use `shmget` with `IPC_PRIVATE` to create a shared memory segment.
   - Use `shmat` to attach it to the Vtui process.
   - Use `XShmAttach` to tell the X Server about the segment.
3. **Image Creation**: Use `XShmCreateImage` to link the shared memory to an `XImage`.
4. **Drawing**: Replace `XPutImage` with `XShmPutImage`.
5. **Synchronization**: Use `XSync` and handle `ShmCompletion` events to ensure we don't write to the buffer while X11 is reading it (preventing tearing).

## Post-Optimization Goal: Fixing "Garbage Pixels"
Once the pipeline is zero-copy and fast, we will focus on visual fidelity:
1. **Sub-pixel Anti-aliasing**: Move beyond grayscale to LCD-optimized blending.
2. **Text Shaping**: Integrate HarfBuzz to handle ligatures and complex scripts properly (preventing character misalignment).
3. **Atlas Padding**: Ensure glyphs in the atlas have 1px padding to prevent "bleeding" between adjacent characters.

---
**CRITICAL**: Always verify MIT-SHM stability with `XSync` to avoid `BadShmSeg` errors.
