//
//  TickerTapeApp.swift
//  TickerTape
//
//  Created by Thomas Paolino on 9/5/24.
//

import SwiftUI
import Foundation
import Combine
import Network

@main
struct TickerTapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var statusItem: NSStatusItem?
    @Published var stocks: [Stock] = []
    @Published var refreshInterval: TimeInterval = 300 // This will be the user-facing setting
    let actualRefreshInterval: TimeInterval = 30 // Fixed at 30 seconds
    @Published var scrollSpeed: Double = 50 // pixels per second
    @Published var isLoading: Bool = true
    @Published var displayStyle: DisplayStyle = .stationary
    var timer: Timer?
    @StateObject private var networkMonitor = NetworkMonitor()

    enum DisplayStyle: String, CaseIterable {
        case stationary = "Stationary"
        case scrolling = "Scrolling"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Application did finish launching")
        loadSettings()
        loadSavedStocks()
        setupStatusItem()
        fetchAllStockData()
        startTimer()
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 200) // Adjust this value as needed
        
        if let button = statusItem?.button {
            button.frame = NSRect(x: 0, y: 0, width: 200, height: NSStatusBar.system.thickness)
            updateTickerView()
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Add Ticker", action: #selector(addTicker), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Remove Ticker", action: #selector(removeTicker), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    func updateTickerView() {
        print("Updating ticker view with \(stocks.count) stocks")
        if let button = statusItem?.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            let tickerView = TickerView(stocks: stocks, scrollSpeed: scrollSpeed)
            let hostingView = NSHostingView(rootView: tickerView)
            hostingView.frame = button.bounds
            button.addSubview(hostingView)
        }
    }

    func startTimer() {
        timer?.invalidate() // Invalidate existing timer if any
        timer = Timer.scheduledTimer(withTimeInterval: actualRefreshInterval, repeats: true) { [weak self] timer in
            self?.fetchAllStockData()
        }
        print("Timer started/restarted with interval: \(String(format: "%.2f", actualRefreshInterval)) seconds")
    }

    func fetchAllStockData() {
        print("Fetching all stock data")
        isLoading = true
        updateTickerView() // This will show "Fetching 0 Quotes" if stocks is empty
        
        let group = DispatchGroup()
        
        for stock in stocks {
            group.enter()
            fetchStockData(for: stock.ticker) { updatedStock in
                if let updatedStock = updatedStock {
                    DispatchQueue.main.async {
                        if let index = self.stocks.firstIndex(where: { $0.ticker == updatedStock.ticker }) {
                            self.stocks[index] = updatedStock
                            print("Updated stock in array: \(updatedStock.ticker) - Price: \(updatedStock.price)")
                        }
                    }
                } else {
                    print("Failed to fetch data for \(stock.ticker)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            self.isLoading = false
            self.updateTickerView() // This will update with fetched stocks
            print("Finished fetching all stock data. Current stocks: \(self.stocks)")
        }
    }

    @objc func addTicker() {
        print("Opening Add Ticker view")
        let contentView = AddTickerView(onAdd: { [weak self] newStock in
            guard let self = self else { return }
            print("onAdd callback received in AppDelegate")
            self.addStock(newStock)
        }, fetchStockData: fetchStockData)
        
        let controller = NSHostingController(rootView: contentView)
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 300)
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: statusItem?.button?.bounds ?? .zero, of: statusItem?.button ?? NSView(), preferredEdge: .minY)
    }

    @objc func removeTicker() {
        let contentView = RemoveTickerView(appDelegate: self)
        let controller = NSHostingController(rootView: contentView)
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 300)
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: statusItem?.button?.bounds ?? .zero, of: statusItem?.button ?? NSView(), preferredEdge: .minY)
    }

    func removeStock(_ stock: Stock) {
        if let index = stocks.firstIndex(where: { $0.id == stock.id }) {
            stocks.remove(at: index)
            saveStocks()
            updateTickerView()
            print("Removed stock: \(stock.ticker)")
        }
    }

    @objc func openSettings() {
        let contentView = SettingsView(
            refreshInterval: Binding(
                get: { self.refreshInterval },
                set: { self.refreshInterval = $0 }
            ),
            scrollSpeed: Binding(
                get: { self.scrollSpeed },
                set: { self.scrollSpeed = $0 }
            ),
            displayStyle: Binding(
                get: { self.displayStyle },
                set: { self.displayStyle = $0 }
            )
        ) {
            self.saveSettings()
            self.updateTickerView()
        }
        let controller = NSHostingController(rootView: contentView)
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 250)
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: statusItem?.button?.bounds ?? .zero, of: statusItem?.button ?? NSView(), preferredEdge: .minY)
    }

    func saveStocks() {
        let encodedData = try? JSONEncoder().encode(stocks)
        UserDefaults.standard.set(encodedData, forKey: "savedStocks")
        print("Saved \(stocks.count) stocks to UserDefaults")
    }

    func loadSavedStocks() {
        if let savedStocks = UserDefaults.standard.data(forKey: "savedStocks"),
           let decodedStocks = try? JSONDecoder().decode([Stock].self, from: savedStocks) {
            stocks = decodedStocks
            print("Loaded saved stocks: \(stocks)")
        } else {
            print("No saved stocks found")
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        UserDefaults.standard.set(scrollSpeed, forKey: "scrollSpeed")
        UserDefaults.standard.set(displayStyle.rawValue, forKey: "displayStyle")
        print("Settings saved: refreshInterval = \(formatRefreshInterval(refreshInterval)) (displayed), actualRefreshInterval = 30 seconds (fixed), scrollSpeed = \(String(format: "%.0f", scrollSpeed)) pixels/second, displayStyle = \(displayStyle.rawValue)")
    }

    func loadSettings() {
        refreshInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        scrollSpeed = UserDefaults.standard.double(forKey: "scrollSpeed")
        if refreshInterval == 0 { refreshInterval = 300 } // Default to 5 minutes if not set
        if scrollSpeed == 0 { scrollSpeed = 50 } // Default to 50 pixels/second if not set
        refreshInterval = max(20, min(refreshInterval, 300)) // Ensure refreshInterval is within the valid range
        refreshInterval = round(refreshInterval / 30) * 30 // Round to nearest 30 seconds
        scrollSpeed = max(10, min(scrollSpeed, 100)) // Ensure scrollSpeed is within the valid range
        scrollSpeed = round(scrollSpeed / 5) * 5 // Round to nearest 5
        if let savedStyle = UserDefaults.standard.string(forKey: "displayStyle"),
           let style = DisplayStyle(rawValue: savedStyle) {
            displayStyle = style
        }
        print("Settings loaded: refreshInterval = \(formatRefreshInterval(refreshInterval)) (displayed), actualRefreshInterval = 30 seconds (fixed), scrollSpeed = \(String(format: "%.0f", scrollSpeed)) pixels/second, displayStyle = \(displayStyle.rawValue)")
    }

    private func formatRefreshInterval(_ interval: TimeInterval) -> String {
        if interval >= 60 {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return seconds == 0 ? "\(minutes) minute(s)" : "\(minutes) minute(s) \(seconds) seconds"
        } else {
            return "\(Int(interval)) seconds"
        }
    }

    func addStock(_ stock: Stock) {
        print("AppDelegate: Adding stock: \(stock)")
        stocks.append(stock)
        saveStocks()
        updateTickerView()
        print("AppDelegate: Stock added, current stocks: \(stocks)")
    }
}

struct Stock: Identifiable, Codable, Equatable {
    let id: UUID
    let ticker: String
    let name: String
    let price: Double
    let change: Double
    var lastUpdated: Date?
    
    static func == (lhs: Stock, rhs: Stock) -> Bool {
        return lhs.id == rhs.id &&
               lhs.ticker == rhs.ticker &&
               lhs.name == rhs.name &&
               lhs.price == rhs.price &&
               lhs.change == rhs.change &&
               lhs.lastUpdated == rhs.lastUpdated
    }
}

struct AddTickerView: View {
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    var onAdd: (Stock) -> Void
    var fetchStockData: (String, @escaping (Stock?) -> Void) -> Void

    var body: some View {
        VStack {
            Text("Add Ticker")
                .font(.headline)
            TextField("Search for ticker", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    searchStocks()
                }
            Button("Search") {
                searchStocks()
            }
            if isSearching {
                ProgressView()
            } else {
                List(searchResults) { result in
                    VStack(alignment: .leading) {
                        Text("\(result.symbol) - \(result.instrumentName)")
                            .font(.headline)
                        Text(result.country)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    Button("Add") {
                        addStock(symbol: result.symbol)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300, height: 300)
    }

    func searchStocks() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let headers = [
            "x-rapidapi-key": "88ad377c4amsh95e8ecf71af74bcp1713bbjsn1737002ecce1",
            "x-rapidapi-host": "twelve-data1.p.rapidapi.com"
        ]

        let urlString = "https://twelve-data1.p.rapidapi.com/symbol_search?symbol=\(searchText)&outputsize=30"
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else {
            print("Invalid URL")
            isSearching = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSearching = false
                
                if let error = error {
                    print("Error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let data = json["data"] as? [[String: Any]] {
                        self.searchResults = data.compactMap { result in
                            guard let symbol = result["symbol"] as? String,
                                  let instrumentName = result["instrument_name"] as? String,
                                  let country = result["country"] as? String else { return nil }
                            return SearchResult(symbol: symbol, instrumentName: instrumentName, country: country)
                        }
                        print("Parsed search results: \(self.searchResults)")
                    } else {
                        print("Invalid JSON structure")
                    }
                } catch {
                    print("Error parsing JSON: \(error.localizedDescription)")
                }
            }
        }

        task.resume()
    }

    func addStock(symbol: String) {
        print("Attempting to add stock: \(symbol)")
        fetchStockData(symbol) { stock in
            if let stock = stock {
                DispatchQueue.main.async {
                    self.onAdd(stock)
                    print("Added: \(stock)")
                }
            } else {
                print("Failed to fetch data for \(symbol)")
                // You might want to show an alert to the user here
            }
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let symbol: String
    let instrumentName: String
    let country: String
}

struct RemoveTickerView: View {
    @ObservedObject var appDelegate: AppDelegate
    
    var body: some View {
        VStack {
            Text("Remove Ticker")
                .font(.headline)
            List(appDelegate.stocks) { stock in
                HStack {
                    Text(stock.ticker)
                    Spacer()
                    Button("Remove") {
                        appDelegate.removeStock(stock)
                    }
                }
            }
        }
        .padding()
        .frame(width: 300, height: 300)
    }
}

struct SettingsView: View {
    @Binding var refreshInterval: Double
    @Binding var scrollSpeed: Double
    @Binding var displayStyle: AppDelegate.DisplayStyle
    var onSave: () -> Void

    var body: some View {
        VStack {
            Text("Settings")
                .font(.headline)
            Form {
                Section(header: Text("Refresh Interval")) {
                    Slider(value: $refreshInterval, in: 20...300, step: 30)
                    Text(formatRefreshInterval(refreshInterval))
                    Text("Note: Actual refresh occurs every 30 seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Scroll Speed (pixels per second)")) {
                    Slider(value: $scrollSpeed, in: 10...100, step: 5)
                    Text(String(format: "%.0f pixels/second", scrollSpeed))
                }
                Section(header: Text("Display Style")) {
                    Picker("Style", selection: $displayStyle) {
                        ForEach(AppDelegate.DisplayStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            Button("Save") {
                onSave()
                // Add this line to update the ticker view
                (NSApplication.shared.delegate as? AppDelegate)?.updateTickerView()
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
    
    private func formatRefreshInterval(_ interval: Double) -> String {
        if interval >= 60 {
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            return seconds == 0 ? "\(minutes) minute(s)" : "\(minutes) minute(s) \(seconds) seconds"
        } else {
            return "\(Int(interval)) seconds"
        }
    }
}

struct TickerView: View {
    let stocks: [Stock]
    let scrollSpeed: Double
    
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            if stocks.isEmpty {
                Text("Click to Add Ticker")
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(stocks) { stock in
                            stockView(for: stock)
                        }
                    }
                    .offset(x: offset)
                    .frame(height: geometry.size.height)
                    .background(GeometryReader { contentGeometry in
                        Color.clear.onAppear {
                            contentWidth = contentGeometry.size.width
                        }
                    })
                }
                .onAppear {
                    animateScroll(viewWidth: geometry.size.width)
                }
            }
        }
        .frame(height: 22)  // Adjust this height as needed
    }
    
    private func stockView(for stock: Stock) -> some View {
        HStack(spacing: 4) {
            Text(stock.ticker)
                .fontWeight(.bold)
            Text("$\(String(format: "%.2f", stock.price))")
            Text("(\(stock.change >= 0 ? "+" : "")\(String(format: "%.2f", stock.change))%)")
                .foregroundColor(stock.change >= 0 ? .green : .red)
        }
    }
    
    private func animateScroll(viewWidth: CGFloat) {
        withAnimation(.linear(duration: Double(contentWidth / scrollSpeed)).repeatForever(autoreverses: false)) {
            offset = -contentWidth
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

func fetchStockData(for symbol: String, completion: @escaping (Stock?) -> Void) {
    let headers = [
        "x-rapidapi-key": "88ad377c4amsh95e8ecf71af74bcp1713bbjsn1737002ecce1",
        "x-rapidapi-host": "twelve-data1.p.rapidapi.com"
    ]

    let urlString = "https://twelve-data1.p.rapidapi.com/quote?symbol=\(symbol)&interval=1day&outputsize=30&format=json"
    guard let url = URL(string: urlString) else {
        print("Invalid URL")
        completion(nil)
        return
    }

    var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
    request.httpMethod = "GET"
    request.allHTTPHeaderFields = headers

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error: \(error.localizedDescription)")
            completion(nil)
            return
        }

        guard let data = data else {
            print("No data received")
            completion(nil)
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                print("Received JSON for \(symbol): \(json)")

                guard let name = json["name"] as? String,
                      let price = json["close"] as? String,
                      let change = json["percent_change"] as? String,
                      let priceDouble = Double(price),
                      let changeDouble = Double(change) else {
                    print("Failed to parse required fields for \(symbol)")
                    completion(nil)
                    return
                }

                let stock = Stock(id: UUID(), ticker: symbol, name: name, price: priceDouble, change: changeDouble / 100, lastUpdated: Date())
                completion(stock)
            }
        } catch {
            print("Error parsing JSON: \(error.localizedDescription)")
            completion(nil)
        }
    }

    task.resume()
}

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = false

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
