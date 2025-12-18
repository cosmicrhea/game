#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aTexCoord;
layout(location = 3) in vec3 aTangent;
layout(location = 4) in vec3 aBitangent;
layout(location = 5) in ivec4 aBoneIndices;
layout(location = 6) in vec4 aBoneWeights;

out vec2 TexCoord;
out vec3 Normal;
out vec3 FragPos;
out vec3 Tangent;
out vec3 Bitangent;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

// Bone transformation matrices (up to 100 bones)
uniform mat4 boneTransforms[100];
uniform int numBones;

void main() {
  // Initialize with zero (will accumulate weighted transforms)
  vec4 totalPosition = vec4(0.0);
  vec3 totalNormal = vec3(0.0);
  vec3 totalTangent = vec3(0.0);
  vec3 totalBitangent = vec3(0.0);
  
  // Apply bone transformations if this mesh has bones
  if (numBones > 0) {
    // Loop through up to 4 bone influences (matching LearnOpenGL approach)
    for(int i = 0; i < 4; i++) {
      int boneIndex;
      float weight;
      
      // Get bone index and weight based on component
      if(i == 0) {
        boneIndex = aBoneIndices.x;
        weight = aBoneWeights.x;
      } else if(i == 1) {
        boneIndex = aBoneIndices.y;
        weight = aBoneWeights.y;
      } else if(i == 2) {
        boneIndex = aBoneIndices.z;
        weight = aBoneWeights.z;
      } else {
        boneIndex = aBoneIndices.w;
        weight = aBoneWeights.w;
      }
      
      // Skip if weight is zero or bone index is invalid (-1 means unused, like LearnOpenGL)
      if(weight < 0.0001 || boneIndex < 0 || boneIndex >= 100) {
        continue;
      }
      
      // Transform vertex by this bone's matrix
      vec4 localPosition = boneTransforms[boneIndex] * vec4(aPos, 1.0);
      totalPosition += localPosition * weight;
      
      // Transform normal, tangent, bitangent by this bone's matrix
      vec3 localNormal = mat3(boneTransforms[boneIndex]) * aNormal;
      vec3 localTangent = mat3(boneTransforms[boneIndex]) * aTangent;
      vec3 localBitangent = mat3(boneTransforms[boneIndex]) * aBitangent;
      totalNormal += localNormal * weight;
      totalTangent += localTangent * weight;
      totalBitangent += localBitangent * weight;
    }
  } else {
    // No bones - use original vertex data
    totalPosition = vec4(aPos, 1.0);
    totalNormal = aNormal;
    totalTangent = aTangent;
    totalBitangent = aBitangent;
  }

  // Transform to world space using model matrix
  FragPos = vec3(model * totalPosition);
  
  // Transform normal, tangent, bitangent to world space
  Normal = mat3(transpose(inverse(model))) * totalNormal;
  Tangent = mat3(transpose(inverse(model))) * totalTangent;
  Bitangent = mat3(transpose(inverse(model))) * totalBitangent;

  // Match LearnOpenGL: view * model then projection * viewModel * position
  mat4 viewModel = view * model;
  gl_Position = projection * viewModel * totalPosition;
  TexCoord = aTexCoord;
}
