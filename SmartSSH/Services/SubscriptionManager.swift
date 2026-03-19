//
//  SubscriptionManager.swift
//  SSH Terminal
//
//  StoreKit subscription management
//

import Foundation
import StoreKit

// MARK: - Subscription Product

enum SubscriptionTier: String, CaseIterable {
    case free = "free"
    case pro = "com.smartssh.pro.monthly"
    case proYearly = "com.smartssh.pro.yearly"
    case team = "com.smartssh.team.monthly"
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro Monthly"
        case .proYearly: return "Pro Yearly"
        case .team: return "Team"
        }
    }
    
    var price: String {
        switch self {
        case .free: return "Free"
        case .pro: return "$4.99/month"
        case .proYearly: return "$49/year (Save 17%)"
        case .team: return "$9.99/user/month"
        }
    }
    
    var features: [String] {
        switch self {
        case .free:
            return [
                "5 Hosts",
                "Basic SSH Features",
                "Terminal Access",
                "Local Storage"
            ]
        case .pro, .proYearly:
            return [
                "Unlimited Hosts",
                "iCloud Sync",
                "SFTP Browser",
                "Code Snippets",
                "Priority Support"
            ]
        case .team:
            return [
                "Everything in Pro",
                "Shared Hosts",
                "Team Management",
                "Audit Logs",
                "SSO Integration",
                "Dedicated Support"
            ]
        }
    }
}

// MARK: - Subscription Manager

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var products: [Product] = []
    @Published var purchasedSubscriptions: [Product] = []
    @Published var currentTier: SubscriptionTier = .free
    @Published var isLoading: Bool = false
    @Published var restoreMessage: String?
    
    private var updateTask: Task<Void, Error>?
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--uitesting")
    #if targetEnvironment(simulator)
    private let shouldSkipStoreKitSetup = true
    #else
    private let shouldSkipStoreKitSetup = false
    #endif
    
    init() {
        guard !isUITesting, !shouldSkipStoreKitSetup else { return }

        // Listen for transaction updates
        updateTask = listenForTransactions()
        
        // Load products
        Task {
            await loadProducts()
            await updateCurrentSubscription()
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
    
    // MARK: - Load Products
    
    func loadProducts() async {
        isLoading = true
        
        do {
            let storeProducts = try await Product.products(for: [
                SubscriptionTier.pro.rawValue,
                SubscriptionTier.proYearly.rawValue,
                SubscriptionTier.team.rawValue
            ])
            
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Purchase
    
    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            
            // Deliver content
            await updateCurrentSubscription()
            
            // Finish transaction
            await transaction.finish()
            
            return transaction
            
        case .userCancelled:
            return nil
            
        case .pending:
            return nil
            
        @unknown default:
            return nil
        }
    }
    
    // MARK: - Restore Purchases
    
    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
            await updateCurrentSubscription()
            restoreMessage = currentTier == .free
                ? "No active subscriptions were found for this Apple Account."
                : "Restored your \(currentTier.displayName) subscription."
        } catch {
            restoreMessage = nil
            throw error
        }
    }
    
    // MARK: - Check Subscription Status
    
    func updateCurrentSubscription() async {
        var highestTier: SubscriptionTier = .free
        var resolvedSubscriptions: [Product] = []
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if let subscription = products.first(where: { $0.id == transaction.productID }) {
                    // Determine tier
                    if transaction.productID == SubscriptionTier.pro.rawValue {
                        highestTier = .pro
                    } else if transaction.productID == SubscriptionTier.proYearly.rawValue {
                        highestTier = .proYearly
                    } else if transaction.productID == SubscriptionTier.team.rawValue {
                        highestTier = .team
                    }
                    
                    resolvedSubscriptions.append(subscription)
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        purchasedSubscriptions = resolvedSubscriptions
        currentTier = highestTier
    }
    
    // MARK: - Listen for Transactions
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task {
            do {
                for try await result in Transaction.updates {
                    let transaction = try self.checkVerified(result)
                    await self.updateCurrentSubscription()
                    await transaction.finish()
                }
            } catch is CancellationError {
                // Task was cancelled, exit gracefully
            } catch {
                print("Transaction listener error: \(error)")
            }
        }
    }
    
    // MARK: - Verify Transaction
    
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - Feature Access
    
    func hasAccess(to feature: Feature) -> Bool {
        switch feature {
        case .basicSSH:
            return true // Available to all
        case .unlimitedHosts, .iCloudSync, .sftpBrowser, .snippets:
            return currentTier != .free
        case .teamManagement, .auditLogs, .ssoIntegration:
            return currentTier == .team
        }
    }
}

// MARK: - Feature Enum

enum Feature {
    case basicSSH
    case unlimitedHosts
    case iCloudSync
    case sftpBrowser
    case snippets
    case teamManagement
    case auditLogs
    case ssoIntegration
}

// MARK: - Store Error

enum StoreError: Error {
    case failedVerification
    case productNotFound
}

// MARK: - Legacy Compatibility (for iOS < 15)

#if !os(iOS) || compiler(<5.5)
// Fallback for older iOS versions
extension SubscriptionManager {
    func purchaseLegacy(_ productID: String, completion: @escaping (Bool) -> Void) {
        // Use SKPaymentQueue for iOS < 15
        completion(false)
    }
}
#endif
