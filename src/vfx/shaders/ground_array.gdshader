shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Ground Array chunk surface, owned by docs/TERRAIN_CRATER_DEFORMER.md §4.6.
//
// The chunk mesh is a flat grid whose UVs land exactly on height-texture texel
// centres (see GroundArray._build_chunk_mesh). Height comes from an R16 texture
// rather than from rebuilt vertex data, because committing a deformation is
// then an Image blit rather than a mesh reconstruction with a normal pass —
// which is the difference between a 0.14 ms commit and a visible hitch.
//
// Normals are derived here from the height texture, so no normal data is ever
// transferred. Colour is per-surface-class flat shading: doc 13 §10.2 puts
// Ground Arrays at STAGE_PROXY until real material sets exist, and an honest
// greybox is the specified behaviour rather than a placeholder.

uniform sampler2D u_height : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D u_surface : hint_default_black, filter_nearest, repeat_disable;

uniform float u_height_min = -128.0;
uniform float u_height_range = 512.0;
uniform float u_sample_spacing = 0.5;
uniform float u_chunk_samples = 129.0;

// One colour per SurfaceTable.Surface entry, in enum order.
uniform vec3 u_colour_compacted : source_color = vec3(0.34, 0.32, 0.28);
uniform vec3 u_colour_loose : source_color = vec3(0.47, 0.41, 0.30);
uniform vec3 u_colour_slick : source_color = vec3(0.38, 0.44, 0.48);
uniform vec3 u_colour_deformed : source_color = vec3(0.24, 0.21, 0.18);
uniform vec3 u_colour_structure : source_color = vec3(0.40, 0.40, 0.42);

uniform float u_roughness : hint_range(0.0, 1.0) = 0.94;

varying vec2 v_uv;
varying float v_height;


float height_at(vec2 uv) {
	return u_height_min + texture(u_height, uv).r * u_height_range;
}


vec3 colour_for_surface(float encoded) {
	// The surface texture is R8 carrying the enum ordinal; nearest filtering
	// keeps it an ordinal rather than blending two unrelated classes.
	int id = int(round(encoded * 255.0));
	if (id == 1) { return u_colour_loose; }
	if (id == 2) { return u_colour_slick; }
	if (id == 3) { return u_colour_deformed; }
	if (id == 4) { return u_colour_structure; }
	return u_colour_compacted;
}


void vertex() {
	v_uv = UV;
	VERTEX.y = height_at(UV);
	v_height = VERTEX.y;
}


void fragment() {
	float texel = 1.0 / u_chunk_samples;
	float hl = height_at(v_uv - vec2(texel, 0.0));
	float hr = height_at(v_uv + vec2(texel, 0.0));
	float hd = height_at(v_uv - vec2(0.0, texel));
	float hu = height_at(v_uv + vec2(0.0, texel));

	// Central differences over 2 * spacing, scaled through by that span so the
	// vertical term is the constant.
	vec3 n = normalize(vec3(hl - hr, 2.0 * u_sample_spacing, hd - hu));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	vec3 base = colour_for_surface(texture(u_surface, v_uv).r);

	// A slight darkening into hollows and lightening on crests reads as ambient
	// occlusion without an AO pass, and is what stops a large flat basin from
	// looking like a single untextured polygon at STAGE_PROXY.
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	ALBEDO = base * (1.0 - 0.35 * slope);
	ROUGHNESS = u_roughness;
	SPECULAR = 0.15;
}
