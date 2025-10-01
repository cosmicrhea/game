import GLMath

// Helper to pretty print vec3 for the debug label
func StringFromGLMathVec3(_ v: vec3) -> String {
  return String(format: "(%.1f, %.1f, %.1f)", v.x, v.y, v.z)
}
