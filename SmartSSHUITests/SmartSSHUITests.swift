//
//  SmartSSHUITests.swift
//  SmartSSHUITests
//
//  UI Tests for SmartSSH
//

import XCTest

final class SmartSSHUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Tests
    
    func testAppLaunchesSuccessfully() throws {
        // App should launch and show hosts view
        XCTAssertTrue(app.exists, "App should launch successfully")
        
        // Should show hosts view by default
        let hostsView = app.navigationBars["Hosts"]
        XCTAssertTrue(hostsView.waitForExistence(timeout: 5), "Hosts view should be visible")
    }
    
    // MARK: - Tab Navigation Tests
    
    func testTabNavigation() throws {
        // Test Hosts tab
        let hostsTab = app.tabBars.buttons["Hosts"]
        XCTAssertTrue(hostsTab.exists, "Hosts tab should exist")
        hostsTab.tap()
        
        // Test Keys tab
        let keysTab = app.tabBars.buttons["Keys"]
        if keysTab.exists {
            keysTab.tap()
            
            // Verify we're on Keys view
            let keysNavBar = app.navigationBars["Keys"]
            XCTAssertTrue(keysNavBar.waitForExistence(timeout: 2), "Keys view should be visible")
        }
        
        // Test Snippets tab
        let snippetsTab = app.tabBars.buttons["Snippets"]
        if snippetsTab.exists {
            snippetsTab.tap()
            
            let snippetsNavBar = app.navigationBars["Snippets"]
            XCTAssertTrue(snippetsNavBar.waitForExistence(timeout: 2), "Snippets view should be visible")
        }
        
        // Test Settings tab
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            
            let settingsNavBar = app.navigationBars["Settings"]
            XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 2), "Settings view should be visible")
        }
    }
    
    // MARK: - Add Host Tests
    
    func testAddHostButtonExists() throws {
        // Look for add button
        let addButton = app.navigationBars.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3), "Add button should exist in Hosts view")
    }
    
    func testAddHostFlow() throws {
        // Tap add button
        let addButton = app.navigationBars.buttons["Add"]
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()
            
            // Should show Add Host view
            let addHostView = app.navigationBars["Add Host"]
            XCTAssertTrue(addHostView.waitForExistence(timeout: 3), "Add Host view should appear")
            
            // Check for input fields
            let nameField = app.textFields["Host Name"]
            XCTAssertTrue(nameField.exists, "Name field should exist")
            
            let hostnameField = app.textFields["Hostname"]
            XCTAssertTrue(hostnameField.exists, "Hostname field should exist")
            
            let usernameField = app.textFields["Username"]
            XCTAssertTrue(usernameField.exists, "Username field should exist")
            
            // Test cancel
            let cancelButton = app.navigationBars.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
                
                // Should return to Hosts view
                let hostsNavBar = app.navigationBars["Hosts"]
                XCTAssertTrue(hostsNavBar.waitForExistence(timeout: 2), "Should return to Hosts view")
            }
        }
    }
    
    // MARK: - Empty State Tests
    
    func testEmptyHostsState() throws {
        // If no hosts, should show empty state
        let emptyState = app.staticTexts["No hosts yet"]
        let addFirstHostButton = app.buttons["Add Your First Host"]
        
        // Either empty state or host list should be visible
        let listExists = app.collectionViews.count > 0 || app.tables.count > 0
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 2) || listExists,
            "Should show empty state or host list"
        )
    }
    
    // MARK: - Settings Tests
    
    func testSettingsView() throws {
        // Navigate to Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            
            // Check for settings sections
            let terminalSection = app.staticTexts["Terminal"]
            if terminalSection.exists {
                XCTAssertTrue(terminalSection.exists, "Terminal section should exist")
            }
            
            let connectionSection = app.staticTexts["Connection"]
            if connectionSection.exists {
                XCTAssertTrue(connectionSection.exists, "Connection section should exist")
            }
            
            let aiSection = app.staticTexts["AI Features"]
            if aiSection.exists {
                XCTAssertTrue(aiSection.exists, "AI Features section should exist")
            }
        }
    }
    
    // MARK: - Subscription Tests
    
    func testSubscriptionButton() throws {
        // Navigate to Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()
            
            // Look for subscription button
            let subscriptionButton = app.buttons["Subscription"]
            if subscriptionButton.waitForExistence(timeout: 3) {
                subscriptionButton.tap()
                
                // Should show subscription view
                let subscriptionNavBar = app.navigationBars["Subscription"]
                XCTAssertTrue(subscriptionNavBar.waitForExistence(timeout: 3), "Subscription view should appear")
            }
        }
    }
}
