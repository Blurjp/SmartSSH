#!/bin/bash

# SSH Terminal - iOS App Setup Script
# This script helps you set up the Xcode project

echo "🦞 SSH Terminal - iOS App Setup"
echo "================================"
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Xcode is not installed. Please install Xcode first."
    exit 1
fi

echo "✅ Xcode found"
echo ""

# Create project directory
PROJECT_DIR="/Users/jianpinghuang/projects/SmartSSH"
cd "$PROJECT_DIR"

echo "📁 Project directory: $PROJECT_DIR"
echo ""

# Instructions
echo "📋 Next Steps:"
echo ""
echo "1. Open Xcode"
echo "2. File → New → Project"
echo "3. Choose iOS → App"
echo "4. Configure:"
echo "   - Product Name: SmartSSH"
echo "   - Team: Your Apple Developer Team"
echo "   - Organization Identifier: com.yourcompany"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Storage: Core Data ✅"
echo "   - Include Tests: ✅"
echo ""
echo "5. Save to: /Users/jianpinghuang/projects/SmartSSH"
echo "   (Choose 'Replace' when prompted)"
echo ""
echo "6. After project is created, copy these files:"
echo ""
echo "   Views/:"
echo "   - ContentView.swift"
echo "   - HostsView.swift"
echo "   - AddHostView.swift"
echo "   - TerminalView.swift"
echo "   - KeysView.swift"
echo "   - SnippetsView.swift"
echo "   - SettingsView.swift"
echo ""
echo "   Services/:"
echo "   - DataController.swift"
echo "   - SSHManager.swift"
echo ""
echo "   Models/:"
echo "   - Host.swift"
echo ""
echo "7. Build and Run! 🚀"
echo ""

# Option to open in Xcode
read -p "Open project folder in Finder? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "$PROJECT_DIR"
fi

echo ""
echo "✨ Setup complete! Follow the steps above to create your Xcode project."
