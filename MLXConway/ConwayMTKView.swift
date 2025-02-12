//
//  ConwayMTKView.swift
//  MLXConway
//
//  Created by Andrew Gleave on 09/02/2025.
//


import MetalKit
import MLX

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

// custom MTKView that directly renders grayscale pixel data
class ConwayMTKView: MTKView, MTKViewDelegate {
    
    private var simulationWidth: Int = 0
    private var simulationHeight: Int = 0
    private var pixelTexture: MTLTexture?
    private var pixelBuffer: MTLBuffer?
    
    private let spawnRadius: Int = 5
    
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    
    // Track last point for smooth drawing
    private var lastPoint: CGPoint?
    
    private struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }
    
    private static let vertices: [Vertex] = [
        Vertex(position: SIMD2(-1, -1), texCoord: SIMD2(0, 1)),
        Vertex(position: SIMD2(1, -1),  texCoord: SIMD2(1, 1)),
        Vertex(position: SIMD2(-1, 1),  texCoord: SIMD2(0, 0)),
        Vertex(position: SIMD2(1, 1),   texCoord: SIMD2(1, 0))
    ]
    
    private var vertexBuffer: MTLBuffer?
    
    weak var simulationModel: ConwayModel? {
        didSet {
            initBuffers()
        }
    }
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let device = device ?? MTLCreateSystemDefaultDevice()!
        super.init(frame: frameRect, device: device)
        commonInit()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        device = MTLCreateSystemDefaultDevice()!
        commonInit()
    }
    private func initBuffers() {
        guard let model = simulationModel,
              let device = device else { return }
        
        simulationWidth = model.grid.shape[1]
        simulationHeight = model.grid.shape[0]
        
        pixelBuffer = device.makeBuffer(length: simulationWidth * simulationHeight, 
                                      options: .storageModeShared)
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: simulationWidth,
            height: simulationHeight,
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        pixelTexture = device.makeTexture(descriptor: descriptor)
    }
    
    private func commonInit() {
        colorPixelFormat = .bgra8Unorm
        delegate = self
        commandQueue = device?.makeCommandQueue()
        createVertexBuffer()
        createPipelineState()
        
        #if os(macOS)
            // Enable mouse tracking for macOS
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
        #else
            // Enable touch tracking for iOS
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(panGesture)
            addGestureRecognizer(tapGesture)
            isUserInteractionEnabled = true
        #endif
    }
    
    private func createVertexBuffer() {
        guard let device = device else { return }
        vertexBuffer = device.makeBuffer(bytes: Self.vertices,
                                       length: MemoryLayout<Vertex>.stride * Self.vertices.count,
                                       options: .storageModeShared)
    }
    
    private func createPipelineState() {
        guard let device = device,
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            return
        }
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = fragmentFunction
        desc.colorAttachments[0].pixelFormat = colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("error creating pipeline state: \(error)")
        }
    }
    
    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let model = simulationModel,
              let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let pixelTexture = pixelTexture,
              let pixelBuffer = pixelBuffer else { return }
        
        // Update simulation
        model.step()
        let one = MLXArray(1).asType(.int8)
        let inverted = one - model.grid
        let uint8Grid = (inverted.asType(.uint8)) * 255
        let data = uint8Grid.asData(access: .copy).data
        
        // Update pixel buffer
        data.withUnsafeBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memcpy(pixelBuffer.contents(), baseAddress, model.grid.shape[1] * model.grid.shape[0])
            }
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        // Copy buffer to texture using blit encoder
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: pixelBuffer,
                sourceOffset: 0,
                sourceBytesPerRow: simulationWidth,
                sourceBytesPerImage: simulationWidth * simulationHeight,
                sourceSize: MTLSizeMake(simulationWidth, simulationHeight, 1),
                to: pixelTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOriginMake(0, 0, 0)
            )
            blitEncoder.endEncoding()
        }
        
        // Render to screen
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(pixelTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: Self.vertices.count)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    // Convert view coordinates to grid coordinates
    private func gridCoordinates(from point: CGPoint) -> (x: Int, y: Int)? {
        guard let model = simulationModel else { return nil }
        
        #if os(macOS)
        let normalizedY = 1.0 - (point.y / bounds.height)  // Flip Y for macOS
        #else
        let normalizedY = point.y / bounds.height
        #endif
        let normalizedX = point.x / bounds.width
        
        let gridX = Int(normalizedX * CGFloat(model.gridWidth))
        let gridY = Int(normalizedY * CGFloat(model.gridHeight))
        
        guard gridX >= 0 && gridX < model.gridWidth &&
              gridY >= 0 && gridY < model.gridHeight else {
            return nil
        }
        
        return (gridX, gridY)
    }
    
    private func setGridCell(_ value: MLXArray, at x: Int, y: Int) {
        guard let model = simulationModel,
              x >= 0 && x < simulationWidth &&
                y >= 0 && y < simulationHeight else { return }
        
        model.grid[y, x] = value
    }
    
    // Set cells alive in a radius around a point
    private func setCellsAlive(at point: CGPoint) {
        guard let (gridX, gridY) = gridCoordinates(from: point) else { return }
        
        let alive = MLXArray(1).asType(.int8)
        for dy in -spawnRadius...spawnRadius {
            for dx in -spawnRadius...spawnRadius {
                setGridCell(alive, at: gridX + dx, y: gridY + dy)
            }
        }
    }
    
    // Draw a line of live cells between two points
    private func drawLine(from start: CGPoint, to end: CGPoint) {
        guard let (startX, startY) = gridCoordinates(from: start),
              let (endX, endY) = gridCoordinates(from: end) else { return }
        
        // Use Bresenham's line algorithm
        var x = startX
        var y = startY
        let dx = abs(endX - startX)
        let dy = abs(endY - startY)
        let sx = startX < endX ? 1 : -1
        let sy = startY < endY ? 1 : -1
        var err = dx - dy
        
        let alive = MLXArray(1).asType(.int8)
        let radius = 1
        
        while true {
            // Set cells alive in a radius around the current point
            for dy in -radius...radius {
                for dx in -radius...radius {
                    setGridCell(alive, at: x + dx, y: y + dy)
                }
            }
            
            if x == endX && y == endY { break }
            
            let e2 = 2 * err
            if e2 > -dy {
                err -= dy
                x += sx
            }
            if e2 < dx {
                err += dx
                y += sy
            }
        }
    }
    
    #if os(macOS)
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastPoint = point
        setCellsAlive(at: point)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let last = lastPoint {
            drawLine(from: last, to: point)
        }
        lastPoint = point
    }
    
    override func mouseUp(with event: NSEvent) {
        lastPoint = nil
    }
    #else
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            lastPoint = point
            setCellsAlive(at: point)
        case .changed:
            if let last = lastPoint {
                drawLine(from: last, to: point)
            }
            lastPoint = point
        case .ended, .cancelled:
            lastPoint = nil
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        setCellsAlive(at: point)
    }
    #endif
} 
