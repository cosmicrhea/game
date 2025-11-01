
-  ✅ Make `Color` codable (or what's it called? raw representable?) so we don't need `accentRGBA` nonsense

- Finish up `TextField`
  - ✅ Use GLFW’s thing for text input instead of the madness we currently have
  - ✅ Either remove multi-line text inputs (from the demo) or fix them (line height, Y-flipped issues)
  - ✅ Add copy/cut/paste via keyboard shortcuts (native context menu can follow later)
  - Make it “scroll” when at the ends and you have a long text that gets clipped

- `ScrollView`
  - Fix rubberbanding; feed raw scroll data to Cursor so it can figure it out
  - `var isFocusable: Bool`
    - Automatic scrolling when focus changes to next item
  - Honestly wish we could hack in so we overlay actual platform scroll views and get the exact native behavior, so on macOS we’d have a NSScrollView on top of (or offscreen, with metrics matching and events forwarded) all our ScrollViews and they’d like… yeah… just feel 100% native. How crazy of an idea is that? Be honest. 

- `PopupMenu`
  - ✅ Fix click areas
  - Ensure proper abstraction

- [Cursed] Figure out UI scaling
- [Cursed] Flip Y globally

- Game
  - ✅ Render prerendered environment
  - ✅ Add debug character and movement
  - Integrate with prerendered environment
  - Add collisions
  - Add camera triggers
  - Add multiple rooms

- [Deps] Hack hi-dpi support into GLFW

# 2D


- also, g, do you think we could introduce an `isFlipped: Bool` on our GraphicsContext? maybe it's too lat enow… but… i think it will help in the future

