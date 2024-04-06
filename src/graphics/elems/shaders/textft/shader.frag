#version 450
#extension GL_EXT_nonuniform_qualifier : require

layout (binding = 0) uniform SpatialUBO {
   float time;
   vec2 in_resolution;
} spatial_ubo;

layout (binding = 1) uniform OtherUBO {
   mat4 transform;
   float opacity;
   int index;
   int count;
   vec3 color;
} other_ubo[];

layout (location = 0) in vec2 uv;
layout (location = 1) flat in uint id;

layout (location = 0) out vec4 FragColor;

layout(binding = 2) uniform sampler2D texSampler[];

void main()
{
   vec4 col = texture(texSampler[nonuniformEXT(id)], uv);
   col.rgb *= other_ubo[nonuniformEXT(id)].color;
   col.a *= other_ubo[nonuniformEXT(id)].opacity;
   FragColor = col;
}

