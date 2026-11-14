class_name PreyManager
extends Node3D
## Spawns the herds of prey animals, keeps their numbers up after kills and lets herd mates warn
## each other. Predators ask it for something to hunt.

signal prey_killed(prey: Prey, by: Node3D)

var world: WorldData
var player: Player
var predators: PredatorManager
var animals: Array[Prey] = []
var kills := 0
var _rng := RandomNumberGenerator.new()
var _next_herd := 1


func setup(p_world: WorldData, p_player: Player, p_predators: PredatorManager) -> void:
	world = p_world
	player = p_player
	predators = p_predators
	predators.prey = self
	_rng.seed = world.seed_value + 311


func spawn_default_roster() -> void:
	# gazelle herds graze the clearings and their edges
	var n := world.clearings.size()
	for i in mini(n, 6):
		var c: Vector2 = world.clearings[i]["center"]
		var ang := _rng.randf() * TAU
		spawn_herd("gazelle", c + Vector2(cos(ang), sin(ang)) * _rng.randf_range(18.0, 34.0), 3)
	for i in range(6, n):
		var c2: Vector2 = world.clearings[i]["center"]
		spawn_herd("gazelle", c2 + Vector2(_rng.randf_range(-20.0, 20.0), _rng.randf_range(-20.0, 20.0)), 3)
	# one herd grazes within sight of where the deer starts, so the jungle feels alive at once
	var ang0 := _rng.randf() * TAU
	spawn_herd("gazelle", world.spawn_point + Vector2(cos(ang0), sin(ang0)) * 38.0, 4, 10.0)
	spawn_herd("boar", world.spawn_point - Vector2(cos(ang0), sin(ang0)) * 55.0, 2, 12.0)
	# boar root about in the forest
	for c: Vector2 in [Vector2(-150.0, 60.0), Vector2(90.0, -120.0), Vector2(170.0, 60.0), Vector2(-60.0, 190.0), Vector2(20.0, 40.0)]:
		spawn_herd("boar", c, 2)


func spawn_herd(kind: String, where: Vector2, count: int, scatter := 30.0) -> Array[Prey]:
	var out: Array[Prey] = []
	var id := _next_herd
	_next_herd += 1
	var center := world.random_land_point(_rng, where, scatter)
	for i in count:
		out.append(spawn(kind, world.random_land_point(_rng, center, 7.0), id))
	return out


func spawn(kind: String, p2: Vector2, herd := 0) -> Prey:
	var a := Prey.new()
	a.kind = kind
	a.name = "%s%d" % [kind.capitalize(), animals.size()]
	a.world = world
	a.player = player
	a.manager = self
	a.herd_id = herd
	a.position = Vector3(p2.x, world.height_at(p2.x, p2.y) + 0.1, p2.y)
	add_child(a)
	a.reset_physics_interpolation()
	animals.append(a)
	return a


func clear() -> void:
	for a in animals:
		a.queue_free()
	animals.clear()
	kills = 0


## Everything a prey animal should be afraid of right now.
func threats() -> Array:
	return predators.predators if predators != null else []


func alarm_herd(source: Prey, pos: Vector3) -> void:
	for a in animals:
		if a != source and a.herd_id == source.herd_id and a.alive() and not a.is_fleeing() \
				and a.global_position.distance_to(source.global_position) < 30.0:
			a._threat_pos = pos
			a._calm = _rng.randf_range(5.0, 8.0)
			a._enter(Prey.State.FLEE)


## Nearest living animal a predator at `from` could go for.
func nearest_prey(from: Vector3, max_dist: float) -> Prey:
	var best: Prey = null
	var bd := max_dist
	for a in animals:
		if not a.alive() or (a.hunter != null and is_instance_valid(a.hunter)):
			continue
		var d := a.global_position.distance_to(from)
		if d < bd and not world.in_safe_zone(a.pos2(), 1.5):
			bd = d
			best = a
	return best


func on_killed(prey: Prey, by: Node3D) -> void:
	kills += 1
	prey_killed.emit(prey, by)
	if player != null and by != null and prey.global_position.distance_to(player.global_position) < 70.0:
		var hunter_name: String = str(by.get("display_name")) if by.get("display_name") != null else "predator"
		GameState.notify("A kill nearby", "A %s brought down a %s. It will be busy for a while." % [hunter_name.to_lower(), prey.display_name.to_lower()])


## A carcass has been lying long enough: the animal re-enters the world far from the deer.
func recycle(prey: Prey) -> void:
	var p := Vector2(player.global_position.x, player.global_position.z) if player != null else Vector2.ZERO
	for attempt in 30:
		var ang := _rng.randf() * TAU
		var cand := p + Vector2(cos(ang), sin(ang)) * _rng.randf_range(110.0, 220.0)
		if world.in_bounds(cand.x, cand.y, 30.0) and world.is_walkable(cand.x, cand.y) and not world.in_safe_zone(cand, 6.0):
			prey.respawn_at(cand)
			return
	prey.respawn_at(prey.home)


func living() -> int:
	var n := 0
	for a in animals:
		if a.alive():
			n += 1
	return n
