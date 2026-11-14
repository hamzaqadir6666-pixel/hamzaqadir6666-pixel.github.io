// Dynamic sky: day gradient, sunset scattering, sun & moon discs, stars, drifting clouds.
shader_type sky;

uniform vec3 zenith_day : source_color = vec3(0.16, 0.36, 0.72);
uniform vec3 horizon_day : source_color = vec3(0.62, 0.76, 0.88);
uniform vec3 zenith_night : source_color = vec3(0.004, 0.008, 0.022);
uniform vec3 horizon_night : source_color = vec3(0.02, 0.035, 0.065);
uniform vec3 sunset_color : source_color = vec3(1.0, 0.42, 0.14);
uniform vec3 ground_color : source_color = vec3(0.10, 0.13, 0.09);
uniform float day_factor = 1.0;       // 0 night .. 1 day
uniform float sunset_factor = 0.0;    // 0..1 around sunrise / sunset
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed = 0.006;
uniform float overcast : hint_range(0.0, 1.0) = 0.0;   // storm: grey, heavy sky
uniform float star_intensity = 1.0;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);   // toward the sun
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_energy = 1.0;
uniform float moon_energy = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = clamp(dir.y, 0.0, 1.0);
	float horizon = pow(1.0 - up, 3.0);
	vec3 day = mix(zenith_day, horizon_day, horizon);
	vec3 night = mix(zenith_night, horizon_night, horizon);
	vec3 col = mix(night, day, day_factor);

	// warm band toward the sun at dawn / dusk
	float sun_dot = max(dot(dir, sun_direction), 0.0);
	float toward = max(dot(normalize(vec3(dir.x, 0.0, dir.z) + vec3(0.0001)), normalize(vec3(sun_direction.x, 0.0, sun_direction.z) + vec3(0.0001))), 0.0);
	col = mix(col, sunset_color, sunset_factor * horizon * (0.35 + 0.65 * toward * toward));
	col += sunset_color * sunset_factor * pow(sun_dot, 8.0) * 0.6;

	// stars
	if (day_factor < 0.6 && dir.y > -0.05) {
		vec3 g = floor(dir * 220.0);
		float h = hash(g);
		float star = step(0.9965, h) * (0.5 + 0.5 * sin(TIME * (1.0 + h * 3.0) + h * 40.0));
		col += vec3(star) * (1.0 - smoothstep(0.1, 0.6, day_factor)) * star_intensity * smoothstep(-0.05, 0.25, dir.y);
	}

	// sun disc + glow
	if (sun_energy > 0.001) {
		float sd = distance(dir, sun_direction);
		float e = clamp(sun_energy, 0.0, 1.5);
		col += sun_color * smoothstep(0.045, 0.035, sd) * 12.0 * e;
		col += sun_color * pow(sun_dot, 180.0) * 0.8 * min(e, 1.0);
		col += sun_color * pow(sun_dot, 12.0) * 0.12 * min(e, 1.0);
	}
	// moon disc + halo
	if (moon_energy > 0.001) {
		float md = distance(dir, moon_direction);
		float disc = smoothstep(0.034, 0.030, md);
		float crater = texture(noise_tex, dir.xz * 6.0 + dir.y * 3.0).r;
		col += vec3(0.85, 0.9, 1.0) * disc * (0.75 + 0.35 * crater) * 1.6 * (1.0 - day_factor * 0.9);
		col += vec3(0.35, 0.45, 0.7) * pow(max(dot(dir, moon_direction), 0.0), 60.0) * 0.25 * (1.0 - day_factor);
	}

	// clouds (projected noise layers)
	if (dir.y > 0.01) {
		vec2 cuv = dir.xz / (dir.y + 0.12) * 0.12 + TIME * cloud_speed * vec2(1.0, 0.35);
		float n = texture(noise_tex, cuv).r * 0.6 + texture(noise_tex, cuv * 2.7 + vec2(0.4, 0.8)).r * 0.4;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, n) * smoothstep(0.01, 0.2, dir.y);
		vec3 cloud_day = mix(vec3(0.95, 0.96, 0.98), vec3(0.6, 0.63, 0.7), smoothstep(0.5, 1.0, n));
		vec3 cloud_col = mix(vec3(0.03, 0.04, 0.07), cloud_day, day_factor);
		cloud_col = mix(cloud_col, sunset_color * 1.1, sunset_factor * 0.6 * (0.3 + 0.7 * toward));
		cloud_col = mix(cloud_col, cloud_col * vec3(0.42, 0.45, 0.5), overcast);
		col = mix(col, vec3(0.30, 0.33, 0.37) * max(day_factor, 0.04), overcast * 0.75);
		col = mix(col, cloud_col, c * mix(0.85, 1.0, overcast));
	}
	if (dir.y < 0.0) {
		col = mix(col, ground_color * mix(0.08, 1.0, day_factor), smoothstep(0.0, -0.08, dir.y));
	}
	COLOR = col;
}
