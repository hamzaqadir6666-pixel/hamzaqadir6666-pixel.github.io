class_name WorldMap
extends RefCounted
## Top-down picture of the jungle painted from the terrain data: water, shores, grass, forest,
## trails, clearings and mountains. Used by the minimap, the full map (M) and the map export tool.

const WATER := Color(0.20, 0.47, 0.70)
const WATER_DEEP := Color(0.11, 0.30, 0.55)
const SHORE := Color(0.72, 0.68, 0.48)
const GRASS := Color(0.47, 0.66, 0.30)
const FOREST := Color(0.13, 0.33, 0.14)
const TRAIL := Color(0.62, 0.52, 0.36)
const ROCK := Color(0.56, 0.55, 0.52)
const PEAK := Color(0.86, 0.86, 0.84)

## Colours of the rare plants on every map (same ids as Forage.KINDS).
const PLANT_COLORS := {
	"clover": Color(0.30, 1.0, 0.40), "moonpetal": Color(0.55, 0.75, 1.0), "ironbark": Color(0.90, 0.45, 0.22),
	"sunberry": Color(1.0, 0.85, 0.15), "ghostfern": Color(0.92, 1.0, 0.96), "owlcap": Color(0.95, 0.55, 1.0),
	"springlily": Color(1.0, 0.5, 0.72), "lotus": Color(0.35, 0.95, 1.0), "herb": Color(0.55, 0.95, 0.65),
	"honey": Color(1.0, 0.62, 0.05), "toadstool": Color(1.0, 0.1, 0.1),
}


static func color_at(d: WorldData, x: float, z: float) -> Color:
	var h := d.height_at(x, z)
	var wd := d.water_distance(x, z)
	var c: Color
	if h < WorldData.WATER_LEVEL - 0.02:
		c = WATER.lerp(WATER_DEEP, clampf(-h / 2.5, 0.0, 1.0))
		return c
	c = GRASS.lerp(FOREST, clampf(d.forest_at(x, z) * 1.15, 0.0, 1.0))
	c = c.lerp(GRASS.lightened(0.12), clampf(d.clearing_at(x, z), 0.0, 1.0) * 0.6)
	c = c.lerp(TRAIL, clampf(d.trail_at(x, z), 0.0, 1.0) * 0.75)
	if wd < 2.5:
		c = c.lerp(SHORE, clampf(1.0 - wd / 2.5, 0.0, 1.0) * 0.8)
	# high ground turns to rock, then pale peaks
	c = c.lerp(ROCK, smoothstep(16.0, 34.0, h))
	c = c.lerp(PEAK, smoothstep(45.0, 75.0, h))
	# light from the north-west gives the hills some shape
	var shade := clampf((h - d.height_at(x - 3.0, z - 3.0)) * 0.09, -0.22, 0.22)
	return Color(clampf(c.r + shade, 0.0, 1.0), clampf(c.g + shade, 0.0, 1.0), clampf(c.b + shade, 0.0, 1.0))


## `size` pixels per side for the whole world (WorldData.SIZE metres).
static func build_image(d: WorldData, size := 512) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var step := WorldData.SIZE / float(size)
	for py in size:
		var z := -WorldData.HALF + (py + 0.5) * step
		for px in size:
			img.set_pixel(px, py, color_at(d, -WorldData.HALF + (px + 0.5) * step, z))
	return img


## World position (x, z) -> 0..1 map coordinates (north = -Z is up).
static func to_uv(x: float, z: float) -> Vector2:
	return Vector2((x + WorldData.HALF) / WorldData.SIZE, (z + WorldData.HALF) / WorldData.SIZE)
