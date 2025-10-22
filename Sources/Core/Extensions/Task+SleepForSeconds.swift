extension Task where Success == Never, Failure == Never {
  public static func sleep(_ seconds: Double) async {
    try? await sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
  }
}
