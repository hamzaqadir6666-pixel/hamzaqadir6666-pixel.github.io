// Distant bird silhouettes: wings flap in the vertex shader.
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float fade = 1.0;
void vertex() {
	// wings flap: vertices further from the body move more
	float phase = INSTANCE_CUSTOM.x * 6.28318;
	VERTEX.y += abs(VERTEX.x) * sin(TIME * (7.0 + INSTANCE_CUSTOM.y * 3.0) + phase) * 0.55;
}
void fragment() {
	ALBEDO = vec3(0.03, 0.03, 0.035);
	ALPHA = fade;
}
