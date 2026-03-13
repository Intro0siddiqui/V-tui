# Implementation Plan: Sixel Graphics Support

## Phase 1: Verification and Bug Identification
- [ ] Task: Create a comprehensive Sixel test suite
    - [ ] Write unit tests in `src/sixel.zig` for all DCS parameter combinations (P1, P2, P3).
    - [ ] Create a standalone `test_sixel_rendering.zig` to verify direct and scaled blitting.
- [ ] Task: Run current Sixel implementation against complex patterns
    - [ ] Use `neofetch` and `btop` with Sixel output enabled.
    - [ ] Use `test-render.sh` to capture and compare PPM screenshots against `foot`.
- [ ] Task: Identify and document any rendering or parsing regressions.
- [ ] Task: Conductor - User Manual Verification 'Phase 1: Verification and Bug Identification' (Protocol in workflow.md)

## Phase 2: Parser and Renderer Polishing
- [ ] Task: Refine Sixel transparency support
    - [ ] Write Tests: Ensure `SixelImage.data` correctly preserves alpha information from DCS P2=1.
    - [ ] Implement: Update `Renderer.blitSixelImageDirect/Scaled` to support per-pixel alpha blending.
- [ ] Task: Correctly handle DECGRA Raster Attributes
    - [ ] Write Tests: Verify `SixelParser` correctly applies pan, pad, width, and height.
    - [ ] Implement: Ensure image pre-allocation and aspect ratio calculation are accurate.
- [ ] Task: Optimize Sixel image storage in Grid
    - [ ] Write Tests: Verify images are correctly cleared when text is written over them.
    - [ ] Implement: Ensure memory is freed properly during grid clear and resize operations.
- [ ] Task: Conductor - User Manual Verification 'Phase 2: Parser and Renderer Polishing' (Protocol in workflow.md)

## Phase 3: Performance and Integration
- [ ] Task: Optimize Sixel blitting performance
    - [ ] Write Tests: Benchmark blitting for high-resolution Sixel images.
    - [ ] Implement: Apply SIMD optimizations (Zig `@Vector`) for Sixel pixel blitting where possible.
- [ ] Task: Integrate Sixel support into main PTY loop
    - [ ] Write Tests: Ensure PTY reads correctly pass Sixel sequences to the parser.
    - [ ] Implement: Verify seamless rendering during high-frequency PTY updates.
- [ ] Task: Conductor - User Manual Verification 'Phase 3: Performance and Integration' (Protocol in workflow.md)
