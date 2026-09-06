shader_type canvas_item;
render_mode unshaded;

uniform float seed = 1.0;
uniform vec4 glow_color : source_color = vec4(.35,.62,.75,1.0);
uniform float intensity = 0.45;

float hash(vec2 p){return fract(sin(dot(p,vec2(127.1+seed,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}
float fbm(vec2 p){float v=0.0,a=.5;for(int i=0;i<6;i++){v+=a*noise(p);p=p*2.04+vec2(3.7,9.2);a*=.5;}return v;}
void fragment(){
    vec2 uv=UV,q=(uv-.5)*2.0;
    float mask=1.0-smoothstep(.52,1.0,length(q*vec2(.86,1.14)));
    float n=fbm(uv*5.0+seed);
    float n2=fbm(uv*13.0+seed*2.0);
    float turbulence=pow(max(0.0,1.0-abs(n2*2.0-1.0)),7.0);
    float a=mask*(smoothstep(.28,.76,n)*.16+turbulence*.20)*intensity;
    vec3 c=mix(vec3(.025,.035,.045),glow_color.rgb,n*.40+turbulence*.25);
    COLOR=vec4(c,a);
}
