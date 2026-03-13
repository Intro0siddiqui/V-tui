# Vtui Development Workflow

## 1. Task-Driven Development (TDD)
*   Every task must start with a corresponding unit test in `src/` or a new test file.
*   **Target Coverage:** Maintain a minimum of **85%** test coverage for all new code.
*   **Visual Verification:** For any changes affecting rendering, you MUST run `./test-render.sh` and `./compare-foot.sh` to verify pixel accuracy against the reference terminal.

## 2. Commit Strategy
*   **Frequency:** Commit changes after every successfully completed task.
*   **Messages:** Follow conventional commit standards (e.g., `feat:`, `fix:`, `chore:`).
*   **Summaries:** Store detailed task summaries in **Git Notes** to keep the commit history clean while preserving technical context.

## 3. Phase Completion Protocol
*   At the end of each phase, perform a full build and run all tests (`zig build test`).
*   Verify the final output visually using the `neofetch` and `btop` screenshots.
*   Update the `metadata.json` for the corresponding track to mark the phase as complete.

## 4. Architectural Integrity
*   Consult `AGENTS.md` and the `refs/` directory before making structural changes.
*   Prioritize performance and zero-allocation patterns in all rendering and parsing code.
