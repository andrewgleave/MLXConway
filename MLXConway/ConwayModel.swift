//
//  ConwayModel.swift
//  MLXConway
//
//  Created by Andrew Gleave on 09/02/2025.
//

import CoreGraphics
import MLX
import MLXFast
import MLXRandom

let conwayKernelSource = """
    uint i = thread_position_in_grid.x;
    uint j = thread_position_in_grid.y;
    uint n = threads_per_grid.x;
    uint m = threads_per_grid.y;
    uint down = (i == 0) ? n : (i - 1);
    uint up = (i + 1) == n ? 0 : (i + 1);
    uint left = (j == 0) ? m : (j - 1);
    uint right = (j + 1) == m ? 0 : (j + 1);
    size_t idx = i * m + j;
    int count = grid[up * m + right] + grid[up * m + j]
        + grid[i * m + right] + grid[up * m + left] + grid[down * m + left]
        + grid[down * m + j] + grid[i * m + left] + grid[down * m + right];
    if ((grid[idx] && count == 2) || count == 3) {
        out[idx] = true;
    } else {
        out[idx] = false;
    }
"""

class ConwayModel {
    var grid: MLXArray
    let kernel: MLXFastKernel
    let gridWidth: Int
    let gridHeight: Int
    
    init(gridSize: CGSize = .zero, scale: CGFloat = 1.0) {
        self.gridWidth = Int(gridSize.width * scale)
        self.gridHeight = Int(gridSize.height * scale)
        
        let randomGrid = MLXRandom.bernoulli(0.3, [gridHeight, gridWidth])
        self.grid = randomGrid.asType(.int8)
        
        self.kernel = metalKernel(
            name: "conway",
            inputNames: ["grid"],
            outputNames: ["out"],
            source: conwayKernelSource,
            grid: (gridHeight, gridWidth, 1),
            threadGroup: (2, 512, 1),
            outputShapes: [grid.shape],
            outputDTypes: [grid.dtype]
        )
    }

    func step() {
        let outputs = kernel([grid])
        grid = outputs[0]
    }
}
