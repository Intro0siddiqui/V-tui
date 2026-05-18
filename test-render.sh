#!/bin/bash
# Test Vtui rendering and save a screenshot as PPM
# Usage: ./test-render.sh [cmd]

CMD=${1:-neofetch}
OUTPUT_PPM="screenshot.ppm"
OUTPUT_PNG="screenshot.png"

# Clean up existing files
rm -f "${OUTPUT_PPM}" "${OUTPUT_PNG}"

echo "=== Building Vtui ==="
./build-install.sh

echo ""
echo "=== Running ${CMD} and saving to ${OUTPUT_PPM} ==="
# Run with a short timeout to ensure it captures something then exits
# For neofetch it exits normally, for btop we might need to kill it
if [ "${CMD}" == "btop" ]; then
    timeout 5s ./zig-out/bin/vtui --save-ppm "${OUTPUT_PPM}" btop || true
else
    ./zig-out/bin/vtui --save-ppm "${OUTPUT_PPM}" "${CMD}"
fi

if [ -f "${OUTPUT_PPM}" ]; then
    echo "✓ Screenshot saved to ${OUTPUT_PPM}"
    echo "=== Converting to PNG ==="
    convert "${OUTPUT_PPM}" "${OUTPUT_PNG}"
    if [ -f "${OUTPUT_PNG}" ]; then
        echo "✓ PNG saved to ${OUTPUT_PNG}"
        rm -f "${OUTPUT_PPM}"
        ls -lh "${OUTPUT_PNG}"
    else
        echo "✗ Failed to convert to PNG"
        ls -lh "${OUTPUT_PPM}"
    fi
else
    echo "✗ Failed to save screenshot"
fi
