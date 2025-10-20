import Foundation

/// Demo for testing EXR image loading functionality
public struct EXRDemo {
  public static func run() {
    print("EXR Demo - Testing EXR image loading")

    // Test loading the existing EXR files
    let exrFiles = [
      "textures/marble_01_nor_gl_4k.exr",
      "textures/concrete_tiles_02_rough_4k.exr",
      "textures/concrete_tiles_02_nor_gl_4k.exr",
    ]

    for exrFile in exrFiles {
      print("Loading EXR file: \(exrFile)")

      // Test direct EXR loading
      let image = Image.loadEXR(exrFile)
      print("  - Loaded image size: \(image.naturalSize)")
      print("  - Texture ID: \(image.textureID)")
      print("  - Pixel scale: \(image.pixelScale)")

      // Test loading through main Image initializer
      let image2 = Image(exrFile)
      print("  - Loaded via main initializer: \(image2.naturalSize)")

      // Test layer functionality
      let layers = Image.getEXRLayers(exrFile)
      print("  - Available layers: \(layers)")

      if !layers.isEmpty {
        let layerImage = Image.loadEXR(exrFile, layer: layers[0])
        print("  - Loaded first layer: \(layerImage.naturalSize)")
      }
    }

    print("EXR Demo completed successfully!")
  }
}
