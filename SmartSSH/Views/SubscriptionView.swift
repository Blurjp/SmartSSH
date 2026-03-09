//
//  SubscriptionView.swift
//  SSH Terminal
//
//  Subscription upgrade view
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var isPurchasing: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Pricing cards
                    pricingCards
                    
                    // Features comparison
                    featuresComparison
                    
                    // Restore purchases
                    restoreButton
                }
                .padding()
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            
            Text("Unlock All Features")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Get unlimited hosts, AI features, and more")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }
    
    // MARK: - Pricing Cards
    
    private var pricingCards: some View {
        VStack(spacing: 12) {
            // Free tier
            PricingCard(
                tier: .free,
                isSelected: subscriptionManager.currentTier == .free,
                isCurrent: true
            ) {
                // Already on free tier
            }
            
            // Pro Monthly
            if let product = subscriptionManager.products.first(where: { $0.id == SubscriptionTier.pro.rawValue }) {
                PricingCard(
                    tier: .pro,
                    isSelected: selectedTier == .pro,
                    isPopular: true
                ) {
                    purchaseProduct(product)
                }
            }
            
            // Pro Yearly
            if let product = subscriptionManager.products.first(where: { $0.id == SubscriptionTier.proYearly.rawValue }) {
                PricingCard(
                    tier: .proYearly,
                    isSelected: selectedTier == .proYearly,
                    badge: "Save 17%"
                ) {
                    purchaseProduct(product)
                }
            }
            
            // Team
            if let product = subscriptionManager.products.first(where: { $0.id == SubscriptionTier.team.rawValue }) {
                PricingCard(
                    tier: .team,
                    isSelected: selectedTier == .team
                ) {
                    purchaseProduct(product)
                }
            }
        }
    }
    
    // MARK: - Features Comparison
    
    private var featuresComparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features")
                .font(.headline)
            
            let allFeatures: [(String, Feature)] = [
                ("Basic SSH", .basicSSH),
                ("Hosts (Unlimited)", .unlimitedHosts),
                ("iCloud Sync", .iCloudSync),
                ("AI Features", .aiFeatures),
                ("SFTP Browser", .sftpBrowser),
                ("Code Snippets", .snippets),
                ("Team Management", .teamManagement),
                ("Audit Logs", .auditLogs),
            ]
            
            ForEach(allFeatures, id: \.0) { feature in
                HStack {
                    Text(feature.0)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    if subscriptionManager.hasAccess(to: feature.1) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Restore Button
    
    private var restoreButton: some View {
        Button {
            Task {
                await subscriptionManager.restorePurchases()
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }
    
    // MARK: - Purchase
    
    private func purchaseProduct(_ product: Product) {
        isPurchasing = true
        
        Task {
            do {
                _ = try await subscriptionManager.purchase(product)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            
            isPurchasing = false
        }
    }
}

// MARK: - Pricing Card

struct PricingCard: View {
    let tier: SubscriptionTier
    var isSelected: Bool = false
    var isCurrent: Bool = false
    var isPopular: Bool = false
    var badge: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tier.displayName)
                                .font(.headline)
                            
                            if let badge = badge {
                                Text(badge)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundStyle(.green)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Text(tier.price)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if isCurrent {
                        Text("Current")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(16)
                    } else if isPopular {
                        Text("Popular")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .cornerRadius(16)
                    }
                }
                
                // Features
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tier.features.prefix(4), id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                            
                            Text(feature)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SubscriptionView()
}
