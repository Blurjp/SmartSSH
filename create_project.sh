#!/bin/bash

echo "Creating Xcode project structure..."

# Create directories
mkdir -p SSHTerminal.xcodeproj
mkdir -p SSHTerminal/Views
mkdir -p SSHTerminal/Models
mkdir -p SSHTerminal/Services
mkdir -p SSHTerminal/ViewModels
mkdir -p SSHTerminal/Utils

echo "Project structure created!"
echo ""
echo "Now opening Xcode..."
echo ""
echo "Please follow these steps in Xcode:"
echo "1. File → New → Project (⌘⇧N)"
echo "2. Choose iOS → App"
echo "3. Configure:"
echo "   - Product Name: SSHTerminal"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "   - Storage: Core Data ✅"
echo "4. Save to: /Users/jianpinghuang/projects/"
echo "5. Name: SSHTerminal (will replace existing folder)"
echo ""

open -a Xcode

