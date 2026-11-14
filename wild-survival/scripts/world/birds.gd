class_name Birds
extends Node3D
## Real birds in the sky: hawks soaring high over the clearings and crows wheeling lower down.
## Crows are a tell worth watching - when a hunter makes a kill, the nearest flock gathers above it.

const HAWK := "res://models/animals/hawk.glb"
const CROW := "res://models/animals/crow.glb"

var world: WorldData
var follow: Node3D
var birds: Array[Dictionary] = []   ## {rig, node, kind, center: Vector2, radius, height, speed, phase, flock}
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func setup(p_world: WorldData) -> void:
	world = p_world
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = world.seed_value + 901
	var n := world.clearings.size()
	for i in 5:
		var c: Vector2 = world.clearings[(i * 2) % n]["center"]
		_add("hawk", c + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)), _rng.randf_range(35.0, 70.0), _rng.randf_range(38.0, 60.0), _rng.randf_range(7.0, 9.5), -1)
	for f in 4:
		var c2: Vector2 = world.clearings[(f * 2 + 1) % n]["center"]
		for k in 5:
			_add("crow", c2, _rng.randf_range(10.0, 24.0), _rng.randf_range(13.0, 22.0), _rng.randf_range(6.0, 8.0), f)


func _add(kind: String, center: Vector2, radius: float, height: float, speed: float, flock: int) -> void:
	var node := Node3D.new()
	node.name = "%s%d" % [kind.capitalize(), birds.size()]
	add_child(node)
	var rig := AnimalRig.new()
	node.add_child(rig)
	rig.setup(HAWK if kind == "hawk" else CROW, 0.2 if kind == "hawk" else 0.24, {}, false)
	rig.play("Walk" if kind == "crow" else "Idle", 1.0, 0.0)
	rig.set_shadow(false)
	birds.append({"rig": rig, "node": node, "kind": kind, "center": center, "home": center, "radius": radius, "height": height,
		"speed": speed, "phase": _rng.randf() * TAU, "flock": flock, "dir": 1.0 if _rng.randf() < 0.5 else -1.0, "flap": _rng.randf_range(4.0, 12.0)})


func count(kind: String) -> int:
	var n := 0
	for b in birds:
		if b["kind"] == kind:
			n += 1
	return n


## A kill: the nearest crow flock comes to circle above it for a while.
func gather_over(pos: Vector3) -> void:
	var p := Vector2(pos.x, pos.z)
	var best := -1
	var bd := INF
	for b in birds:
		if b["kind"] == "crow":
			var d: float = (b["home"] as Vector2).distance_to(p)
			if d < bd:
				bd = d
				best = int(b["flock"])
	for b in birds:
		if int(b["flock"]) == best:
			b["target"] = p
			b["visit"] = 70.0


func _process(delta: float) -> void:
	_time += delta
	for b in birds:
		var node: Node3D = b["node"]
		var center: Vector2 = b["center"]
		# flocks drift to a kill and back home again
		if b.has("visit"):
			b["visit"] = float(b["visit"]) - delta
			var goal: Vector2 = b["target"] if float(b["visit"]) > 0.0 else b["home"]
			center = center.move_toward(goal, delta * 9.0)
			b["center"] = center
			if float(b["visit"]) <= 0.0 and center.distance_to(b["home"]) < 1.0:
				b.erase("visit")
		var ang_speed: float = float(b["speed"]) / float(b["radius"]) * float(b["dir"])
		b["phase"] = float(b["phase"]) + ang_speed * delta
		var ph: float = b["phase"]
		var r: float = float(b["radius"]) * (1.0 + 0.15 * sin(ph * 0.37 + float(b["height"])))
		var x := center.x + cos(ph) * r
		var z := center.y + sin(ph) * r
		var y := maxf(world.height_at(x, z), WorldData.WATER_LEVEL) + float(b["height"]) + sin(ph * 0.6) * 2.0
		node.position = Vector3(x, y, z)
		# face along the circle, banking into the turn
		var tangent := Vector3(-sin(ph), 0.0, cos(ph)) * float(b["dir"])
		node.rotation.y = atan2(-tangent.x, -tangent.z)
		node.rotation.z = 0.35 * float(b["dir"])
		# hawks glide, with a few wingbeats now and then
		if b["kind"] == "hawk":
			b["flap"] = float(b["flap"]) - delta
			var rig: AnimalRig = b["rig"]
			if float(b["flap"]) < 0.0:
				b["flap"] = _rng.randf_range(6.0, 14.0)
			rig.play("Walk" if float(b["flap"]) < 1.8 else "Idle", 1.0, 0.5)
		# far-away birds do not need animating
		if follow != null:
			var far := node.position.distance_squared_to(follow.global_position) > 260.0 * 260.0
			node.visible = not far
			(b["rig"] as AnimalRig).set_paused(far)
