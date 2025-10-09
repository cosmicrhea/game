import class Foundation.Bundle
import struct Foundation.Data
import class Foundation.NSObject
import class Foundation.XMLParser
import protocol Foundation.XMLParserDelegate

extension ImageAtlas {
  /// Load a TexturePacker-style XML atlas and return an ``ImageAtlas``.
  /// - Parameter tpxmlPath: Path to the TexturePacker XML file relative to the bundle resources.
  /// - Returns: An initialized `ImageAtlas`, or `nil` if loading fails.
  public convenience init?(tpxmlPath: String) {
    guard let baseURL = Bundle.module.resourceURL else {
      logger.error("ImageAtlas: Bundle.module.resourceURL is nil")
      return nil
    }
    let xmlURL = baseURL.appendingPathComponent(tpxmlPath)
    logger.info("ImageAtlas: looking for XML at \(xmlURL.path)")
    guard let data = try? Data(contentsOf: xmlURL) else {
      logger.error("ImageAtlas: failed to load XML data from \(xmlURL.path)")
      return nil
    }

    let coordinator = TexturePackerXMLCoordinator()
    let xml = XMLParser(data: data)
    xml.delegate = coordinator
    let parseResult = xml.parse()
    logger.info("ImageAtlas: XML parsing result: \(parseResult)")
    logger.info("ImageAtlas: parsed \(coordinator.nameToRect.count) entries")

    // Resolve PNG path relative to XML
    let imageFileName = coordinator.imagePath ?? ""
    let imageURL = xmlURL.deletingLastPathComponent().appendingPathComponent(imageFileName)
    let relativeFromBundle = imageURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
    logger.info("ImageAtlas: loading image from \(relativeFromBundle)")
    let texture = Image(resourcePath: relativeFromBundle)

    // Get dimensions from the loaded image instead of XML
    let atlasW = Int(texture.naturalSize.width)
    let atlasH = Int(texture.naturalSize.height)
    logger.info("ImageAtlas: atlas dimensions from image: \(atlasW)x\(atlasH)")
    guard atlasW > 0 && atlasH > 0 else {
      logger.error("ImageAtlas: invalid atlas dimensions: \(atlasW)x\(atlasH)")
      return nil
    }

    var entries: [ImageAtlasEntry] = []
    for (name, r) in coordinator.nameToRect {
      let u0 = Float(r.x) / Float(atlasW)
      let v0 = Float(r.y) / Float(atlasH)
      let u1 = Float(r.x + r.w) / Float(atlasW)
      let v1 = Float(r.y + r.h) / Float(atlasH)
      let uv = Rect(x: u0, y: v0, width: u1 - u0, height: v1 - v0)
      entries.append(ImageAtlasEntry(name: name, uv: uv, size: Size(Float(r.w), Float(r.h))))
    }
    logger.info("ImageAtlas: creating ImageAtlas with \(entries.count) entries")
    self.init(texture: texture, entries: entries)
  }

  /// Internal coordinator for parsing TexturePacker XML files.
  final class TexturePackerXMLCoordinator: NSObject, XMLParserDelegate {
    /// Path to the atlas image file.
    var imagePath: String? = nil
    /// Width of the atlas texture in pixels.
    var atlasWidth: Int = 0
    /// Height of the atlas texture in pixels.
    var atlasHeight: Int = 0
    /// Mapping from subimage names to their pixel coordinates and dimensions.
    var nameToRect: [String: (x: Int, y: Int, w: Int, h: Int)] = [:]

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
      attributes attributeDict: [String: String] = [:]
    ) {
      if elementName == "TextureAtlas" {
        imagePath = attributeDict["imagePath"]
        atlasWidth = Int(attributeDict["width"] ?? "0") ?? 0
        atlasHeight = Int(attributeDict["height"] ?? "0") ?? 0
      } else if elementName == "SubTexture" {
        if let name = attributeDict["name"],
          let x = Int(attributeDict["x"] ?? "0"),
          let y = Int(attributeDict["y"] ?? "0"),
          let w = Int(attributeDict["width"] ?? "0"),
          let h = Int(attributeDict["height"] ?? "0")
        {
          nameToRect[name] = (x, y, w, h)
        }
      }
    }
  }
}
