#version 330 core
out vec4 FragColor;

in vec2 TexCoord;
in vec3 Normal;
in float Time;
in vec3 Pos;

uniform sampler2D texture0;
uniform vec3 real_cam_pos;
uniform vec3 spatial_pos;
uniform float fog;

float RADIUS = 1.1;
float SURFACE = 1.0;


vec3 CENTER = vec3(0);

vec3 coeff = vec3(5.8e-6, 13.6e-6, 33.1e-6)*6471e3/RADIUS*0.1;
float FALLOFF = 4*RADIUS;

float dens(vec3 pos) {
   float h = length(pos-spatial_pos)-SURFACE;
   return exp(-h/(RADIUS-SURFACE)*FALLOFF);
}

const float STEPS = 19;

vec2 ray_sphere_intersect(
    vec3 start, // starting position of the ray
    vec3 dir, // the direction of the ray
    float radius // and the sphere radius
) {
    // ray-sphere intersection that assumes
    // the sphere is centered at the origin.
    // No intersection when result.x > result.y
    float a = dot(dir, dir);
    float b = 2.0 * dot(dir, start);
    float c = dot(start, start) - (radius * radius);
    float d = (b*b) - 4.0*a*c;
    if (d < 0.0) return vec2(1e5,-1e5);
    return vec2(
        (-b - sqrt(d))/(2.0*a),
        (-b + sqrt(d))/(2.0*a)
    );
}

vec3 transmittance(vec3 start, vec3 end) {
   vec3 dir = normalize(end-start);

   float DS = length(end-start)/STEPS;

   float b0 = 0.4;
   float res = 0;

   for (int i = 0; i < STEPS; i++) {
      float dens = dens(start);
      res += dens*DS;
      start += dir*DS;
   }
   return exp(-coeff*res);
}

float distance(float r, vec3 center, vec3 pos) {
   return length(pos-center)-r;
}

const float actual = 1.0;
float fac = RADIUS/actual;

void main()
{
   vec3 cam_pos = real_cam_pos*fac;
   vec3 position = Pos*fac;
   vec3 dir = normalize(position-cam_pos);

   vec2 hit = ray_sphere_intersect(cam_pos, dir, RADIUS);

   vec3 start = cam_pos+dir*hit.x;
   vec3 end = cam_pos+dir*hit.y;
   float DS = length(end-start)/STEPS;

   vec3 res = vec3(0);

   vec3 sun_pos = vec3(3.0, 0.0, 0.0)*fac;

   for (int i = 0; i < STEPS; i++) {
      start += dir*DS;

      float h = length(start);
      vec3 sunDiff = sun_pos-start;
      float dens = dens(start);
      float b0 = 1;
      vec3 Bh = dens*coeff;
      float phase = 3/(16*PI)*(1+pow(dot(dir, normalize(sunDiff)), 2));
      vec3 Lsun = 40*transmittance(start, sunDiff)*phase*Bh;
      res += transmittance(position, start)*Lsun*DS;
   }

   //res *= 4;

   //FragColor = vec4(vec3(hit.y-hit.x)/fac, 1.0);
   
   FragColor = vec4(res, 1.0);
}

