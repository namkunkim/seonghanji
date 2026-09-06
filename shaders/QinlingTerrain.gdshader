shader_type canvas_item;
render_mode unshaded;

uniform float segment_phase = 0.0;
uniform float pass_position = 0.35;
uniform float pass_strength = 0.85;
uniform float western_mass = 1.0;
uniform float eastern_fracture = 0.0;

float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0,1.0)),f.x),f.y);}
float fbm(vec2 p){float v=0.0,a=.5;for(int i=0;i<6;i++){v+=a*noise(p);p=p*2.05+vec2(7.2,4.1);a*=.5;}return v;}
void fragment(){
    vec2 uv=UV;
    float x=uv.x;
    float n=fbm(vec2(x*8.0+segment_phase,uv.y*5.0));
    float n2=fbm(vec2(x*18.0+2.0,uv.y*10.0+segment_phase));
    float center=.50+sin(x*6.0+segment_phase)*.045+(n-.5)*.055;

    float west_mass=(1.0-smoothstep(0.0,0.72,x))*western_mass;
    float width=.15+.085*west_mass+.030*sin(x*4.5+segment_phase);
    float pass=exp(-pow((x-pass_position)/.085,2.0))*pass_strength;
    width*=1.0-pass*.78;
    float east_break=smoothstep(.60,1.0,x)*smoothstep(.34,.78,n2)*(0.50+eastern_fracture*.50);
    float dy=abs(uv.y-center);
    float body=1.0-smoothstep(width,width+.12,dy);
    body*=1.0-east_break*.52;

    float core=smoothstep(.37,.72,n)*body;
    float ridge=pow(max(0.0,1.0-abs(n2*2.0-1.0)),7.0)*body;
    float ast=step(.965,hash(floor(uv*vec2(180.0,46.0))+segment_phase))*body;

    vec3 black_mass=mix(vec3(.002,.003,.008),vec3(.018,.021,.030),n*.45);
    vec3 violet=vec3(.22,.12,.36);
    vec3 edge=vec3(.58,.43,.76);
    vec3 c=black_mass;
    c=mix(c,violet,ridge*.30);
    c+=edge*ridge*.16;
    c+=vec3(.18,.19,.21)*ast*.55;
    float end_fade=smoothstep(.01,.10,x)*smoothstep(.01,.13,1.0-x);
    float alpha=body*(.48+.36*core+.18*ridge)*end_fade+ast*.28*end_fade;
    COLOR=vec4(c,clamp(alpha,0.0,.92));
}
