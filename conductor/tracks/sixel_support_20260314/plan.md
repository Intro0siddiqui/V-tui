# Implementation Plan: Sixel Graphics Support (Foot-Level Refinement Loop)

## Phase 1: Baseline Establishment (Initial Capability)
- [x] Task: Establish Performance & Fidelity Baseline
    - [x] Run `test-render.sh` to capture current Sixel output (e.g., using `neofetch`).
    - [x] Run `compare-foot.sh` to capture reference output from `foot`.
    - [x] Use a tool like `magick compare` or manual inspection of `diff.png` to quantify the 'Fidelity Gap'.
- [ ] Task: Conductor - User Manual Verification 'Baseline Establishment' (Protocol in workflow.md)

## Phase 2: Iterative Refinement & Optimization Loop (Recurrent)
*This phase is repeated until Sixel rendering reaches 'foot-level' quality and performance.*

- [ ] Task: Identify Current Primary Bottleneck or Fidelity Issue
    - [ ] Analyze: Is it Transparency (P2=1)? Raster Attributes (DECGRA)? SIMD Performance?
- [ ] Task: Implement Targeted Improvement
    - [ ] Write Tests: Create a reproduction/test case for the identified issue.
    - [ ] Implement: Apply the fix or optimization (e.g., SIMD blitting, alpha-blending logic).
- [ ] Task: Re-Verify and Benchmark
    - [ ] Run `test-render.sh` and compare the new output to both the previous 'Baseline' and the 'Foot Reference'.
    - [ ] Measure Performance: Capture the blit time and compare with previous iterations.
- [ ] Task: Loop Decision: 'Are we at Foot-Level yet?'
    - [ ] If NO: Reset sub-tasks and repeat this phase for the next improvement.
    - [ ] If YES: Proceed to Final Integration.
- [ ] Task: Conductor - User Manual Verification 'Refinement Loop' (Protocol in workflow.md)

## Phase 3: Final Integration & Stability
- [ ] Task: Verify Full Grid & Scrollback Integration
    - [ ] Ensure Sixel images remain stable during heavy PTY I/O and window resizing.
    - [ ] Verify proper memory deallocation for multiple high-resolution images.
- [ ] Task: Final Build and Stress Test
    - [ ] Run `zig build test` and verify 85% coverage.
    - [ ] Perform a final visual check with `btop` and `neofetch`.
- [ ] Task: Conductor - User Manual Verification 'Final Integration' (Protocol in workflow.md)
