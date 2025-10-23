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
  // Initialize with identity transformation
  mat4 boneTransform = mat4(1.0);

  // Apply bone transformations if this mesh has bones
  if (numBones > 0) {
    // Calculate weighted bone transformation
    boneTransform = aBoneWeights.x * boneTransforms[aBoneIndices.x] +
                    aBoneWeights.y * boneTransforms[aBoneIndices.y] +
                    aBoneWeights.z * boneTransforms[aBoneIndices.z] +
                    aBoneWeights.w * boneTransforms[aBoneIndices.w];
  }

  // Apply bone transformation to vertex position
  vec4 bonePosition = boneTransform * vec4(aPos, 1.0);
  FragPos = vec3(model * bonePosition);

  // Apply bone transformation to normal
  vec3 boneNormal = mat3(boneTransform) * aNormal;
  Normal = mat3(transpose(inverse(model))) * boneNormal;

  // Transform tangent and bitangent to world space
  vec3 boneTangent = mat3(boneTransform) * aTangent;
  vec3 boneBitangent = mat3(boneTransform) * aBitangent;
  Tangent = mat3(transpose(inverse(model))) * boneTangent;
  Bitangent = mat3(transpose(inverse(model))) * boneBitangent;

  gl_Position = projection * view * vec4(FragPos, 1.0);
  TexCoord = aTexCoord;
}
