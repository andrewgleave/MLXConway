//
//  MLXConwayApp.swift
//  MLXConway
//
//  Created by Andrew Gleave on 09/02/2025.
//

import SwiftUI

@main
struct MLXConwayApp: App {
    var body: some Scene {
        
        #if os(macOS)
            let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 800, height: 600)
        #else
            let screenSize = UIScreen.main.bounds.size
        #endif
        
        WindowGroup {
            ContentView(model: ConwayModel(gridSize: screenSize, scale: 1.0))
        }
    }
}
