import StoreKit

@available(iOS 15.0, *)
class StoreKitManager: NSObject, ObservableObject {
    static let shared = StoreKitManager()
    
    private let productId = "com.ioanabunta.kidseducgames.unlockall"
    
    @Published var isUnlocked: Bool = false
    @Published var product: Product?
    
    private override init() {
        super.init()
        // Check if already purchased
        isUnlocked = UserDefaults.standard.bool(forKey: "allGamesUnlocked")
        
        // Start listening for transactions
        Task {
            await listenForTransactions()
            await loadProduct()
            await checkCurrentEntitlements()
        }
    }
    
    // Load the product from App Store
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [productId])
            if let product = products.first {
                self.product = product
                print("[StoreKit] Product loaded: \(product.displayName) - \(product.displayPrice)")
            }
        } catch {
            print("[StoreKit] Failed to load product: \(error)")
        }
    }
    
    // Purchase the product
    func purchase() async -> Bool {
        guard let product = product else {
            print("[StoreKit] Product not available")
            return false
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await MainActor.run {
                    self.isUnlocked = true
                    UserDefaults.standard.set(true, forKey: "allGamesUnlocked")
                }
                print("[StoreKit] Purchase successful!")
                return true
                
            case .userCancelled:
                print("[StoreKit] User cancelled purchase")
                return false
                
            case .pending:
                print("[StoreKit] Purchase pending")
                return false
                
            @unknown default:
                return false
            }
        } catch {
            print("[StoreKit] Purchase failed: \(error)")
            return false
        }
    }
    
    // Restore purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
        } catch {
            print("[StoreKit] Restore failed: \(error)")
        }
    }
    
    // Check current entitlements
    func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == productId {
                    await MainActor.run {
                        self.isUnlocked = true
                        UserDefaults.standard.set(true, forKey: "allGamesUnlocked")
                    }
                    print("[StoreKit] User has active entitlement for: \(transaction.productID)")
                }
            }
        }
    }
    
    // Listen for transactions (handles purchases made on other devices)
    func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                if transaction.productID == productId {
                    await MainActor.run {
                        self.isUnlocked = true
                        UserDefaults.standard.set(true, forKey: "allGamesUnlocked")
                    }
                }
                await transaction.finish()
            }
        }
    }
    
    // Verify transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    enum StoreError: Error {
        case failedVerification
    }
}
