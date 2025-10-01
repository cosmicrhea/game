//import Pango
//import GL
//
//class PangoRenderer {
//    struct RenderedText {
//        let textureID: GLuint
//        let width: Int
//        let height: Int
//    }
//
//    let font: String
//    let fontSize: Int
//    let wrapWidth: Int
//    let padding: Int
//
//    init(font: String = "Sans", fontSize: Int = 16, wrapWidth: Int = 512, padding: Int = 8) {
//        self.font = font
//        self.fontSize = fontSize
//        self.wrapWidth = wrapWidth
//        self.padding = padding
//    }
//
//    func render(text: String) -> RenderedText {
//        // 1. Dummy surface to measure size
//        let dummySurface = ImageSurface(format: .argb32, width: 1, height: 1)
//        let dummyContext = Cairo.Context(surface: dummySurface)
//
//        let layout = Pango.Layout(context: dummyContext)
//        layout.text = text
//        layout.width = Int32(wrapWidth * PANGO_SCALE)
//        layout.wrap = .wordChar
//        layout.fontDescription = FontDescription("\(font) \(fontSize)")
//
//        let (layoutW, layoutH) = layout.size
//        let textWidth = layoutW / PANGO_SCALE
//        let textHeight = layoutH / PANGO_SCALE
//
//        let finalWidth = textWidth + 2 * padding
//        let finalHeight = textHeight + 2 * padding
//
//        // 2. Real surface
//        let surface = ImageSurface(format: .argb32, width: finalWidth, height: finalHeight)
//        let cr = Cairo.Context(surface: surface)
//
//        // Optional: clear background (transparent)
//        cr.setSourceRGBA(0, 0, 0, 0)
//        cr.paint()
//
//        // 3. Layout on real surface
//        let realLayout = Pango.Layout(context: cr)
//        realLayout.text = text
//        realLayout.width = layout.width
//        realLayout.wrap = layout.wrap
//        realLayout.fontDescription = layout.fontDescription
//
//        cr.move(to: (Double(padding), Double(padding)))
//        realLayout.show(on: cr)
//
//        // 4. Upload to OpenGL
//        let pixelData = surface.data
//        var texID: GLuint = 0
//        glGenTextures(1, &texID)
//        glBindTexture(GL_TEXTURE_2D, texID)
//
//        glTexImage2D(
//            GL_TEXTURE_2D,
//            0,
//            GL_RGBA,
//            GLsizei(finalWidth),
//            GLsizei(finalHeight),
//            0,
//            GLenum(GL_BGRA),
//            GLenum(GL_UNSIGNED_BYTE),
//            pixelData
//        )
//
//        // Texture params
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
//        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
//
//        return RenderedText(
//            textureID: texID,
//            width: finalWidth,
//            height: finalHeight
//        )
//    }
//}
