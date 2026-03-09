#!/bin/bash

echo "Creating Xcode project structure..."

# Create directories
mkdir -p SmartSSH.xcodeproj
mkdir -p SmartSSH/Views
mkdir -p SmartSSH/Models
mkdir -p SmartSSH/Services
mkdir -p SmartSSH/ViewModels
mkdir -p SmartSSH/Utils

echo "Project structure created!"
echo ""
echo "Now opening Xcode..."
echo ""
echo "Please follow these steps in Xcode:"
echo "1. File → New → Project (⌘⇧N)"
echo "2. Choose iOS → App"
echo "3. Configure:"
echo "   - Product Name: SmartSSH"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Storage: Core Data ✅"
echo "4. Save to: /Users/jianpinghuang/projects/"
echo "5. Name: SmartSSH (will replace existing folder)"
echo ""

open -a Xcode

