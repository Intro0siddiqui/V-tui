# Specification: Sixel Graphics Support

## Overview
This track aims to ensure robust and feature-complete Sixel graphics support in Vtui. While core parsing and rendering are implemented, this track focuses on verification, handling edge cases (like transparency and raster attributes), and ensuring seamless integration with the grid and renderer.

## Functional Requirements
*   **Complete Parser Implementation:** Ensure the Sixel parser correctly handles all DCS parameters (P1, P2, P3) and DECGRA raster attributes.
*   **Transparency Support:** Implement Sixel transparency (P2=1) correctly in the renderer blitter.
*   **Grid Integration:** Verify that Sixel images are correctly positioned, cleared on text writes, and shifted during scrolling.
*   **Renderer Polishing:** Ensure scaled and direct blitting are performance-optimized and pixel-accurate.
*   **Verification:** Create a suite of Sixel test patterns and compare rendering against the reference `foot` terminal.

## Non-Functional Requirements
*   **Performance:** Sixel parsing and blitting should be optimized to minimize overhead on the main rendering loop.
*   **Memory Efficiency:** Adhere to Sixel memory limits and ensure proper deallocation of image data.

## Acceptance Criteria
*   Successfully render complex Sixel patterns (e.g., from `neofetch` or specific test tools).
*   Correctly handle transparency in Sixel images.
*   Verify that images are cleared or shifted appropriately during grid operations.
*   Pass all automated Sixel parser and renderer tests.

## Out of Scope
*   Implementation of iTerm2 or Kitty graphics protocols (reserved for future tracks).
*   Wayland or macOS display backend support.
