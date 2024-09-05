//
//  ContentView.swift
//  TickerTape
//
//  Created by Thomas Paolino on 9/5/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var newTickerSymbol: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Stock Ticker Menu Bar App")
                .font(.title)
                .padding()
            
            HStack {
                TextField("Enter ticker symbol", text: $newTickerSymbol)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Add Stock") {
                    addStock()
                }
                .disabled(newTickerSymbol.isEmpty)
            }
            .padding(.horizontal)
            
            List {
                ForEach(appDelegate.stocks) { stock in
                    HStack {
                        Text(stock.ticker)
                            .fontWeight(.bold)
                        Spacer()
                        Text(stock.name)
                        Spacer()
                        Text("$\(String(format: "%.2f", stock.price))")
                        Text("(\(stock.change >= 0 ? "+" : "")\(String(format: "%.2f", stock.change))%)")
                            .foregroundColor(stock.change >= 0 ? .green : .red)
                    }
                }
                .onDelete(perform: removeStocks)
            }
            
            HStack {
                Button("Refresh Stocks") {
                    appDelegate.fetchAllStockData()
                }
                
                Spacer()
                
                Button("Settings") {
                    appDelegate.openSettings()
                }
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
    
    private func addStock() {
        fetchStockData(for: newTickerSymbol) { stock in
            if let stock = stock {
                DispatchQueue.main.async {
                    self.appDelegate.addStock(stock)
                    self.newTickerSymbol = ""
                }
            }
        }
    }
    
    private func removeStocks(at offsets: IndexSet) {
        for index in offsets {
            if let stock = appDelegate.stocks[safe: index] {
                appDelegate.removeStock(stock)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppDelegate())
    }
}
