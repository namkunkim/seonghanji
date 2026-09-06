shader_type canvas_item;
render_mode unshaded;

uniform float phase = 0.0;
uniform float basin_boost = 0.0;
uniform float valley_strength = 1.0;

float hash(vec2 p){return fract(sin(dot(p,vec2(12.98,78.23)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}
float fbm(vec2 p){float v=0.0,a=.5;for(int i=0;i<6;i++){v+=a*noise(p);p=p*2.02+vec2(5.5,8.9);a*=.5;}return v;}
void fragment(){
    vec2 uv=UV;
    float n=fbm(vec2(uv.x*7.0-TIME*.025+phase,uv.y*4.0));
    float n2=fbm(vec2(uv.x*15.0-TIME*.045,uv.y*8.0+phase));
    float center=.50+sin(uv.x*5.0+phase)*.06+sin(uv.x*12.0)*.02+(n-.5)*.035;
    float width=(.15+.045*sin(uv.x*4.0+1.5)+basin_boost*.10)*valley_strength;
    float dy=abs(uv.y-center);
    float broad=1.0-smoothstep(width,width+.18,dy);

    float channel_a=1.0-smoothstep(.020,.052,abs(uv.y-(center-.065-.028*sin(uv.x*8.0))));
    float channel_b=1.0-smoothstep(.018,.048,abs(uv.y-(center+.055+.025*sin(uv.x*10.0+2.0))));
    float channel_c=1.0-smoothstep(.015,.042,abs(uv.y-(center+.010*sin(uv.x*15.0)+basin_boost*.09*sin(uv.x*6.0))));
    float fog=smoothstep(.30,.78,n)*broad;
    float darker=smoothstep(.62,.84,n2)*broad;
    float island=step(.972,hash(floor(uv*vec2(180.0,54.0))+phase))*broad;

    vec3 deep=vec3(.018,.17,.27);
    vec3 cyan=vec3(.08,.50,.63);
    vec3 bright=vec3(.50,.86,.94);
    vec3 c=mix(deep,cyan,fog*.60);
    c=mix(c,bright,clamp(channel_a*.42+channel_b*.32+channel_c*.46,0.0,1.0));
    c*=1.0-darker*.24;
    c+=vec3(.19,.24,.27)*island*.55;
    float end_fade=smoothstep(.01,.11,uv.x)*smoothstep(.01,.11,1.0-uv.x);
    float alpha=(broad*(.10+.30*fog+.22*channel_a+.16*channel_b+.18*channel_c)+island*.28)*end_fade;
    COLOR=vec4(c,clamp(alpha,0.0,.78));
}
