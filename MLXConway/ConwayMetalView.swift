//
//  ConwayMetalView.swift
//  MLXConway
//
//  Created by Andrew Gleave on 09/02/2025.
//

import SwiftUI
import MetalKit
import MLX

#if os(macOS)
struct ConwayMetalView: NSViewRepresentable {
    var model: ConwayModel

    func makeNSView(context: Context) -> ConwayMTKView {
        return ConwayMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }
    
    func updateNSView(_ nsView: ConwayMTKView, context: Context) {
        nsView.simulationModel = model
    }
}
#else
struct ConwayMetalView: UIViewRepresentable {
    var model: ConwayModel

    func makeUIView(context: Context) -> ConwayMTKView {
        return ConwayMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }
    
    func updateUIView(_ uiView: ConwayMTKView, context: Context) {
        uiView.simulationModel = model
    }
}
#endif 
