import SwiftUI
// import Inject
import Observation

struct ProductListView: View {
    // @ObserveInjection var inject
    @Environment(ProductListManager.self) var productListManager
    @Environment(MessageHandler.self) var messageHandler
    let list: ProductList
    @State private var showingAlert = false
    @State private var showingListPicker = false
    @State private var selectedProduct: Product?  // Unified state variable
    @State private var sortOption: ProductListView.SortOption = .newest  // Default sort option

    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case name = "Name"
        case barcode = "Barcode"
    }

    var body: some View {
        List {
            let sortedProducts = productListManager.sortedProducts(from: list, by: sortOption)

            if sortedProducts.isEmpty {
                Text("No products yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedProducts) { product in
                    NavigationLink(destination: ProductDetailsView(product: product)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.productName)
                                .font(.headline)
                            Text(product._id)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Delete action
                        Button(role: .destructive) {
                            selectedProduct = product
                            showingAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        // Add to custom list action
                        Button {
                            selectedProduct = product
                            showingListPicker = true
                        } label: {
                            Label("Add to List", systemImage: "plus")
                        }
                        .tint(.blue) // Customize the button color if needed
                    }
                }
            }
        }
        .navigationTitle(list.name.rawValue)
        .navigationBarItems(trailing: sortButton) // Add the sort button to the navigation bar
        .alert("Delete Product", isPresented: $showingAlert, presenting: selectedProduct) { product in
            Button("Delete", role: .destructive) {
                if let index = list.products.firstIndex(where: { $0.id == product.id }) {
                    list.products.remove(at: index)
                    productListManager.saveProductLists()
                    messageHandler.show("Removed '\(product.productName)' from list")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { product in
            Text("Are you sure you want to remove '\(product.productName)' from this list?")
        }
        .onChange(of: productListManager.selectedProduct) { product in
            guard let selectedProduct = product else {
                return
            }
            
            Task {
                do {
                    let fullProduct = try await NetworkService.shared.fetchProduct(barcode: selectedProduct._id)
                    // Update the product in the list with full details
                    if let listIndex = productListManager.productLists.firstIndex(where: { $0.id == list.id }),
                       let productIndex = productListManager.productLists[listIndex].products.firstIndex(where: { $0.id == selectedProduct.id }) {
                        productListManager.productLists[listIndex].products[productIndex] = fullProduct
                        productListManager.saveProductLists()
                    }
                } catch {
                    print("Error fetching product: \(error)")
                }
            }
        }
        .sheet(isPresented: $showingListPicker) {
            ListPickerView(isPresented: $showingListPicker, product: selectedProduct!) // Pass the selected product
        }
        .toast()
        // .enableInjection()
    }

    private var sortButton: some View {
        Menu {
            Button(action: {
                sortOption = sortOption == .newest ? .oldest : .newest // Combined toggle
            }) {
                Label("Order: \(sortOption == .newest ? "Newest" : "Oldest")", systemImage: sortOption == .newest ? "arrow.up" : "arrow.down") // Updated label and image
            }
            ForEach(SortOption.allCases.filter { $0 != .newest && $0 != .oldest }, id: \.self) { option in
                Button(action: {
                    sortOption = option
                }) {
                    Text(option.rawValue)
                }
            }
        } label: {
            Label("Order", systemImage: "arrow.up.arrow.down") 
                .font(.headline)
        }
    }
}

#Preview {
    NavigationStack {
        ProductListView(list: ProductList(name: .custom("Test List")))
            .environment(MessageHandler.shared)
            .environment(ProductListManager.shared)
            .environment(NetworkService.shared)  // Added because of network calls in onChange
    }
}
