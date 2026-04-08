#!/bin/bash
# Build script for iOS XCFramework
# This script compiles the Go backend to XCFramework for iOS
# Must be run on macOS with Xcode installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_BACKEND_DIR="$PROJECT_DIR/go_backend"
IOS_DIR="$PROJECT_DIR/ios"
OUTPUT_DIR="$IOS_DIR/Frameworks"

echo "=== SpotiFLAC iOS Build Script ==="
echo "Project directory: $PROJECT_DIR"
echo "Go backend directory: $GO_BACKEND_DIR"
echo "Output directory: $OUTPUT_DIR"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script must be run on macOS"
    exit 1
fi

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install Go first."
    exit 1
fi

echo "Go version: $(go version)"

# Check if gomobile is installed
if ! command -v gomobile &> /dev/null; then
    echo "Installing gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
fi

# Initialize gomobile (required for iOS builds)
echo "Initializing gomobile..."
gomobile init

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Navigate to Go backend directory
cd "$GO_BACKEND_DIR"

# Download dependencies
echo "Downloading Go dependencies..."
go mod download
go mod tidy

# Build XCFramework for iOS
echo "Building XCFramework for iOS..."
gomobile bind -target=ios -o "$OUTPUT_DIR/Gobackend.xcframework" .

# Verify output
if [ -d "$OUTPUT_DIR/Gobackend.xcframework" ]; then
    echo "✅ Successfully built Gobackend.xcframework"
    echo "Output: $OUTPUT_DIR/Gobackend.xcframework"
    
    # List architectures
    echo ""
    echo "Architectures included:"
    ls -la "$OUTPUT_DIR/Gobackend.xcframework/"
else
    echo "❌ Failed to build XCFramework"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo "Next steps:"
echo "1. Open ios/Runner.xcworkspace in Xcode"
echo "2. Add Gobackend.xcframework to the project"
echo "3. Build and run the app"
