#if canImport(AppKit)

  import class AppKit.NSWindow
  import CoreImage.CIFilterBuiltins

  extension NSWindow {
    func hideStandardWindowButtons() {
      let buttonTypes: [ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
      for type in buttonTypes {
        guard let button = standardWindowButton(type) else { continue }
        button.isHidden = true
      }
    }

    func darkenStandardWindowButtons() {
      let filter = CIFilter.colorControls()
      filter.brightness = -0.4
      let buttonTypes: [ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
      for type in buttonTypes {
        guard let button = standardWindowButton(type) else { continue }
        button.wantsLayer = true
        button.layer?.filters = [filter]
        button.layer?.opacity = 0.6
      }
    }
  }

  import class AppKit.NSFont
  import ObjectiveC.runtime

  @objc class NSWindowSwizzling: NSObject {
    @objc func updateTextPropertiesWithFont(_ font: NSFont) {
      // ignore the passed-in font and replace it with monospace (same size)
      let newFont = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .bold)

      // call the *original* method with our font instead
      _ = self.perform(
        NSSelectorFromString("_original_updateTextPropertiesWithFont:"),
        with: newFont
      )
    }

    @objc class func run() {
      guard let cls = NSClassFromString("NSToolbarPrimaryTitleContainerView") else {
        return
      }

      let sel = NSSelectorFromString("updateTextPropertiesWithFont:")
      let originalSel = NSSelectorFromString("_original_updateTextPropertiesWithFont:")

      guard
        let m1 = class_getInstanceMethod(cls, sel),
        let m2 = class_getInstanceMethod(Self.self, sel)
      else {
        return
      }

      // add the backup for the original
      class_addMethod(
        cls,
        originalSel,
        method_getImplementation(m1),
        method_getTypeEncoding(m1)
      )

      // and swap ‘em ✨
      method_exchangeImplementations(m1, m2)
    }
  }

#endif
