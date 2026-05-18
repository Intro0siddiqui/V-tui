# Vtui Product Guidelines

## Code Style & Conventions
*   **Language:** Primary development in **Zig**, with an openness to **Rust** if it better serves the project's performance or safety goals.
*   **Naming:** Strictly follow Zig's standard (PascalCase for types, camelCase for fields and functions).
*   **Constants:** Use `SCREAMING_SNAKE_CASE` for all constant values (e.g., `DEFAULT_WIDTH`).
*   **Error Handling:** Employ strict error sets and use the `try` keyword for all fallible operations to ensure robust error propagation.
*   **Memory Management:** Prioritize zero-allocation patterns and explicit memory ownership.

## Documentation Strategy
*   **Selective Documentation:** Focus docstrings (`///`) on complex logic, non-obvious behaviors, and public-facing APIs.
*   **Verification:** Use the built-in screenshot and comparison tools (`compare-foot.sh`) to verify visual improvements and performance regressions.

## Development Principles
*   **Production Readiness:** Every change must move the engine toward a state of being reliable and production-ready.
*   **Performance First:** Prioritize high-performance, cache-friendly data structures and algorithms.
*   **Pixel Accuracy:** All rendering must be verified for pixel-perfect consistency against reference implementations (like the `foot` terminal). Note: Because `foot` uses a custom configuration that affects automated calculations, the AI agent MUST manually read and visually compare the PNG screenshots (e.g., `screenshot.png` vs. `foot_screenshot.png`) to judge improvements or regressions.
