//import HarfBuzz
import GLMath

//import Pango

let keepersDiary = [
  """
  May 9, 1998

  At night, we played poker with Scott the guard, Alias and Steve the researcher.

  Steve was very lucky, but I think he was cheating. What a scumbag.
  """,
  """
  May 10th 1998

  Today, a high ranking researcher asked me to take care of a new monster. It looks like a gorilla without any skin. They told me to feed them live food. When I threw in a pig, they were playing with it... tearing off the pig's legs and pulling out the guts before they actually ate it.
  """,
  """
  May 11th 1998

  Around 5 o'clock this morning, Scott came in and woke me up suddenly. He was wearing a protective suit that looks like a space suit. He told me to put one on as well. I heard there was an accident in the basement lab. It's no wonder, those researchers never rest, even at night.
  """,
  """
  May 12th 1998

  I've been wearing this annoying space suit since yesterday, my skin grows musty and feels very itchy. By way of revenge, I didn't feed those dogs today. Now I feel better.
  """,
  """
  May 13th 1998

  I went to the medical room because my back is all swollen and feels itchy. They put a big bandage on my back and the doctor told me I did not need to wear the space suit any more. I guess I can sleep well tonight.
  """,
  """
  May 14th 1998

  When I woke up this morning, I found another blister on my foot. It was annoying and I ended up dragging my foot as I went to the dog's pen. They have been quiet since morning, which is very unusual. I found that some of them had escaped. I'll be in real trouble if the higher-ups find out.
  """,
  """
  May 15th 1998

  Even though I didn't feel well, I decided to go see Nancy. It's my first day off in a long time but I was stopped by the guard on the way out. They say the company has ordered that no one leave the grounds. I can't even make a phone call. What kind of joke is this?!
  """,
  """
  May 16th 1998

  I heard a researcher who tried to escape from this mansion was shot last night. My entire body feels burning and itchy at night. When I was scratching the swelling on my arms, a lump of rotten flesh dropped off. What the hell is happening to me?
  """,
  """
  May 19, 1998

  Fever gone but itchy. Hungry and eat doggy food. Itchy itchy Scott came. Ugly face so killed him. Tasty.
  """,
  """
  4

  Itchy.
  Tasty.
  """,
]

let green = Color(red: 0.1, green: 0.8, blue: 0.3)

class CaretRenderer {
  private let imageRenderer: ImageRenderer
  private let direction: Direction
  private var animationTime: Float = 0

  enum Direction {
    case left
    case right
  }

  init(direction: Direction) {
    self.direction = direction
    switch direction {
    case .left:
      self.imageRenderer = ImageRenderer("UI/Icons/Carets/caret-left.png")
    case .right:
      self.imageRenderer = ImageRenderer("UI/Icons/Carets/caret-right.png")
    }
  }

  func draw(x: Float, y: Float, windowSize: (Int32, Int32), tint: Color) {
    // Update animation time
    animationTime += 0.016  // Assuming ~60fps

    // Animate with slow back-and-forth movement
    let animationOffset: Float = GLMath.sin(animationTime * 0.8) * 8  // 8px amplitude, slow speed
    let animatedX: Float = direction == .left ? x - animationOffset : x + animationOffset

    imageRenderer.draw(x: animatedX, y: y, windowSize: windowSize, tint: tint)
  }
}

class DocumentDemo: RenderLoop {
  let caretLeft = CaretRenderer(direction: .left)
  let caretRight = CaretRenderer(direction: .right)

  let textRenderer = TextRenderer("Creato Display Medium", 24)

  func draw() {
    // Center text horizontally with 640px width
    let textX: Float = (Float(WIDTH) - 640) / 2
    let textY: Float = Float(HEIGHT) - 80

    // Position arrows on left and right of text, centered vertically
    let arrowY: Float = Float(HEIGHT) / 2
    let leftArrowX: Float = textX - 40
    let rightArrowX: Float = textX + 640 + 20

    caretLeft.draw(x: leftArrowX, y: arrowY, windowSize: (Int32(WIDTH), Int32(HEIGHT)), tint: green)

    textRenderer?.draw(
      keepersDiary[1],
      at: (textX, textY),
      windowSize: (Int32(WIDTH), Int32(HEIGHT)),
      scale: 2,
      wrapWidth: 640,
      anchor: .topLeft
    )

    caretRight.draw(x: rightArrowX, y: arrowY, windowSize: (Int32(WIDTH), Int32(HEIGHT)), tint: green)
  }
}
