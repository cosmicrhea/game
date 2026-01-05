#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;
layout(location = 2) in vec2 aTexCoord;
layout(location = 3) in vec3 aTangent;
layout(location = 4) in vec3 aBitangent;
layout(location = 5) in ivec4 aBoneIndices;
layout(location = 6) in vec4 aBoneWeights;
layout(location = 7) in vec2 aTexCoord1;

uniform mat4 lightSpaceMatrix;
uniform mat4 model;

// Bone transformation matrices (up to 100 bones)
uniform mat4 boneTransforms[100];
uniform int numBones;

void main() {
  vec4 position = vec4(aPos, 1.0);
  
  // Apply bone transformations if this mesh has bones
  if (numBones > 0) {
    vec4 totalPosition = vec4(0.0);
    
    // Loop through up to 4 bone influences
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
      
      // Apply bone transformation if valid
      if(boneIndex >= 0 && boneIndex < numBones && weight > 0.0) {
        totalPosition += boneTransforms[boneIndex] * position * weight;
      }
    }
    
    position = totalPosition;
  }
  
  gl_Position = lightSpaceMatrix * model * position;
}

