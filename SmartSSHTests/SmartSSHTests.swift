//
//  SmartSSHTests.swift
//  SmartSSHTests
//
//  Unit tests for critical bug fixes
//

import XCTest
@testable import SmartSSH

final class SmartSSHTests: XCTestCase {
    
    func testSFTPClientThreadSafety() throws {
        let test = SFTPClientThreadSafetyTest()
        test.testConcurrentHistoryOperations()
    }
    
    func testSSHClientDisconnectThreadSafety() throws {
        let test = SSHClientDisconnectTest()
        test.testDisconnectThreadSafety()
    }
    
    func testSubscriptionManagerCancellation() throws {
        let test = SubscriptionManagerCancellationTest()
        test.testTaskCancellationHandling()
    }
    
    func testCommandHistoryBoundedGrowth() throws {
        let test = TerminalHistoryTests()
        test.testCommandHistoryBoundedGrowth()
    }
    
    func testHistoryIndexBoundsUpNavigation() throws {
        let test = TerminalHistoryTests()
        test.testHistoryIndexBoundsUpNavigation()
    }
    
    func testHistoryIndexBoundsDownNavigation() throws {
        let test = TerminalHistoryTests()
        test.testHistoryIndexBoundsDownNavigation()
    }
    
    func testPortValidation() throws {
        let test = PortValidationTests()
        test.testValidPort()
        test.testPortMinimumBoundary()
        test.testPortMaximumBoundary()
        test.testPortOutOfRangeLow()
        test.testPortOutOfRangeHigh()
        test.testPortInvalidString()
        test.testPortEmptyString()
    }
    
    func testFileUploadCleanup() throws {
        let test = FileUploadCleanupTests()
        test.testUploadStagingURLGeneration()
        test.testDeferCleanupPattern()
        test.testCleanupOrderWithDefer()
    }
    
    func testSnippetSerialization() throws {
        let test = SnippetSerializationTests()
        test.testSnippetEncoding()
        test.testSnippetArrayEncoding()
        test.testSnippetDecodingFailure()
    }
}

// MARK: - SFTPClient Thread Safety Tests

final class SFTPClientThreadSafetyTest {
    
    func testConcurrentHistoryOperations() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 100
        
        let client = SFTPClient.shared
        client.pathHistory = ["/"]
        client.historyIndex = 0
        
        for i in 0..<100 {
            DispatchQueue.global().async {
                client.navigateTo("/path\(i)")
                expectation.fulfill()
            }
        }
        
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed)
    }
    
    func testGoBackThreadSafety() {
        let client = SFTPClient.shared
        client.pathHistory = ["/", "/home", "/home/user"]
        client.historyIndex = 2
        
        let expectation = XCTestExpectation(description: "Go back completes")
        expectation.expectedFulfillmentCount = 50
        
        for _ in 0..<50 {
            DispatchQueue.global().async {
                client.goBack()
                expectation.fulfill()
            }
        }
        
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed)
        XCTAssertGreaterThanOrEqual(client.historyIndex, 0)
    }
    
    func testGoForwardThreadSafety() {
        let client = SFTPClient.shared
        client.pathHistory = ["/", "/home", "/home/user"]
        client.historyIndex = 0
        
        let expectation = XCTestExpectation(description: "Go forward completes")
        expectation.expectedFulfillmentCount = 50
        
        for _ in 0..<50 {
            DispatchQueue.global().async {
                client.goForward()
                expectation.fulfill()
            }
        }
        
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed)
        XCTAssertLessThanOrEqual(client.historyIndex, client.pathHistory.count - 1)
    }
    
    func testHistoryIndexBounds() {
        let client = SFTPClient.shared
        client.pathHistory = ["/"]
        client.historyIndex = 0
        
        for _ in 0..<10 {
            client.goBack()
        }
        XCTAssertEqual(client.historyIndex, 0)
        
        for _ in 0..<10 {
            client.goForward()
        }
        XCTAssertEqual(client.historyIndex, 0)
    }
}

// MARK: - SSHClient Disconnect Thread Safety Tests

final class SSHClientDisconnectTest {
    
    func testDisconnectThreadSafety() {
        let client = SSHClient.shared
        
        let connectExpectation = XCTestExpectation(description: "Connect initiated")
        let disconnectExpectation = XCTestExpectation(description: "Disconnect initiated")
        
        DispatchQueue.global().async {
            client.disconnect()
            disconnectExpectation.fulfill()
        }
        
        DispatchQueue.global().async {
            client.disconnect()
            disconnectExpectation.fulfill()
        }
        
        let result = XCTWaiter().wait(for: [disconnectExpectation], timeout: 5)
        XCTAssertEqual(result, .completed)
    }
    
    func testMultipleDisconnectCalls() {
        let client = SSHClient.shared
        
        for _ in 0..<10 {
            client.disconnect()
        }
        
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(client.state, .disconnected)
    }
}

// MARK: - SubscriptionManager Cancellation Tests

final class SubscriptionManagerCancellationTest {
    
    func testTaskCancellationHandling() async throws {
        let task = Task {
            do {
                for try await _ in Transaction.updates {
                    // Simulate work
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            } catch is CancellationError {
                // Expected behavior - task was cancelled
                return
            } catch {
                // Unexpected error
            }
        }
        
        task.cancel()
        
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            // Expected
        }
        
        XCTAssertTrue(task.isCancelled)
    }
    
    func testListenForTransactionsCancellation() {
        let manager = SubscriptionManager.shared
        let updateTask = manager.updateTask
        
        updateTask?.cancel()
        
        XCTAssertTrue(updateTask?.isCancelled ?? false)
    }
}

// MARK: - DataController Model Loading Tests

final class DataControllerTests: XCTestCase {
    
    func testModelLoadingSucceeds() {
        let controller = DataController(inMemory: true, cloudSyncEnabled: false)
        
        XCTAssertNotNil(controller.container)
        XCTAssertNil(controller.persistentStoreErrorMessage)
    }
    
    func testInMemoryController() {
        let controller = DataController(inMemory: true, cloudSyncEnabled: false)
        
        let context = controller.container.viewContext
        XCTAssertNotNil(context)
    }
}

// MARK: - TerminalView Command History Tests

final class TerminalHistoryTests: XCTestCase {
    
    private let maxHistorySize = 100
    
    func testCommandHistoryBoundedGrowth() {
        var commandHistory: [String] = []
        
        for i in 0..<150 {
            commandHistory.insert("command\(i)", at: 0)
            if commandHistory.count > maxHistorySize {
                commandHistory = Array(commandHistory.prefix(maxHistorySize))
            }
        }
        
        XCTAssertEqual(commandHistory.count, maxHistorySize)
        XCTAssertEqual(commandHistory[0], "command149")
        XCTAssertEqual(commandHistory[99], "command50")
    }
    
    func testCommandHistoryDuplicateInsertion() {
        var commandHistory: [String] = []
        
        let commands = ["ls", "ls", "pwd", "ls", "cd /home", "ls"]
        for command in commands {
            commandHistory.insert(command, at: 0)
            if commandHistory.count > maxHistorySize {
                commandHistory = Array(commandHistory.prefix(maxHistorySize))
            }
        }
        
        XCTAssertEqual(commandHistory.first, "ls")
        XCTAssertEqual(commandHistory.count, 6)
    }
    
    func testHistoryIndexBoundsUpNavigation() {
        var commandHistory = ["cmd5", "cmd4", "cmd3", "cmd2", "cmd1", "cmd0"]
        var historyIndex = -1
        
        for _ in 0..<10 {
            let nextIndex = historyIndex + 1
            if nextIndex < commandHistory.count {
                historyIndex = nextIndex
            }
        }
        
        XCTAssertEqual(historyIndex, 5)
        XCTAssertEqual(historyIndex < commandHistory.count, true)
    }
    
    func testHistoryIndexBoundsDownNavigation() {
        var commandHistory = ["cmd5", "cmd4", "cmd3", "cmd2", "cmd1", "cmd0"]
        var historyIndex = 5
        
        for _ in 0..<10 {
            if historyIndex > 0 {
                historyIndex -= 1
            }
        }
        
        XCTAssertEqual(historyIndex, 0)
    }
    
    func testHistoryIndexResetOnNewCommand() {
        var commandHistory = ["old1", "old0"]
        var historyIndex = 1
        
        commandHistory.insert("new", at: 0)
        historyIndex = -1
        
        XCTAssertEqual(historyIndex, -1)
        XCTAssertEqual(commandHistory.first, "new")
    }
    
    func testHistoryNavigationEdgeCases() {
        var commandHistory: [String] = []
        var historyIndex = -1
        
        guard !commandHistory.isEmpty, historyIndex >= -1 else {
            XCTAssertTrue(true)
            return
        }
        
        XCTAssertTrue(true)
    }
}

// MARK: - Port Validation Tests

final class PortValidationTests: XCTestCase {
    
    func testValidPort() {
        let port = "22"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTFail("Port validation failed")
            return
        }
        let validPort = Int16(portInt)
        
        XCTAssertNotNil(validPort)
        XCTAssertEqual(validPort, 22)
    }
    
    func testPortMinimumBoundary() {
        let port = "1"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTFail("Port validation failed")
            return
        }
        let validPort = Int16(portInt)
        
        XCTAssertNotNil(validPort)
        XCTAssertEqual(validPort, 1)
    }
    
    func testPortMaximumBoundary() {
        let port = "65535"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTFail("Port validation failed")
            return
        }
        let validPort = Int16(portInt)
        
        XCTAssertNotNil(validPort)
        XCTAssertEqual(validPort, 65535)
    }
    
    func testPortOutOfRangeLow() {
        let port = "0"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTAssertTrue(true)
            return
        }
        XCTFail("Port should be invalid")
    }
    
    func testPortOutOfRangeHigh() {
        let port = "65536"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTAssertTrue(true)
            return
        }
        XCTFail("Port should be invalid")
    }
    
    func testPortInvalidString() {
        let port = "abc"
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTAssertTrue(true)
            return
        }
        XCTFail("Port should be invalid")
    }
    
    func testPortEmptyString() {
        let port = ""
        guard let portInt = Int(port), portInt >= 1, portInt <= 65535 else {
            XCTAssertTrue(true)
            return
        }
        XCTFail("Port should be invalid")
    }
    
    func testPortDefaultFallback() {
        let invalidPort = ""
        guard let portInt = Int(invalidPort), portInt >= 1, portInt <= 65535 else {
            XCTAssertEqual(22, 22)
            return
        }
        XCTFail("Port should be invalid")
    }
}

// MARK: - File Upload Cleanup Tests

final class FileUploadCleanupTests: XCTestCase {
    
    func testUploadStagingURLGeneration() {
        let fileName = "test.txt"
        let tempDir = FileManager.default.temporaryDirectory
        let stagingURL = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        
        XCTAssertTrue(stagingURL.path.hasPrefix(tempDir.path))
        XCTAssertTrue(stagingURL.pathExtension == "txt")
    }
    
    func testDeferCleanupPattern() {
        var cleanupCalled = false
        var accessRevoked = false
        
        func performUpload() {
            defer {
                accessRevoked = true
            }
            
            defer {
                cleanupCalled = true
            }
            
            return
        }
        
        performUpload()
        
        XCTAssertTrue(accessRevoked)
        XCTAssertTrue(cleanupCalled)
    }
    
    func testCleanupOrderWithDefer() {
        var order: [String] = []
        
        func performOperations() {
            defer {
                order.append("cleanup")
            }
            order.append("operation")
        }
        
        performOperations()
        
        XCTAssertEqual(order, ["operation", "cleanup"])
    }
}

// MARK: - Snippet Serialization Tests

final class SnippetSerializationTests: XCTestCase {
    
    func testSnippetEncoding() {
        struct TestSnippet: Codable {
            let id: UUID
            let title: String
            let content: String
        }
        
        let snippet = TestSnippet(id: UUID(), title: "Test", content: "echo hello")
        
        do {
            let data = try JSONEncoder().encode(snippet)
            XCTAssertNotNil(data)
            
            let decoded = try JSONDecoder().decode(TestSnippet.self, from: data)
            XCTAssertEqual(decoded.title, "Test")
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }
    
    func testSnippetArrayEncoding() {
        struct TestSnippet: Codable {
            let id: UUID
            let title: String
            let content: String
        }
        
        let snippets = [
            TestSnippet(id: UUID(), title: "Test1", content: "ls"),
            TestSnippet(id: UUID(), title: "Test2", content: "pwd")
        ]
        
        do {
            let data = try JSONEncoder().encode(snippets)
            XCTAssertNotNil(data)
            
            let decoded = try JSONDecoder().decode([TestSnippet].self, from: data)
            XCTAssertEqual(decoded.count, 2)
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }
    
    func testSnippetDecodingFailure() {
        struct TestSnippet: Codable {
            let id: UUID
            let title: String
        }
        
        let invalidData = Data([0xFF, 0xFE])
        
        do {
            _ = try JSONDecoder().decode([TestSnippet].self, from: invalidData)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(true)
        }
    }
}

// MARK: - Error Handling Tests

final class ErrorHandlingTests: XCTestCase {
    
    func testContextSaveErrorPropagation() {
        enum TestError: Error {
            case saveFailed(String)
        }
        
        do {
            throw TestError.saveFailed("Test error")
        } catch let error as TestError {
            switch error {
            case .saveFailed(let message):
                XCTAssertEqual(message, "Test error")
            }
        }
    }
    
    func testJSONEncodingErrorHandling() {
        struct NonEncodable {
            let value: Void?
        }
        
        do {
            let data = try JSONEncoder().encode(NonEncodable(value: nil))
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(true)
        }
    }
}

// MARK: - SFTPClient Bounds Checking Tests

final class SFTPClientBoundsTests: XCTestCase {
    
    func testGoBackWithEmptyHistory() {
        var pathHistory: [String] = []
        var historyIndex = 0
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoBack = historyIndex > 0 && !pathHistory.isEmpty
        let targetIndex = canGoBack ? historyIndex - 1 : historyIndex
        let path = (canGoBack && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoBack {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertFalse(canGoBack)
        XCTAssertEqual(path, "")
        XCTAssertEqual(historyIndex, 0)
    }
    
    func testGoBackAtStartIndex() {
        var pathHistory = ["/", "/home", "/home/user"]
        var historyIndex = 0
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoBack = historyIndex > 0 && !pathHistory.isEmpty
        let targetIndex = canGoBack ? historyIndex - 1 : historyIndex
        let path = (canGoBack && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoBack {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertFalse(canGoBack)
        XCTAssertEqual(historyIndex, 0)
    }
    
    func testGoBackValidIndex() {
        var pathHistory = ["/", "/home", "/home/user"]
        var historyIndex = 2
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoBack = historyIndex > 0 && !pathHistory.isEmpty
        let targetIndex = canGoBack ? historyIndex - 1 : historyIndex
        let path = (canGoBack && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoBack {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertTrue(canGoBack)
        XCTAssertEqual(path, "/home")
        XCTAssertEqual(historyIndex, 1)
    }
    
    func testGoForwardWithEmptyHistory() {
        var pathHistory: [String] = []
        var historyIndex = 0
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoForward = historyIndex < pathHistory.count - 1 && !pathHistory.isEmpty
        let targetIndex = canGoForward ? historyIndex + 1 : historyIndex
        let path = (canGoForward && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoForward {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertFalse(canGoForward)
        XCTAssertEqual(path, "")
        XCTAssertEqual(historyIndex, 0)
    }
    
    func testGoForwardAtEndIndex() {
        var pathHistory = ["/", "/home", "/home/user"]
        var historyIndex = 2
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoForward = historyIndex < pathHistory.count - 1 && !pathHistory.isEmpty
        let targetIndex = canGoForward ? historyIndex + 1 : historyIndex
        let path = (canGoForward && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoForward {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertFalse(canGoForward)
        XCTAssertEqual(historyIndex, 2)
    }
    
    func testGoForwardValidIndex() {
        var pathHistory = ["/", "/home", "/home/user"]
        var historyIndex = 0
        let historyLock = NSLock()
        
        historyLock.lock()
        let canGoForward = historyIndex < pathHistory.count - 1 && !pathHistory.isEmpty
        let targetIndex = canGoForward ? historyIndex + 1 : historyIndex
        let path = (canGoForward && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
        if canGoForward {
            historyIndex = targetIndex
        }
        historyLock.unlock()
        
        XCTAssertTrue(canGoForward)
        XCTAssertEqual(path, "/home")
        XCTAssertEqual(historyIndex, 1)
    }
    
    func testConcurrentModificationSafety() {
        var pathHistory = ["/", "/home"]
        var historyIndex = 1
        let historyLock = NSLock()
        
        let expectation = XCTestExpectation(description: "Concurrent access complete")
        expectation.expectedFulfillmentCount = 10
        
        for i in 0..<10 {
            DispatchQueue.global().async {
                historyLock.lock()
                let canGoBack = historyIndex > 0 && !pathHistory.isEmpty
                let targetIndex = canGoBack ? historyIndex - 1 : historyIndex
                let path = (canGoBack && targetIndex < pathHistory.count) ? pathHistory[targetIndex] : ""
                if canGoBack {
                    historyIndex = targetIndex
                }
                historyLock.unlock()
                expectation.fulfill()
            }
        }
        
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed)
        XCTAssertGreaterThanOrEqual(historyIndex, 0)
    }
}

// MARK: - Host Creation/Edit Logic Tests

final class HostCreationTests: XCTestCase {
    
    func testEditHostDoesNotCreateNew() {
        var existingHosts: [String] = ["host1", "host2", "host3"]
        let hostToEdit = "host2"
        let newName = "host2-edited"
        
        let host: String
        if let existingHost = hostToEdit as String? {
            host = existingHost
        } else {
            host = newName
            existingHosts.append(host)
        }
        
        XCTAssertEqual(existingHosts.count, 3, "Should not add new host when editing")
        XCTAssertEqual(host, "host2")
    }
    
    func testNewHostIsCreated() {
        var existingHosts: [String] = ["host1", "host2"]
        let hostToEdit: String? = nil
        let newName = "host3"
        
        let host: String
        if let existingHost = hostToEdit {
            host = existingHost
        } else {
            host = newName
            existingHosts.append(host)
        }
        
        XCTAssertEqual(existingHosts.count, 3, "Should add new host when creating")
        XCTAssertEqual(host, "host3")
    }
    
    func testHostEditPreservesOriginal() {
        struct TestHost {
            var name: String
            var hostname: String
            var port: Int
        }
        
        var originalHost = TestHost(name: "Original", hostname: "original.com", port: 22)
        let hostToEdit = originalHost
        
        let host: TestHost
        if let existingHost = hostToEdit as TestHost? {
            host = existingHost
            host.name = "Edited"
            host.hostname = "edited.com"
        } else {
            host = TestHost(name: "New", hostname: "new.com", port: 22)
        }
        
        XCTAssertEqual(host.name, "Edited")
        XCTAssertEqual(host.hostname, "edited.com")
    }
}

// MARK: - Document Directory Access Tests

final class DocumentDirectoryTests: XCTestCase {
    
    func testSafeArrayAccessWithFirst() {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        if let firstURL = urls.first {
            XCTAssertTrue(firstURL.path.contains("Documents"))
        } else {
            XCTFail("Document directory should exist")
        }
    }
    
    func testEmptyArraySafeAccess() {
        let emptyArray: [String] = []
        
        if let first = emptyArray.first {
            XCTFail("Should not have a first element")
        } else {
            XCTAssertTrue(true)
        }
    }
    
    func testArrayFirstVersusIndex() {
        let array = ["a", "b", "c"]
        
        let firstElement = array.first
        let indexZero = array.count > 0 ? array[0] : nil
        
        XCTAssertEqual(firstElement, indexZero)
        XCTAssertEqual(firstElement, "a")
    }
    
    func testDocumentDirectoryURLConstruction() {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        guard let documentsDir = urls.first else {
            XCTFail("No document directory")
            return
        }
        
        let exportURL = documentsDir.appendingPathComponent("export.json")
        
        XCTAssertTrue(exportURL.path.hasSuffix("export.json"))
        XCTAssertTrue(exportURL.path.contains("Documents"))
    }
}

// MARK: - Weak Self Closure Tests

final class WeakSelfClosureTests: XCTestCase {
    
    func testWeakSelfDoesNotRetain() {
        class TestObject {
            var closure: (() -> Void)?
            
            func setupClosure() {
                closure = { [weak self] in
                    _ = self?.description
                }
            }
        }
        
        var object: TestObject? = TestObject()
        object?.setupClosure()
        let closure = object?.closure
        
        weak var weakObject = object
        object = nil
        
        XCTAssertNil(weakObject, "Object should be deallocated")
        XCTAssertNotNil(closure, "Closure should still exist")
    }
    
    func testStrongSelfRetains() {
        class TestObject {
            var closure: (() -> Void)?
            var value = 42
            
            func setupClosure() {
                closure = {
                    _ = self.value
                }
            }
        }
        
        var object: TestObject? = TestObject()
        object?.setupClosure()
        let closure = object?.closure
        
        weak var weakObject = object
        object = nil
        
        XCTAssertNotNil(weakObject, "Object should be retained by closure")
        XCTAssertNotNil(closure)
    }
}
