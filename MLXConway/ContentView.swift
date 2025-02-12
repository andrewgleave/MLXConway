//
//  ContentView.swift
//  MLXConway
//
//  Created by Andrew Gleave on 09/02/2025.
//

import SwiftUI

struct ContentView: View {
    let model: ConwayModel
    
    var body: some View {
        ConwayMetalView(model: model)
            .ignoresSafeArea()
    }
}
