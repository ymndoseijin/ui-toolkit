#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aTexCoord;
layout (location = 2) in vec3 aNormal;

uniform mat4 transform;
uniform mat4 model;

uniform vec2 in_resolution;
uniform float time;
uniform float bright;
uniform vec3 pos;

out vec2 TexCoord;
out vec3 Normal;
out float Time;

void main()
{
   vec3 position = aPos;
   //position /= mix(sqrt(position.x*position.x+position.y*position.y+position.z*position.z), 1, cos(time*0.5)+1);
   position /= sqrt(position.x*position.x+position.y*position.y+position.z*position.z);

   //float t = (cos(time*0.5)+1)/2;
   //mat4 actual = (1-t)*mat4(1.0)+model*t;
   vec4 vert = transform*model*vec4(position, 1.0);
   gl_Position = vert;
   TexCoord = aTexCoord;
   Time = time;
   Normal = aNormal;
}