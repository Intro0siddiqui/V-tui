# Zig Code Style Guide for Vtui

## Naming
*   **Types:** [PascalCase](https://en.wikipedia.org/wiki/PascalCase) (e.g., `CellFlags`, `Grid`).
*   **Variables:** [snake_case](https://en.wikipedia.org/wiki/Snake_case) (e.g., `cell_flags`, `grid_state`).
*   **Functions:** [camelCase](https://en.wikipedia.org/wiki/Camel_case) (e.g., `processByte()`, `initGrid()`).
*   **Constants:** `SCREAMING_SNAKE_CASE` (e.g., `DEFAULT_WIDTH`, `DEFAULT_HEIGHT`).

## Error Handling
*   **Explicit Returns:** Use `error sets` for all fallible operations.
*   **Try Pattern:** Prefer using the `try` keyword for robust error propagation.
*   **Clear Error Sets:** Define specific error names that help diagnose failures (e.g., `OpenFailed`, `ParseFailed`).

## Memory Management
*   **Ownership:** Be explicit about who owns and frees memory.
*   **Zero-Allocation:** Prioritize zero-allocation state machines and flat buffers (e.g., `Parser` and `Grid`).
*   **Allocation Tracking:** Use `std.testing.allocator` in unit tests to catch memory leaks early.

## Style & Formatting
*   **Unused Parameters:** Use `_ = var;` or change to `const` to satisfy the compiler.
*   **Integer Casting:** Use `@intCast()` when converting types to ensure safety.
*   **Formatting:** Zig's standard library `std.fmt` supports byte-based alignment. Handle Unicode alignment manually when necessary.

## Modules & Imports
*   **Import Style:** Group standard library imports at the top, followed by local module imports.
*   **Clarity:** Use clear, descriptive names for imported modules (e.g., `const Grid = @import("grid.zig").Grid;`).
