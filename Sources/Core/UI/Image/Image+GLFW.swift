//import struct GLFW.Color
//import struct GLFW.Image
//
//extension Image {
//  public init(glfwImage: GLFW.Image, pixelScale: Float = 1.0) {
//    var bytes: [UInt8] = []
//    bytes.reserveCapacity(Int(glfwImage.width * glfwImage.height * 4))
//    glfwImage.pixels.forEach { p in
//      bytes.append(p.redBits)
//      bytes.append(p.greenBits)
//      bytes.append(p.blueBits)
//      bytes.append(p.alphaBits)
//    }
//    self = Image.uploadToGL(
//      pixels: bytes,
//      width: Int(glfwImage.width),
//      height: Int(glfwImage.height),
//      pixelScale: pixelScale
//    )
//  }
//
////  public var glfwImage: GLFW.Image {
////    guard let bytes = pixelBytes, pixelWidth > 0, pixelHeight > 0 else {
////      return GLFW.Image(width: 0, height: 0, pixels: [])
////    }
////
////    print(pixelWidth, pixelHeight, bytes)
////
////    var colors: [GLFW.Color] = []
////    colors.reserveCapacity(pixelWidth * pixelHeight)
////    var i = 0
////    while i + 3 < bytes.count {
////      colors.append(GLFW.Color(rBits: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3]))
////      i += 4
////    }
////
////    return GLFW.Image(width: pixelWidth, height: pixelHeight, pixels: colors)
////  }
//}
