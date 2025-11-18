
- Refactor: Introduce some kind of (UI) Animation type

- UI: Add `FocusRing` type — an aesthetically pleasing focus indicator

- ✅ Add pause menu
- Add save states
- Add door state system (pending, locked, unlocked)
- Finish map area visibility/discovery system

- Finish Objectives system
  - Need some type of list of objectives and a pointer to the current one

- Item View: Add enter/exit transitions

- Map View: Do the thing where you can find the whole map of a place and then it shows up where it only shows the walls, no fill for the floors

- Slot Grid: Don’t show radial gradient / inner shadow on blank slots

- Inventory: Fix bug where discarding items or storing items leave a nil slot instead of a blank slot

- Inventory: Fix move mode bugs
- Inventory: Support wide items in slot grid

- Inventory: Add combine mode?
  - Data model support
  - RE2R-style combine mode
  - WHen entering combine mode, the prompt list switches to `.confirmCancel`
  - When entering combine mode, the slots in the grid are dimmed unless they are combinable with the selected item
  - You can move freely around the grid, but only combinable items show their name and description in the item view
  - Error sound plays if you try to confirm on an incompatible item
  - When combining successfully, a unique sound plays (i'll find one), and combination mode is exited 

- Inventory: Support inventory size expansion
  - Inside `Inventory` type, have a variable for number of slots (or rows?)
  - Slot grid in `InventoryView` and `ItemStorageView` need to be anchored at top and grown downwards on the screen as more inventory slots become available 

- Add proper bone animations
- Add animation blending somehow

- Finish `ModelViewer` (small UI adjustments)

- Editor: Nested editors / editor forwarding


# Assets

- Add first iteration of player character with animations
- Finish intro cutscene
- Finish tunnels
- Add streets
- Add act 1 cutscene
- Finish church scene
- Add metro station
- Finish metro maint. room
- Add metro maint. corridor
- Add Kastellet exterior
- Add Kastellet bridge
- …


# OLD TODOs 

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
- [Deps] Hack hi-dpi support for cursor images into GLFW

- Game
  - ✅ Render prerendered environment
  - ✅ Add debug character and movement
  - ✅ Integrate with prerendered environment
  - ✅ Add collisions
  - ✅ Add camera triggers
  - ✅ Add multiple rooms
