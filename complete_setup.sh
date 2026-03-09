#!/bin/bash

# SSH Terminal - Complete Setup Script
# This script sets up everything for the project

set -e

echo "🦞 SSH Terminal - Complete Setup"
echo "=================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project directory
PROJECT_DIR="/Users/jianpinghuang/projects/SmartSSH"
cd "$PROJECT_DIR"

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Step 1: Check prerequisites
echo "Step 1: Checking prerequisites..."

if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -1)
    print_status "Xcode found: $XCODE_VERSION"
else
    print_error "Xcode not found. Please install Xcode first."
    exit 1
fi

if command -v xcodegen &> /dev/null; then
    print_status "xcodegen found"
else
    print_warning "xcodegen not found. Installing..."
    brew install xcodegen
    print_status "xcodegen installed"
fi

# Step 2: Generate Xcode project
echo ""
echo "Step 2: Generating Xcode project..."
xcodegen generate
print_status "Xcode project generated"

# Step 3: Install CocoaPods (optional)
echo ""
echo "Step 3: Checking CocoaPods..."

if command -v pod &> /dev/null; then
    print_status "CocoaPods found"
    
    read -p "Install dependencies with CocoaPods? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pod install
        print_status "Dependencies installed"
        echo ""
        echo "⚠️  Note: Use SmartSSH.xcworkspace instead of .xcodeproj"
    fi
else
    print_warning "CocoaPods not found. Skipping dependency installation."
    echo "To install CocoaPods: sudo gem install cocoapods"
fi

# Step 4: Create App Icon
echo ""
echo "Step 4: App Icon..."

ICON_DIR="$PROJECT_DIR/SmartSSH/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICON_DIR" ]; then
    print_status "App icon assets directory exists"
    echo ""
    echo "⚠️  App icons need to be added manually:"
    echo "   1. Create a 1024x1024 icon"
    echo "   2. Use app-icon-generator.com to generate all sizes"
    echo "   3. Add PNG files to: $ICON_DIR"
else
    print_warning "App icon directory not found"
fi

# Step 5: Summary
echo ""
echo "=================================="
echo "🎉 Setup Complete!"
echo "=================================="
echo ""
echo "📁 Project Location:"
echo "   $PROJECT_DIR"
echo ""
echo "🚀 Next Steps:"
echo ""
echo "1. Open the project:"
if [ -f "SmartSSH.xcworkspace" ]; then
    echo "   open SmartSSH.xcworkspace"
else
    echo "   open SmartSSH.xcodeproj"
fi
echo ""
echo "2. Configure signing:"
echo "   - Select project → Signing & Capabilities"
echo "   - Choose your Apple Developer Team"
echo ""
echo "3. Configure OpenAI (optional):"
echo "   - Edit Services/AIService.swift"
echo "   - Add your API key"
echo ""
echo "4. Configure StoreKit (optional):"
echo "   - Create products in App Store Connect"
echo "   - Update Services/SubscriptionManager.swift"
echo ""
echo "5. Run the app:"
echo "   - Select simulator or device"
echo "   - Press ⌘ + R"
echo ""
echo "📚 Documentation:"
echo "   - README.md - Project overview"
echo "   - FEATURES.md - Complete feature list"
echo "   - QUICKSTART.md - Quick start guide"
echo ""
echo "🦞 Happy coding!"
