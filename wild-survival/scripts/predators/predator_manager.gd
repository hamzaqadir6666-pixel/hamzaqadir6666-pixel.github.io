class_name PredatorManager
extends Node3D
## Spawns and tracks all predators, shares alerts between allies, raises a night-time hyena pack and
## publishes the overall threat level for the HUD and music.

const SCENES := {
	"lion": "res://scenes/predators/lion.tscn",
	"tiger": "res://scenes/predators/tiger.tscn",
	"cheetah": "res://scenes/predators/cheetah.tscn",
	"hyena": "res://scenes/predators/hyena.tscn",
}

const SPAWN_CLEARANCE := 95.0
const ROSTER_SIZE := 22

var world: WorldData
var player: Player
var day_night: DayNight
var predators: Array[Predator] = []
var max_awareness := 0.0
var nearest_hunter: Predator = null
var _night_pack: Array[Predator] = []
var prey: Node = null             ## PreyManager, set by the world
var allow_hunts := true
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _next_pack := 1


func setup(p_world: WorldData, p_player: Player, p_day_night: DayNight) -> void:
	world = p_world
	player = p_player
	day_night = p_day_night
	_rng.seed = world.seed_value + 77
	day_night.phase_changed.connect(_on_phase_changed)


func spawn_default_roster() -> void:
	# Lions hold the big clearings.
	spawn("lion", world.clearings[1]["center"])
	spawn("lion", world.clearings[5]["center"])
	spawn("lion", world.clearings[6]["center"] + Vector2(20.0, 10.0))
	spawn("lion", world.clearings[7]["center"])
	spawn("lion", world.clearings[0]["center"] + Vector2(35.0, -60.0))
	# Tigers haunt the jungle near water and trails.
	spawn("tiger", Vector2(-205.0, -150.0))
	spawn("tiger", Vector2(215.0, 185.0))
	spawn("tiger", Vector2(-30.0, -215.0))
	spawn("tiger", Vector2(-70.0, 60.0))
	spawn("tiger", Vector2(150.0, -30.0))
	# Cheetahs work the open eastern clearings.
	spawn("cheetah", world.clearings[2]["center"])
	spawn("cheetah", world.clearings[4]["center"])
	spawn("cheetah", world.clearings[3]["center"])
	spawn("cheetah", world.clearings[8]["center"])
	# Roaming hyena packs.
	spawn_pack(Vector2(-300.0, -60.0), 3)
	spawn_pack(Vector2(120.0, 240.0), 3)
	spawn_pack(Vector2(240.0, -20.0), 2)


func spawn(kind: String, where: Vector2, pack := 0) -> Predator:
	var p2 := world.random_land_point(_rng, where, 14.0)
	# never start a run with a hunter on top of the deer
	var away := p2 - world.spawn_point
	if away.length() < SPAWN_CLEARANCE:
		var dir := away.normalized() if away.length() > 0.5 else Vector2.RIGHT
		p2 = world.random_land_point(_rng, world.spawn_point + dir * (SPAWN_CLEARANCE + 20.0), 12.0)
	var scene: PackedScene = load(SCENES[kind])
	var pred: Predator = scene.instantiate()
	pred.world = world
	pred.player = player
	pred.day_night = day_night
	pred.manager = self
	pred.position = Vector3(p2.x, world.height_at(p2.x, p2.y) + 0.2, p2.y)
	if pred is Hyena:
		(pred as Hyena).pack_id = pack
	add_child(pred)
	pred.reset_physics_interpolation()
	predators.append(pred)
	return pred


func spawn_pack(where: Vector2, count: int) -> Array[Predator]:
	var out: Array[Predator] = []
	var id := _next_pack
	_next_pack += 1
	for i in count:
		out.append(spawn("hyena", where + Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8)), id))
	return out


func despawn(pred: Predator) -> void:
	predators.erase(pred)
	pred.queue_free()


## Night brings an extra hyena pack in from the hills; it slinks away again after dawn.
func _on_phase_changed(phase: StringName) -> void:
	if phase == &"night" and _night_pack.is_empty():
		var p := Vector2(player.global_position.x, player.global_position.z)
		var where := p
		for attempt in 30:
			var ang := _rng.randf() * TAU
			var cand := p + Vector2(cos(ang), sin(ang)) * _rng.randf_range(130.0, 190.0)
			if world.is_walkable(cand.x, cand.y) and not world.in_safe_zone(cand, 10.0):
				where = cand
				break
		if where != p:
			_night_pack = spawn_pack(where, 3)
			GameState.notify("Night falls", "The jungle wakes. Predators are bolder in the dark.")


## By day the night pack slinks away as soon as it is out of sight and not hunting.
func _dismiss_night_pack() -> void:
	for pred in _night_pack:
		if predators.has(pred) and pred.threat_level() < GameState.Threat.STALKED \
				and pred.global_position.distance_to(player.global_position) > 80.0:
			despawn(pred)
	_night_pack = _night_pack.filter(func(p: Predator) -> bool: return predators.has(p))


func night_pack_size() -> int:
	return _night_pack.size()


func alert_allies(source: Predator, pos: Vector3, level: float, radius: float, only_species := "") -> void:
	for p in predators:
		if p == source or p.species != source.species:
			continue
		if only_species != "" and p.species != only_species:
			continue
		if p.global_position.distance_to(source.global_position) < radius:
			p.alert(pos, level)


func pack_mate(h: Predator) -> Predator:
	if not (h is Hyena):
		return null
	for p in predators:
		if p != h and p is Hyena and (p as Hyena).pack_id == (h as Hyena).pack_id:
			return p
	return null


func allies_engaged(source: Predator, radius: float) -> int:
	var n := 0
	for p in predators:
		if p != source and p.species == source.species and (p.state == Predator.State.CHASE or p.state == Predator.State.ATTACK) \
				and p.global_position.distance_to(source.global_position) < radius:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.2
	if not _night_pack.is_empty() and day_night.phase == &"day":
		_dismiss_night_pack()
	var level := GameState.Threat.CALM
	max_awareness = 0.0
	nearest_hunter = null
	var best := INF
	for p in predators:
		var t := p.threat_level()
		level = maxi(level, t)
		if p.species != "tiger" or t >= GameState.Threat.STALKED:
			max_awareness = maxf(max_awareness, p.awareness)
		if t == GameState.Threat.HUNTED and p.player_distance < best:
			best = p.player_distance
			nearest_hunter = p
	if player != null and player.is_dead():
		level = GameState.Threat.CALM
	GameState.set_threat(level)


func nearest(kind := "") -> Predator:
	var best: Predator = null
	var bd := INF
	for p in predators:
		if kind != "" and p.species != kind:
			continue
		if p.player_distance < bd:
			bd = p.player_distance
			best = p
	return best
