shader_type canvas_item;
render_mode unshaded;

uniform float seed = 8.0;
uniform float time_scale = 0.0012;
uniform vec4 wei_region;
uniform vec4 shu_region;
uniform vec4 wu_region;
uniform vec4 neutral_region;
uniform vec2 qinling_points[7];
uniform vec2 yangtze_points[7];

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345 + seed);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    mat2 rotation = mat2(vec2(0.82, 0.57), vec2(-0.57, 0.82));
    for (int i = 0; i < 7; i++) {
        value += amplitude * noise(p);
        p = rotation * p * 2.03 + vec2(7.1, 3.8);
        amplitude *= 0.5;
    }
    return value;
}

float ellipse_mask(vec2 p, vec2 center, vec2 radius, float feather) {
    float d = length((p - center) / radius);
    return 1.0 - smoothstep(1.0 - feather, 1.0 + feather, d);
}

float region_mask(vec2 p, vec4 region, float phase) {
    vec2 q = (p - region.xy) / region.zw;
    float angle = atan(q.y, q.x);
    float boundary = 1.0 + sin(angle * 3.0 + phase) * 0.085;
    boundary += sin(angle * 5.0 - phase * 0.70) * 0.045;
    return 1.0 - smoothstep(boundary - 0.20, boundary + 0.08, length(q));
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    return length(p - (a + ab * t));
}

float qinling_distance(vec2 p) {
    float distance_to_path = 10.0;
    for (int index = 0; index < 6; index++) {
        distance_to_path = min(distance_to_path, segment_distance(p, qinling_points[index], qinling_points[index + 1]));
    }
    return distance_to_path;
}

float yangtze_distance(vec2 p) {
    float distance_to_path = 10.0;
    for (int index = 0; index < 6; index++) {
        distance_to_path = min(distance_to_path, segment_distance(p, yangtze_points[index], yangtze_points[index + 1]));
    }
    return distance_to_path;
}

void fragment() {
    vec2 uv = UV;
    vec2 aspect_uv = vec2(uv.x * 1.78, uv.y);
    float drift = TIME * time_scale;

    vec2 warp = vec2(
        fbm(aspect_uv * 1.35 + vec2(1.7 + drift, 8.1)),
        fbm(aspect_uv * 1.55 + vec2(9.4, 2.3 - drift))
    ) - 0.5;
    vec2 terrain_uv = aspect_uv + warp * 0.21;
    float macro = fbm(terrain_uv * 2.15);
    float mid = fbm(terrain_uv * 4.8 + vec2(4.2, 9.1));
    float detail = fbm(terrain_uv * 10.5 + vec2(11.0, 2.0));
    float micro = fbm(terrain_uv * 22.0 + vec2(3.0, 17.0));
    float ridged = pow(clamp(1.0 - abs(detail * 2.0 - 1.0), 0.0, 1.0), 4.0);
    float hairline = pow(clamp(1.0 - abs(micro * 2.0 - 1.0), 0.0, 1.0), 12.0);
    float cross_detail = fbm(vec2(terrain_uv.y * 15.0, terrain_uv.x * 9.0) + vec2(18.0, 5.0));
    float cross_ridge = pow(clamp(1.0 - abs(cross_detail * 2.0 - 1.0), 0.0, 1.0), 5.0);
    float ridge_field = clamp(ridged * 0.70 + cross_ridge * 0.58, 0.0, 1.0);
    float fracture_field = smoothstep(0.46, 0.66, detail * 0.52 + micro * 0.28 + cross_ridge * 0.48);

    // These four masks come directly from terrain.json via ConnectedContinent.
    // The minimap uses the same world-space centres and radii.
    float north_plain = region_mask(uv, wei_region, 0.35);
    float sichuan = region_mask(uv, shu_region, 1.70);
    float eastern_delta = region_mask(uv, wu_region, 3.10);
    float west = region_mask(uv, neutral_region, 4.45);
    float qinling_bridge = 1.0 - smoothstep(0.035, 0.120, qinling_distance(uv));
    float yangtze_bridge = 1.0 - smoothstep(0.030, 0.100, yangtze_distance(uv));
    float connected_mass = max(qinling_bridge * 0.82, yangtze_bridge * 0.76);
    float land = clamp(max(max(max(west, north_plain), max(sichuan, eastern_delta)), connected_mass), 0.0, 1.0);
    land *= smoothstep(0.12, 0.72, macro + land * 0.42);

    // Qinling: massive in the west, pinched at Hanzhong Pass, rebuilt through
    // the centre and fractured into luminous shards toward the east.
    float qinling_path_distance = qinling_distance(uv + vec2(0.0, (mid - 0.5) * 0.018));
    float qinling_extent = smoothstep(qinling_points[0].x - 0.03, qinling_points[0].x + 0.03, uv.x);
    qinling_extent *= 1.0 - smoothstep(qinling_points[6].x - 0.03, qinling_points[6].x + 0.03, uv.x);
    float western_mass = 1.0 - smoothstep(0.22, 0.47, uv.x);
    float pass_cut = 1.0 - 0.80 * exp(-pow((uv.x - 0.345) / 0.035, 2.0));
    float eastern_fracture = mix(1.0, smoothstep(0.33, 0.78, detail), smoothstep(0.68, 0.92, uv.x));
    float mountain_width = mix(0.078, 0.135, western_mass);
    float mountain_distance = qinling_path_distance + (mid - 0.5) * 0.038;
    float mountain = (1.0 - smoothstep(mountain_width * 0.28, mountain_width, mountain_distance));
    mountain *= qinling_extent * pass_cut * eastern_fracture;
    float mountain_ridges = mountain * clamp(ridge_field * 0.78 + hairline * 0.42, 0.0, 1.0);
    float mountain_fragment = smoothstep(0.34, 0.66, detail * 0.54 + ridge_field * 0.60);
    float mountain_core = mountain * smoothstep(0.40, 0.78, mid) * mix(0.10, 0.74, mountain_fragment);
    float mountain_scree = mountain * fracture_field * smoothstep(0.20, 0.86, mountain_distance / mountain_width);

    // Hanzhong -> Jingzhou -> Red Cliffs: a broad curved strategic valley.
    float valley_distance = yangtze_distance(uv);
    valley_distance += (detail - 0.5) * 0.028;
    float strategic_valley = 1.0 - smoothstep(0.035, 0.145, valley_distance);

    // Volumetric Yangtze river basin follows the lower edge of the valley and
    // broadens into Wu's luminous eastern delta.
    float river_extent = smoothstep(yangtze_points[0].x - 0.03, yangtze_points[0].x + 0.03, uv.x);
    river_extent *= 1.0 - smoothstep(yangtze_points[6].x - 0.03, yangtze_points[6].x + 0.03, uv.x);
    float river_distance = yangtze_distance(uv + vec2(0.0, (mid - 0.5) * 0.020));
    float river_basin = (1.0 - smoothstep(0.022, 0.108, river_distance)) * river_extent;
    float river_bank = (1.0 - smoothstep(0.014, 0.052, river_distance)) * river_extent;
    float river_core = (1.0 - smoothstep(0.005, 0.032, river_distance)) * river_extent;
    float river_glint = (1.0 - smoothstep(0.002, 0.014, river_distance)) * river_extent;

    // Sichuan is a bright inhabited basin enclosed by a darker mountainous rim.
    float basin_d = length((uv - vec2(0.22, 0.71)) / vec2(0.25, 0.22));
    float basin_floor = 1.0 - smoothstep(0.35, 0.82, basin_d);
    float basin_rim = smoothstep(0.55, 0.82, basin_d) * (1.0 - smoothstep(0.82, 1.10, basin_d));

    vec3 deep_space = vec3(0.0015, 0.005, 0.012);
    vec3 lowland = vec3(0.018, 0.045, 0.072);
    vec3 highland = vec3(0.075, 0.155, 0.215);
    vec3 starlight = vec3(0.30, 0.63, 0.90);
    vec3 color = deep_space;

    float cloud_mass = land * smoothstep(0.18, 0.66, macro + mid * 0.30);
    float rock_mass = land * smoothstep(0.40, 0.68, macro * 0.66 + mid * 0.46 + ridge_field * 0.18);
    float rock_face = rock_mass * smoothstep(0.34, 0.66, ridge_field + macro * 0.30);
    float cliff = rock_mass * smoothstep(0.38, 0.62, ridge_field + detail * 0.26);
    float shard_mass = land * fracture_field * smoothstep(0.28, 0.70, macro + ridge_field * 0.42);
    float occlusion = rock_mass * smoothstep(0.56, 0.80, macro - detail * 0.22);
    color = mix(color, lowland, cloud_mass * 0.42);
    color += vec3(0.052, 0.053, 0.055) * rock_mass * (0.54 + detail * 0.30);
    color += vec3(0.120, 0.112, 0.098) * rock_face * 0.48;
    color += vec3(0.075, 0.088, 0.098) * shard_mass * (0.24 + cross_ridge * 0.50);
    color += highland * land * ridge_field * (0.08 + mid * 0.25);
    color += starlight * land * hairline * 0.025;
    color *= 1.0 - occlusion * 0.47;
    color += vec3(0.15, 0.135, 0.112) * cliff * (1.0 - occlusion) * 0.38;
    float connection_rock = connected_mass * smoothstep(0.30, 0.72, macro + detail * 0.30);
    color += vec3(0.052, 0.055, 0.058) * connected_mass * (0.34 + mid * 0.34);
    color += vec3(0.14, 0.13, 0.115) * connection_rock * ridged * 0.34;

    // Broad interior illumination identifies the four powers without drawing
    // luminous closed borders. It is modulated by terrain mass, so political
    // colour settles into dust and rock instead of floating over the map.
    float wei_influence = north_plain;
    float shu_influence = sichuan;
    float wu_influence = eastern_delta;
    float tint_texture = cloud_mass * (0.22 + 0.52 * mid) + rock_face * 0.20;
    color += vec3(0.015, 0.105, 0.245) * wei_influence * tint_texture;
    color += vec3(0.012, 0.180, 0.075) * shu_influence * tint_texture;
    color += vec3(0.235, 0.030, 0.018) * wu_influence * tint_texture;
    color += vec3(0.160, 0.095, 0.020) * west * tint_texture;

    // Fragmented mineral shelves make each power read as a different geological
    // plate. The noisy gaps keep these from becoming luminous closed borders.
    float wei_shelf = smoothstep(0.18, 0.44, wei_influence) * (1.0 - smoothstep(0.56, 0.84, wei_influence));
    float shu_shelf = smoothstep(0.18, 0.44, shu_influence) * (1.0 - smoothstep(0.56, 0.84, shu_influence));
    float wu_shelf = smoothstep(0.18, 0.44, wu_influence) * (1.0 - smoothstep(0.56, 0.84, wu_influence));
    float west_shelf = smoothstep(0.18, 0.44, west) * (1.0 - smoothstep(0.56, 0.84, west));
    float shelf_fragments = fracture_field * smoothstep(0.28, 0.72, ridge_field + mid * 0.34);
    color += vec3(0.055, 0.19, 0.34) * wei_shelf * shelf_fragments * 0.34;
    color += vec3(0.035, 0.23, 0.12) * shu_shelf * shelf_fragments * 0.34;
    color += vec3(0.30, 0.065, 0.040) * wu_shelf * shelf_fragments * 0.33;
    color += vec3(0.29, 0.17, 0.045) * west_shelf * shelf_fragments * 0.32;
    color += vec3(0.16, 0.145, 0.12) * max(max(wei_shelf, shu_shelf), max(wu_shelf, west_shelf)) * cliff * 0.28;
    color += vec3(0.025, 0.18, 0.11) * basin_floor * (0.40 + ridged * 0.60);
    color += vec3(0.12, 0.24, 0.16) * basin_rim * ridged * 0.45;
    color *= 1.0 - strategic_valley * 0.10;
    color += vec3(0.018, 0.080, 0.125) * strategic_valley * (0.28 + mid * 0.30);
    color += vec3(0.028, 0.20, 0.32) * river_basin * (0.30 + ridge_field * 0.34);
    color += vec3(0.075, 0.34, 0.48) * river_bank * (0.26 + cross_ridge * 0.34);
    color += vec3(0.34, 0.70, 0.84) * river_core * (0.22 + ridged * 0.23);
    color += vec3(0.70, 0.88, 0.94) * river_glint * (0.16 + hairline * 0.20);

    // Mountain depth is created by a black core, violet illuminated ridges and
    // starless occlusion, not by a rectangular overlay.
    color *= 1.0 - mountain_core * 0.48;
    color += vec3(0.120, 0.070, 0.145) * mountain * 0.34;
    color += vec3(0.38, 0.25, 0.46) * mountain_ridges * 0.50;
    color += vec3(0.20, 0.16, 0.205) * mountain_scree * 0.38;
    color += vec3(0.18, 0.155, 0.17) * mountain * cliff * (1.0 - mountain_core) * 0.24;

    // Warm western dust and red eastern illumination remain part of the same terrain.
    color += vec3(0.28, 0.145, 0.028) * west * (0.25 + ridged * 0.42 + rock_face * 0.30);
    color += vec3(0.36, 0.235, 0.080) * west * cliff * 0.38;
    color += vec3(0.20, 0.035, 0.025) * eastern_delta * (0.10 + ridged * 0.26);

    // Dark basins break the terrain into readable heights without reopening a
    // featureless black rectangle in the centre.
    float void_a = ellipse_mask(uv, vec2(0.43, 0.78), vec2(0.11, 0.10), 0.22);
    float void_b = ellipse_mask(uv, vec2(0.72, 0.36), vec2(0.14, 0.11), 0.24);
    float voids = max(void_a, void_b) * smoothstep(0.52, 0.80, detail);
    color *= 1.0 - voids * 0.38;

    // Dense multi-scale stars embedded in the geography.
    vec2 star_grid = uv * vec2(1080.0, 610.0);
    vec2 star_cell = floor(star_grid);
    vec2 star_local = fract(star_grid) - 0.5;
    float star_random = hash(star_cell + 91.7);
    float star = smoothstep(0.050, 0.0, length(star_local)) * step(0.982, star_random);
    star *= 0.28 + land * 0.72;
    star *= 1.0 - mountain * 0.72;
    vec3 star_color = mix(vec3(0.35, 0.68, 1.0), vec3(1.0, 0.78, 0.40), step(0.996, star_random));
    color += star_color * star * 1.28;

    float vignette = 1.0 - smoothstep(0.48, 0.82, length((uv - 0.5) * vec2(0.92, 1.02)));
    color *= 0.72 + vignette * 0.36;
    COLOR = vec4(color, 1.0);
}
