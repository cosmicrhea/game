final class MovieDemo: RenderLoop {
  private let movies = [
    "Scenes/Doors/door03_1",
    "Scenes/Doors/door03_2",
    // Add more movie paths here as you get them
  ]

  private var currentMovieIndex = 0
  private var currentMovie: Movie?
  private var hasStarted = false
  private var movieElapsedTime: Float = 0.0
  private var hasPlayedOpenSound = false

  func update(deltaTime: Float) {
    guard !movies.isEmpty else { return }

    // Initialize first movie if needed
    if !hasStarted {
      loadMovie(at: currentMovieIndex)
      hasStarted = true
    }

    // Update current movie
    currentMovie?.update(deltaTime: Double(deltaTime))

    // Track elapsed time for door open sound (200ms delay)
    if currentMovie != nil {
      movieElapsedTime += deltaTime
      if movieElapsedTime >= 0.2 && !hasPlayedOpenSound {
        UISound.doorOpenA()
        hasPlayedOpenSound = true
      }
    }
  }

  func draw() {
    GraphicsContext.current?.renderer.setClearColor(.almostBlack)
    currentMovie?.draw()
  }

  func onAttach(window: Window) {
    // Reset on attach
    hasStarted = false
    currentMovieIndex = 0
    currentMovie?.stop()
    currentMovie = nil
    movieElapsedTime = 0.0
    hasPlayedOpenSound = false
  }

  func onDetach(window: Window) {
    currentMovie?.stop()
    currentMovie = nil
    hasStarted = false
  }

  private func loadMovie(at index: Int) {
    guard index >= 0 && index < movies.count else { return }

    // Stop previous movie
    currentMovie?.stop()

    // Create and play new movie
    let movie = Movie(movies[index])
    // Disable auto-looping so we can detect when it ends
    movie.setAutoLoop(false)
    // Set callback to advance to next movie when this one finishes
    movie.onLoop { [weak self] in
      self?.advanceToNextMovie()
    }

    do {
      try movie.play()
      currentMovie = movie
      // Reset timing for new movie
      movieElapsedTime = 0.0
      hasPlayedOpenSound = false
    } catch {
      logger.error("Failed to play movie \(movies[index]): \(error)")
      // Try next movie
      advanceToNextMovie()
    }
  }

  private func advanceToNextMovie() {
    guard movies.count > 1 else { return }  // Don't advance if only one movie
    currentMovieIndex = (currentMovieIndex + 1) % movies.count
    loadMovie(at: currentMovieIndex)
  }
}
