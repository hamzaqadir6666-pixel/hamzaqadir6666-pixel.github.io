extends Node
## Automated gameplay test. Runs the real main scene and drives it with simulated input.
##   godot --headless --fixed-fps 60 res://scenes/tests/test_runner.tscn
## Exit code 0 = all checks passed.

var main: Node
var world: GameWorld
var player: Player
var passed := 0
var failed := 0
var failures: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var t0 := Time.get_ticks_msec()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	while main.get("world") == null or not main.world.built or main.flow == 0:
		await get_tree().process_frame
	world = main.world
	player = world.player
	print("[info] world built in %.1f s (wall clock)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _run()
	print("\n==== %d passed, %d failed ====" % [passed, failed])
	for f in failures:
		print("  FAILED: ", f)
	get_tree().quit(1 if failed > 0 else 0)


func check(cond: bool, what: String, detail: Variant = "") -> void:
	if cond:
		passed += 1
		print("  ok   ", what, "  ", detail)
	else:
		failed += 1
		failures.append("%s  %s" % [what, str(detail)])
		print("  FAIL ", what, "  ", detail)


func wait(seconds: float) -> void:
	var frames := int(seconds * 60.0)
	for i in frames:
		await get_tree().physics_frame


func release_all() -> void:
	for a: String in Settings.ACTIONS:
		Input.action_release(a)


func teleport(x: float, z: float, facing := 0.0) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(x, world.data.height_at(x, z) + 0.2, z)
	player._speed = 0.0
	player._heading = facing
	player._last_pos = player.global_position
	player.reset_physics_interpolation()


func place(pred: Predator, x: float, z: float) -> void:
	pred.global_position = Vector3(x, world.data.height_at(x, z) + 0.2, z)
	pred.velocity = Vector3.ZERO
	pred._speed = 0.0
	pred.home = Vector2(x, z)
	pred.awareness = 0.0
	pred.stamina = 1.0
	pred.tired = false
	pred._attack_cd = 0.0
	pred.stop_moving()
	pred.set_state(Predator.State.PATROL)
	pred.reset_physics_interpolation()


## Move every predator far away and put them to sleep so they do not disturb a test.
func isolate(keep: Predator = null) -> void:
	var i := 0
	for p in world.predators.predators:
		if p == keep:
			continue
		p.global_position = Vector3(-440.0 + i * 6.0, 60.0, -440.0)
		p.awareness = 0.0
		p.set_state(Predator.State.REST)
		p.process_mode = Node.PROCESS_MODE_DISABLED
		i += 1
	if keep != null:
		keep.process_mode = Node.PROCESS_MODE_INHERIT


func restore_stats() -> void:
	if player.is_dead():
		failed += 1
		failures.append("deer died unexpectedly during the tests (%s)" % GameState.cause_of_death)
		print("  FAIL deer died unexpectedly: ", GameState.cause_of_death)
	player.health = player.max_health
	player.stamina = player.max_stamina
	player.hunger = 100.0
	player.thirst = 100.0
	player.exhausted = false


## A flat, open, dry spot (found by scanning a clearing).
func open_spot(index := 1) -> Vector2:
	var c: Vector2 = world.data.clearings[index]["center"]
	return c


## Unscripted play: a naive bot wanders for several in-game minutes (set WS_SOAK=<minutes>).
func soak(minutes: float) -> void:
	print("\n-- soak (%.0f min of unscripted play)" % minutes)
	main.menus.start_requested.emit()
	await wait(0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hist := {}
	var deaths: Array = []
	var hits := 0
	var hp := player.health
	var hunted_time := 0.0
	for sec in int(minutes * 60.0):
		if sec % 4 == 0:
			release_all()
			world.camera.rotation.y += rng.randf_range(-0.9, 0.9)
			Input.action_press("move_forward")
			# the bot flees when hunted, otherwise trots and sometimes stops to feed
			if GameState.threat == GameState.Threat.HUNTED:
				Input.action_press("sprint")
			elif rng.randf() < 0.2:
				Input.action_release("move_forward")
				Input.action_press("interact")
		await wait(1.0)
		if GameState.threat == GameState.Threat.HUNTED:
			hunted_time += 1.0
		if player.health < hp - 5.0:
			hits += 1
		hp = player.health
		for p in world.predators.predators:
			var key := p.species + ":" + p.state_name()
			hist[key] = int(hist.get(key, 0)) + 1
		if main.flow == 4:
			deaths.append("%s at %s (day %d %s)" % [GameState.cause_of_death, GameState.format_time(GameState.time_survived), world.day_night.day, world.day_night.clock_text()])
			main.menus.restart_requested.emit()
			await wait(0.5)
			hp = player.health
	release_all()
	print("  [info] predator state seconds: ", hist)
	print("  [info] bot deaths: ", deaths)
	print("  [info] hits taken %d, seconds hunted %.0f, escapes %d, clock day %d %s" % [hits, hunted_time, GameState.escapes, world.day_night.day, world.day_night.clock_text()])
	check(true, "soak finished without stalling")


func _run() -> void:
	if OS.get_environment("WS_SOAK") != "":
		await soak(float(OS.get_environment("WS_SOAK")))
		return
	await test_load()
	await test_menu_flow()
	await test_movement()
	await test_collisions()
	await test_survival()
	await test_stealth()
	await test_lion()
	await test_tiger()
	await test_cheetah()
	await test_hyena()
	await test_escape_and_search()
	await test_day_night()
	await test_audio()
	await test_pause_settings()
	await test_death_and_restart()


func test_load() -> void:
	print("\n-- world")
	var d := world.data
	check(d.height.size() == WorldData.N * WorldData.N, "height field generated")
	var hmin := INF
	var hmax := -INF
	var wet := 0
	for h in d.height:
		hmin = minf(hmin, h)
		hmax = maxf(hmax, h)
		if h < 0.0:
			wet += 1
	check(hmin < -1.5 and hmax > 40.0, "terrain has water beds and mountains", "min %.1f max %.1f" % [hmin, hmax])
	check(wet > 3000, "rivers and lakes exist", "%d wet cells (%.1f%%)" % [wet, wet * 100.0 / d.height.size()])
	print("  [info] vegetation counts: ", world.vegetation.counts)
	var trees := int(world.vegetation.counts.get("trees", 0)) + int(world.vegetation.counts.get("palms", 0)) + int(world.vegetation.counts.get("dead", 0))
	check(trees > 800, "hundreds of trees placed", trees)
	check(int(world.vegetation.counts.get("bushes", 0)) > 500, "bushes placed", world.vegetation.counts.get("bushes", 0))
	check(int(world.vegetation.counts.get("rocks", 0)) > 50, "rocks placed", world.vegetation.counts.get("rocks", 0))
	check(world.vegetation.food_sites.size() > 60, "food plants placed", world.vegetation.food_sites.size())
	check(world.flora.entries.size() >= 80, "all flora models loaded", world.flora.entries.size())
	check(world.vegetation._bodies.size() > 100, "static collision bodies", world.vegetation._bodies.size())
	check(d.is_walkable(d.spawn_point.x, d.spawn_point.y), "spawn point is walkable")
	for g in d.groves:
		var c: Vector2 = g["center"]
		check(d.height_at(c.x, c.y) > 0.5 and d.slope_at(c.x, c.y) < 0.3, "grove on dry flat land: " + g["name"],
			"h %.1f slope %.2f" % [d.height_at(c.x, c.y), d.slope_at(c.x, c.y)])
	for p in d.pois:
		if p["type"] != "lake":
			var c: Vector2 = p["pos"]
			check(d.height_at(c.x, c.y) > 0.4 and d.slope_at(c.x, c.y) < 0.35, "POI reachable: " + p["name"],
				"h %.1f slope %.2f" % [d.height_at(c.x, c.y), d.slope_at(c.x, c.y)])
	for cl in d.clearings:
		var c: Vector2 = cl["center"]
		check(d.is_walkable(c.x, c.y), "clearing walkable at %s" % c, "h %.1f" % d.height_at(c.x, c.y))
	await wait(1.0)
	check(world.grass.active_cells() > 10, "grass streamed around player", world.grass.active_cells())


func test_menu_flow() -> void:
	print("\n-- menu flow")
	check(main.flow == 1 and main.menus.current_screen() == "main", "main menu shown after loading")
	check(not player.control_enabled, "player frozen in menu")
	main.menus.start_requested.emit()
	await wait(0.2)
	check(main.flow == 2 and main.hud.visible and GameState.in_game, "start button begins the game")
	check(world.predators.predators.size() == 13, "predator roster spawned", world.predators.predators.size())
	var kinds := {}
	for p in world.predators.predators:
		kinds[p.species] = int(kinds.get(p.species, 0)) + 1
		check(p.rig.anim != null and p.rig.has("Walk") and p.rig.has("Run") and p.rig.has("Attack") and p.rig.has("Idle"),
			"%s has animations" % p.species)
	print("  [info] roster: ", kinds)
	var nearest := world.predators.nearest()
	check(nearest.player_distance > 80.0 or nearest.global_position.distance_to(player.global_position) > 80.0,
		"no predator near the spawn", "%.0f m" % nearest.global_position.distance_to(player.global_position))


func test_movement() -> void:
	print("\n-- movement")
	isolate()
	var s := open_spot()
	teleport(s.x, s.y)
	await wait(0.5)
	check(player.is_on_floor(), "deer stands on the terrain", "y %.2f ground %.2f" % [player.global_position.y, world.data.height_at(s.x, s.y)])
	var start := player.global_position
	Input.action_press("move_forward")
	await wait(2.0)
	var trot := player.horizontal_speed()
	check(absf(trot - Player.TROT_SPEED) < 0.6, "trot speed", "%.2f m/s" % trot)
	check(player.rig.current == "Run" or player.rig.current == "Walk", "locomotion animation plays", player.rig.current)
	check(player.global_position.distance_to(start) > 7.0, "deer moved forward", "%.1f m" % player.global_position.distance_to(start))
	Input.action_press("sprint")
	var st0 := player.stamina
	await wait(2.0)
	check(player.horizontal_speed() > 10.5, "sprint speed", "%.2f m/s" % player.horizontal_speed())
	check(player.stamina < st0 - 10.0, "sprinting drains stamina", "%.0f -> %.0f" % [st0, player.stamina])
	check(player.noise_radius > 20.0, "sprinting is loud", player.noise_radius)
	Input.action_release("sprint")
	Input.action_press("sneak")
	await wait(1.5)
	check(absf(player.horizontal_speed() - Player.SNEAK_SPEED) < 0.5, "sneak speed", "%.2f m/s" % player.horizontal_speed())
	check(player.noise_radius < 5.0, "sneaking is quiet", player.noise_radius)
	Input.action_release("sneak")
	await wait(1.0)
	Input.action_release("move_forward")
	await wait(0.1)
	check(player.horizontal_speed() > 0.5, "smooth deceleration (still coasting after 0.1 s)", "%.2f" % player.horizontal_speed())
	await wait(1.0)
	check(player.horizontal_speed() < 0.05, "deer stops", "%.2f" % player.horizontal_speed())
	check(player.rig.current.begins_with("Idle"), "idle animation", player.rig.current)
	player.stamina = 40.0
	var st1 := player.stamina
	await wait(3.0)
	check(player.stamina > st1 + 10.0, "stamina regenerates at rest", "%.0f -> %.0f" % [st1, player.stamina])
	# turning
	var h0 := player._heading
	Input.action_press("move_right")
	await wait(0.1)
	var partial := absf(angle_difference(h0, player._heading))
	await wait(0.9)
	var full := absf(angle_difference(h0, player._heading))
	check(partial > 0.05 and partial < 1.4 and full > 1.4, "turns smoothly toward input", "%.2f rad after 0.1 s, %.2f after 1 s" % [partial, full])
	Input.action_release("move_right")
	await wait(0.6)
	# jump
	var y0 := player.global_position.y
	Input.action_press("jump")
	await wait(0.05)
	Input.action_release("jump")
	var peak := y0
	for i in 40:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	check(peak - y0 > 0.9, "jump", "apex +%.2f m" % (peak - y0))
	await wait(1.0)
	check(player.is_on_floor(), "lands again")
	# exhaustion
	player.stamina = 3.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(1.5)
	check(player.exhausted and player.horizontal_speed() < 5.0, "exhaustion slows the deer", "%.2f m/s" % player.horizontal_speed())
	release_all()
	restore_stats()
	await wait(0.5)


func test_collisions() -> void:
	print("\n-- collisions")
	var d := world.data
	# elder banyan trunk
	var e: Vector2 = d.pois[3]["pos"]
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(e.x - 12.0, d.height_at(e.x, e.y) + 1.5, e.y), Vector3(e.x, d.height_at(e.x, e.y) + 1.5, e.y), 2)
	var hit := space.intersect_ray(q)
	check(not hit.is_empty(), "tree trunks have colliders")
	teleport(e.x - 8.0, e.y, -PI * 0.5)
	await wait(0.3)
	world.camera.rotation.y = -PI * 0.5
	Input.action_press("move_forward")
	await wait(3.0)
	Input.action_release("move_forward")
	var dist := Vector2(player.global_position.x, player.global_position.z).distance_to(e)
	check(dist > 2.5, "deer cannot run through the giant trunk", "stopped %.1f m from centre" % dist)
	world.camera.rotation.y = 0.0
	# terrain: walk downhill into the river and swim
	var rp := d.river_points[int(d.river_points.size() / 2)]
	var found := false
	for i in range(8, d.river_points.size() - 8):
		var c := d.river_points[i]
		if d.height_at(c.x, c.y) < -1.5:
			rp = c
			found = true
			break
	check(found, "river has deep sections", d.height_at(rp.x, rp.y))
	teleport(rp.x, rp.y)
	await wait(1.5)
	check(player.swimming, "deer swims in deep water", "y %.2f" % player.global_position.y)
	check(player.global_position.y > -1.3 and player.global_position.y < -0.6, "floats at the surface", player.global_position.y)
	# camera collision
	var s := open_spot()
	teleport(s.x, s.y)
	await wait(0.5)
	check(world.camera.camera.global_position.y > d.height_at(world.camera.camera.global_position.x, world.camera.camera.global_position.z),
		"camera stays above ground")
	check(absf(world.camera.camera.global_position.distance_to(player.global_position + Vector3(0, 1.35, 0)) - 5.5) < 1.0, "camera at follow distance",
		world.camera.camera.global_position.distance_to(player.global_position))


func test_survival() -> void:
	print("\n-- survival")
	isolate()
	restore_stats()
	var s := open_spot()
	teleport(s.x, s.y)
	var h0 := player.hunger
	var t0 := player.thirst
	await wait(10.0)
	check(player.hunger < h0 and player.thirst < t0, "hunger and thirst decay", "food %.2f water %.2f after 10 s" % [player.hunger, player.thirst])
	# eating at a food plant
	var orchard: Vector2 = world.data.pois[6]["pos"]
	var site: Dictionary = world.vegetation.nearest_food(Vector3(orchard.x, world.data.height_at(orchard.x, orchard.y), orchard.y), 30.0)
	check(not site.is_empty(), "orchard has food plants")
	var fp: Vector3 = site["pos"]
	teleport(fp.x + 1.2, fp.z)
	player.hunger = 30.0
	await wait(0.5)
	check(player.interaction_hint().contains("eat"), "food prompt appears", player.interaction_hint())
	Input.action_press("interact")
	await wait(3.0)
	check(player.hunger > 50.0, "eating restores hunger", "30 -> %.0f" % player.hunger)
	check(player.rig.current == "Eat", "eat animation", player.rig.current)
	check(float(site["amount"]) < 100.0, "food plant is depleted", site["amount"])
	Input.action_release("interact")
	# grazing
	teleport(s.x + 6.0, s.y + 3.0)
	player.hunger = 20.0
	await wait(0.5)
	if world.data.surface_at(player.global_position.x, player.global_position.z) == &"grass":
		Input.action_press("interact")
		await wait(3.0)
		Input.action_release("interact")
		check(player.hunger > 25.0, "grazing on grass slowly restores hunger", "20 -> %.1f" % player.hunger)
	# drinking: find a shore point
	var d := world.data
	var shore := Vector2.ZERO
	var lake: Dictionary = d.lakes[0]
	var c: Vector2 = lake["center"]
	for i in 400:
		var p := c + Vector2(1, 0) * (20.0 + i * 0.25)
		var h := d.height_at(p.x, p.y)
		if h > -0.3 and h < -0.05:
			shore = p
			break
	check(shore != Vector2.ZERO, "lake shore found", shore)
	teleport(shore.x, shore.y)
	player.thirst = 20.0
	await wait(0.6)
	check(player.can_drink() and player.interaction_hint().contains("drink"), "drink prompt at the water's edge", player.interaction_hint())
	Input.action_press("interact")
	await wait(3.0)
	Input.action_release("interact")
	check(player.thirst > 55.0, "drinking restores thirst", "20 -> %.0f" % player.thirst)
	# starvation damage
	teleport(s.x, s.y)
	restore_stats()
	player.hunger = 0.0
	await wait(4.0)
	check(player.health < player.max_health - 3.0, "starvation drains health", player.health)
	restore_stats()
	player.health = 50.0
	player._since_damage = 99.0
	await wait(5.0)
	check(player.health > 52.0, "health regenerates when fed and watered", player.health)
	# discoveries
	var before := GameState.discoveries.size()
	var salt: Vector2 = d.pois[0]["pos"]
	var ms := player.max_stamina
	teleport(salt.x, salt.y)
	await wait(1.0)
	check(GameState.discoveries.size() == before + 1 and player.max_stamina > ms, "discovering a salt lick grants a reward",
		"max stamina %.0f -> %.0f" % [ms, player.max_stamina])
	var g: Dictionary = d.groves[0]
	teleport(g["center"].x, g["center"].y)
	await wait(1.0)
	check(player.in_grove and GameState.discoveries.has(g["id"]), "safe thicket discovered")
	restore_stats()


func test_stealth() -> void:
	print("\n-- stealth")
	var d := world.data
	# find a bush
	var spot := Vector2.ZERO
	for key: Vector2i in d._cover_cells:
		for c: Vector4 in d._cover_cells[key]:
			if c.w > 0.9 and c.z < 4.0 and not d.in_safe_zone(Vector2(c.x, c.y), 6.0) and absf(c.x) < 300.0 and absf(c.y) < 300.0 and d.slope_at(c.x, c.y) < 0.1 and d.is_walkable(c.x, c.y + 14.0) and d.forest_at(c.x, c.y + 7.0) < 0.3:
				spot = Vector2(c.x, c.y)
				break
		if spot != Vector2.ZERO:
			break
	check(spot != Vector2.ZERO, "found a tall bush", spot)
	teleport(spot.x, spot.y)
	await wait(0.6)
	check(player.cover > 0.8 and player.visibility < 0.1 and player.is_hidden(), "standing in a bush hides the deer",
		"cover %.2f visibility %.2f" % [player.cover, player.visibility])
	var s := open_spot()
	teleport(s.x, s.y)
	await wait(0.4)
	var still := player.visibility
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(1.0)
	check(player.visibility > still and player.visibility > 0.9, "running in the open is far more visible", "%.2f vs %.2f" % [player.visibility, still])
	release_all()
	await wait(1.0)
	# a lion looking straight at a hidden deer 14 m away should not detect it
	var lion := _first("lion")
	isolate(lion)
	teleport(spot.x, spot.y)
	place(lion, spot.x, spot.y + 14.0)
	lion._heading = atan2(-(spot.x - lion.global_position.x), -(spot.y - lion.global_position.z))
	lion.set_state(Predator.State.REST)
	lion._wait = 999.0
	await wait(4.0)
	check(lion.state != Predator.State.CHASE and lion.awareness < 1.0, "hidden deer is not detected at 14 m",
		"awareness %.2f state %s" % [lion.awareness, lion.state_name()])


func _first(kind: String) -> Predator:
	for p in world.predators.predators:
		if p.species == kind:
			return p
	return null


## Player stands still and exposed in a clearing; predator starts `dist` metres away facing it.
func _setup_encounter(pred: Predator, dist: float, clearing := 1, resting := false) -> void:
	isolate(pred)
	restore_stats()
	var s := open_spot(clearing)
	teleport(s.x, s.y)
	place(pred, s.x, s.y + dist)
	pred._heading = 0.0   # facing -Z, toward the player
	pred.rotation.y = 0.0
	if resting:
		# lying up, looking toward the deer (a resting animal is less alert)
		pred.set_state(Predator.State.REST)
		pred._wait = 999.0
	await wait(0.1)


func test_lion() -> void:
	print("\n-- lion")
	var lion := _first("lion") as Lion
	check(lion._circuit.size() == 5, "lion has a patrol circuit", lion._circuit.size())
	# patrol behaviour (night: patrols actively)
	isolate(lion)
	teleport(open_spot(0).x, open_spot(0).y + 10.0)
	var c := open_spot(1)
	world.day_night.set_time(23.0)
	world.day_night.paused = true
	await wait(0.5)
	isolate(lion)   # the night pack that just arrived must not interfere
	place(lion, c.x, c.y)
	lion._on_spawned()
	var seen := {}
	var p0 := lion.global_position
	var travelled := 0.0
	for i in 90:
		await wait(1.0)
		seen[lion.state_name()] = true
		travelled += lion.global_position.distance_to(p0)
		p0 = lion.global_position
	check(seen.has("PATROL") and travelled > 25.0, "lion patrols its territory", "states %s, walked %.0f m (dormant sim)" % [seen.keys(), travelled])
	check(lion.pos2().distance_to(c) < lion.territory_radius * 1.3, "lion stays inside its territory", "%.0f m from home" % lion.pos2().distance_to(c))
	world.day_night.set_time(12.0)
	await _setup_encounter(lion, 20.0, 1, true)
	world.camera.rotation.y = 0.0
	Input.action_press("move_right")   # the deer trots across the resting lion's view
	var states := {}
	var hp := player.health
	var max_speed := 0.0
	var t_detect := -1.0
	var t_hit := -1.0
	for i in 600:
		await get_tree().physics_frame
		states[lion.state_name()] = true
		max_speed = maxf(max_speed, lion._speed)
		if t_detect < 0.0 and lion.state == Predator.State.CHASE:
			t_detect = i / 60.0
		if t_hit < 0.0 and player.health < hp:
			t_hit = i / 60.0
			break
	release_all()
	check(t_detect >= 0.0, "lion detects an exposed deer", "after %.1f s" % t_detect)
	check(GameState.threat == GameState.Threat.HUNTED, "threat level raised to HUNTED")
	check(max_speed > 9.0, "lion charges", "top speed %.1f m/s" % max_speed)
	check(t_hit > 0.0 and states.has("ATTACK"), "lion attack lands", "hit after %.1f s, damage %.0f" % [t_hit, hp - player.health])
	check(absf((hp - player.health) - lion.attack_damage) < 0.5, "lion deals its damage", hp - player.health)
	# fairness: a fresh deer that runs immediately should get away from the charge
	await _setup_encounter(lion, 22.0, 1, true)
	world.camera.rotation.y = 0.0
	lion.awareness = 1.0
	lion.last_known = player.global_position
	lion._on_detected()   # the lion roars and charges; the deer bolts at the same moment
	var charged := false
	var escaped := true
	var min_gap := 999.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	hp = player.health
	for i in 60 * 16:
		await get_tree().physics_frame
		min_gap = minf(min_gap, lion.global_position.distance_to(player.global_position))
		if lion._speed > 9.0:
			charged = true
		if player.health < hp:
			escaped = false
			break
		if lion.state == Predator.State.SEARCH or lion.state == Predator.State.RETURN:
			break
	release_all()
	check(charged, "lion commits to the charge")
	check(escaped, "a fresh sprinting deer can outrun a lion's charge from 22 m", "closest %.1f m, lion ends %s" % [min_gap, lion.state_name()])
	check(lion.tired or lion.state != Predator.State.CHASE, "lion tires / gives up", "stamina %.2f state %s" % [lion.stamina, lion.state_name()])
	world.day_night.paused = false


func test_tiger() -> void:
	print("\n-- tiger")
	var tiger := _first("tiger") as Tiger
	check(world.data.cover_at(tiger._ambush_spot.x, tiger._ambush_spot.z) > 0.45, "tiger picks an ambush site in cover",
		"cover %.2f" % world.data.cover_at(tiger._ambush_spot.x, tiger._ambush_spot.z))
	world.day_night.set_time(12.0)
	world.day_night.paused = true
	# deer facing AWAY from the tiger (heading 0 = facing -Z, tiger at +Z = behind)
	await _setup_encounter(tiger, 24.0)
	var seen := {}
	var crept := false
	var d0 := tiger.global_position.distance_to(player.global_position)
	var pounced := false
	var hp := player.health
	var hit := false
	var max_stalk_speed := 0.0
	for i in 60 * 40:
		await get_tree().physics_frame
		seen[tiger.state_name()] = true
		if tiger.state == Predator.State.STALK:
			max_stalk_speed = maxf(max_stalk_speed, tiger._speed)
			if tiger.global_position.distance_to(player.global_position) < d0 - 5.0:
				crept = true
		if tiger._pouncing > 0.0:
			pounced = true
		if player.health < hp:
			hit = true
			break
	check(seen.has("STALK"), "tiger stalks instead of charging", seen.keys())
	check(crept and max_stalk_speed < 5.0, "tiger creeps closer slowly", "max stalk speed %.1f m/s" % max_stalk_speed)
	check(pounced, "tiger pounces at close range")
	check(hit and hp - player.health > tiger.attack_damage, "pounce hits hard", "damage %.0f" % (hp - player.health))
	# deer watching the tiger: it should freeze
	await _setup_encounter(tiger, 26.0)
	player.face(Vector3(0, 0, 1))   # look toward +Z, at the tiger
	tiger.awareness = 1.0
	tiger.last_known = player.global_position
	tiger.time_since_contact = 0.0
	tiger.set_state(Predator.State.STALK)
	await wait(0.5)
	var a := tiger.global_position
	await wait(3.0)
	check(tiger._frozen and tiger.global_position.distance_to(a) < 0.6, "tiger freezes while the deer is watching it",
		"moved %.2f m" % tiger.global_position.distance_to(a))
	check(GameState.threat == GameState.Threat.STALKED, "HUD threat shows 'stalked'", GameState.threat)
	check(tiger.can_swim, "tiger can swim")
	world.day_night.paused = false


func test_cheetah() -> void:
	print("\n-- cheetah")
	var cheetah := _first("cheetah") as Cheetah
	world.day_night.set_time(12.0)
	world.day_night.paused = true
	await _setup_encounter(cheetah, 45.0, 1)
	var top := 0.0
	var t_chase := -1.0
	var speed_at_1s := 0.0
	var hp := player.health
	var hit := false
	for i in 60 * 14:
		await get_tree().physics_frame
		top = maxf(top, cheetah._speed)
		if t_chase < 0.0 and cheetah.state == Predator.State.CHASE:
			t_chase = i / 60.0
		if t_chase >= 0.0 and absf(i / 60.0 - t_chase - 1.0) < 0.01:
			speed_at_1s = cheetah._speed
		if player.health < hp:
			hit = true
			break
	check(t_chase >= 0.0, "cheetah spots the deer from 45 m", "after %.1f s" % t_chase)
	check(top > 14.0, "cheetah reaches very high speed", "top %.1f m/s" % top)
	check(speed_at_1s < top * 0.75, "cheetah has to accelerate", "%.1f m/s after 1 s, top %.1f" % [speed_at_1s, top])
	check(hit, "cheetah catches a standing deer")
	# burn-out: deer flees; cheetah must exhaust itself and rest
	await _setup_encounter(cheetah, 38.0, 1)
	world.camera.rotation.y = 0.0
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var rested := false
	for i in 60 * 25:
		await get_tree().physics_frame
		restore_stats()
		if cheetah.state == Predator.State.REST and cheetah._exhausted_until > 0.0:
			rested = true
			break
	release_all()
	check(rested, "cheetah burns out and collapses to rest", "stamina %.2f state %s" % [cheetah.stamina, cheetah.state_name()])
	var aw := cheetah.awareness
	await wait(2.0)
	check(cheetah.state == Predator.State.REST, "exhausted cheetah ignores prey for a while", cheetah.state_name())
	# agility penalty
	cheetah._speed = 18.0
	var fast_turn := cheetah.turn_rate / (1.0 + 18.0 * cheetah.turn_speed_penalty)
	check(fast_turn < 1.0, "cheetah corners badly at top speed", "%.2f rad/s" % fast_turn)
	cheetah._speed = 0.0
	world.day_night.paused = false


func test_hyena() -> void:
	print("\n-- hyena")
	var hyena := _first("hyena") as Hyena
	var mate := world.predators.pack_mate(hyena)
	check(mate != null, "hyenas come in packs")
	world.day_night.set_time(12.0)
	world.day_night.paused = true
	await _setup_encounter(hyena, 12.0, 1, true)
	mate.process_mode = Node.PROCESS_MODE_INHERIT
	place(mate, hyena.global_position.x + 30.0, hyena.global_position.z + 10.0)
	mate._heading = PI  # looking away
	var tactics := {}
	var bites := 0
	var hp := player.health
	var mate_joined := false
	for i in 60 * 70:
		await get_tree().physics_frame
		if hyena.state == Predator.State.CHASE:
			tactics[hyena.tactic_name()] = true
		if mate.state == Predator.State.CHASE:
			mate_joined = true
		if player.health < hp:
			bites += 1
			restore_stats()
			hp = player.health
		if i % 30 == 0:
			restore_stats()
			hp = player.health
	check(tactics.size() >= 3, "hyena switches between several tactics", tactics.keys())
	check(mate_joined, "pack mate answers the call")
	check(bites >= 1, "hyena lands bites", bites)
	# roaming
	isolate(hyena)
	teleport(open_spot(0).x, open_spot(0).y + 10.0)
	var c := open_spot(5)
	place(hyena, c.x, c.y)
	var start := hyena.global_position
	var far := 0.0
	for i in 120:
		await wait(1.0)
		far = maxf(far, hyena.global_position.distance_to(start))
	check(far > 40.0, "hyena roams widely with no fixed territory", "ranged %.0f m in 2 min" % far)
	world.day_night.paused = false


func test_escape_and_search() -> void:
	print("\n-- escape, search, return")
	var lion := _first("lion")
	world.day_night.set_time(12.0)
	world.day_night.paused = true
	await _setup_encounter(lion, 16.0, 1, true)
	for i in 60 * 8:
		await get_tree().physics_frame
		if lion.state == Predator.State.CHASE:
			break
	check(lion.state == Predator.State.CHASE, "lion is chasing")
	var escapes := GameState.escapes
	# vanish into a safe thicket
	var g: Dictionary = world.data.groves[1]
	var home := lion.home
	teleport(g["center"].x, g["center"].y)
	place_keep_state(lion, g["center"].x + 22.0, g["center"].y)
	lion.home = Vector2(g["center"].x + 40.0, g["center"].y)
	lion.last_known = Vector3(g["center"].x + 14.0, 0.0, g["center"].y)
	var seen := {}
	var min_d := 999.0
	for i in 60 * 60:
		await get_tree().physics_frame
		seen[lion.state_name()] = true
		min_d = minf(min_d, lion.pos2().distance_to(g["center"]))
		if lion.state == Predator.State.PATROL or lion.state == Predator.State.REST:
			break
	check(seen.has("SEARCH"), "predator searches after losing the deer", seen.keys())
	check(seen.has("RETURN") and (lion.state == Predator.State.PATROL or lion.state == Predator.State.REST), "then returns to patrol", lion.state_name())
	check(min_d > float(g["radius"]) - 0.5, "predator never enters the safe thicket", "closest %.1f m, radius %.0f" % [min_d, g["radius"]])
	check(player.health == player.max_health, "deer unharmed inside the thicket")
	await wait(0.5)
	check(GameState.escapes == escapes + 1 and GameState.threat < GameState.Threat.HUNTED, "escape is counted", GameState.escapes)
	world.day_night.paused = false


func place_keep_state(pred: Predator, x: float, z: float) -> void:
	pred.global_position = Vector3(x, world.data.height_at(x, z) + 0.2, z)
	pred.reset_physics_interpolation()


func test_day_night() -> void:
	print("\n-- day / night")
	isolate()
	var dn := world.day_night
	dn.paused = false
	teleport(open_spot(0).x, open_spot(0).y + 10.0)
	dn.set_time(12.0)
	await wait(0.2)
	check(dn.sun.visible and dn.sun.light_energy > 1.0 and not dn.moon.visible and dn.night_factor < 0.01, "noon: bright sun, no moon",
		"sun %.2f" % dn.sun.light_energy)
	var fog_day: Color = dn.env.fog_light_color
	dn.set_time(18.4)
	await wait(0.2)
	check(dn.sunset_factor > 0.4 and dn.phase == &"dusk", "sunset colours at dusk", "sunset %.2f" % dn.sunset_factor)
	var before := world.predators.predators.size()
	dn.set_time(19.45)
	await wait(1.0)
	dn.set_time(0.5)
	await wait(0.3)
	check(dn.phase == &"night" and not dn.sun.visible and dn.moon.visible and dn.moon.shadow_enabled, "midnight: moonlight only",
		"moon %.2f night %.2f" % [dn.moon.light_energy, dn.night_factor])
	check(dn.env.fog_light_color.v < fog_day.v * 0.2 and dn.env.ambient_light_energy < 0.7, "night is dark")
	check(world.predators.predators.size() == before + 3, "an extra hyena pack arrives at night", world.predators.predators.size())
	var lion := _first("lion")
	check(lion.activity() > 1.2 and lion.current_run_speed() > lion.run_speed, "predators are more active and faster at night",
		"activity x%.2f" % lion.activity())
	var cheetah := _first("cheetah")
	check(cheetah.activity() < 1.0, "cheetahs (day hunters) are less active at night", cheetah.activity())
	var t := dn.time_of_day
	await wait(5.0)
	check(dn.time_of_day > t, "time advances", "%.3f -> %.3f h" % [t, dn.time_of_day])
	var day := dn.day
	dn.set_time(5.99)
	await wait(1.0)
	check(dn.day == day + 1, "a new day is counted at dawn", dn.day)
	dn.set_time(6.4)
	await wait(0.2)
	check(dn.phase == &"dawn" and dn.sunset_factor > 0.3, "sunrise", "factor %.2f" % dn.sunset_factor)
	dn.set_time(9.0)
	await wait(0.5)
	check(world.predators.night_pack_size() == 0 and world.predators.predators.size() == before, "night pack leaves by day", world.predators.predators.size())
	isolate()


func test_audio() -> void:
	print("\n-- audio")
	# every audio path referenced anywhere in the scripts must exist and load
	var missing: PackedStringArray = []
	var count := 0
	var re := RegEx.new()
	re.compile("res://audio/[A-Za-z0-9_/%]+\\.ogg")
	for dir_path: String in ["res://scripts/autoload", "res://scripts/player", "res://scripts/predators", "res://scripts/world", "res://scripts/ui", "res://scripts"]:
		for f in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir_path + "/" + f)
			for m in re.search_all(text):
				var path := m.get_string()
				var variants: PackedStringArray = [path]
				if path.contains("%d"):
					variants = []
					for i in range(1, 9):
						var cand := path.replace("%d", str(i))
						if i <= 2 or ResourceLoader.exists(cand):
							variants.append(cand)
				elif path.contains("%s"):
					variants = [path.replace("%s", "a"), path.replace("%s", "b")]
				for v in variants:
					count += 1
					if not ResourceLoader.exists(v) or not (load(v) is AudioStream):
						missing.append(v)
	check(missing.is_empty(), "all %d referenced sounds exist and load" % count, missing)
	check(AudioServer.get_bus_index("Music") > 0 and AudioServer.get_bus_index("SFX") > 0 and AudioServer.get_bus_index("Ambience") > 0, "audio buses created")
	check(world.ambience._day_a.playing and world.ambience._night.playing and world.ambience._water.playing, "ambience layers are playing")
	check(AudioManager.current_music() != "", "music is playing", AudioManager.current_music())
	world.day_night.set_time(12.0)
	await wait(3.0)
	var day_vol := world.ambience._day_a.volume_db
	var night_vol := world.ambience._night.volume_db
	world.day_night.set_time(0.0)
	await wait(4.0)
	check(world.ambience._night.volume_db > night_vol + 20.0 and world.ambience._day_a.volume_db < day_vol - 20.0,
		"ambience changes with time of day", "crickets %.0f -> %.0f dB" % [night_vol, world.ambience._night.volume_db])
	world.day_night.set_time(10.0)
	var lion := _first("lion")
	lion.process_mode = Node.PROCESS_MODE_INHERIT
	lion.vocalize("roar", 0.0, true)
	check(lion._voice.playing and lion._voice.stream != null, "predator vocalises through a 3D emitter")
	isolate()
	Settings.set_value("audio", "music", 0.25, false)
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))) - 0.25) < 0.01, "volume setting drives the bus")
	Settings.set_value("audio", "music", 0.55, false)


func test_pause_settings() -> void:
	print("\n-- pause & settings")
	main.pause()
	await get_tree().process_frame
	check(get_tree().paused and main.menus.current_screen() == "pause", "pause menu opens and the game stops")
	var pos := player.global_position
	var time := world.day_night.time_of_day
	for i in 30:
		await get_tree().process_frame
	check(world.day_night.time_of_day == time and player.global_position == pos, "world frozen while paused")
	main.menus._open_settings(main.menus._pause)
	check(main.menus.current_screen() == "settings", "settings open from pause")
	var old := Settings.get_binding("jump")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	Settings.rebind("jump", ev)
	check(InputMap.action_has_event("jump", ev) and Settings.binding_text("jump") == "F", "key rebinding works", Settings.binding_text("jump"))
	Settings.reset_bindings()
	check(Settings.get_binding("jump") == old, "bindings reset")
	Settings.set_value("graphics", "preset", 0, false)
	check(float(Settings.get_value("graphics", "vegetation_distance")) < 0.7 and not world.day_night.env.volumetric_fog_enabled,
		"low preset reduces vegetation distance and disables volumetric fog")
	Settings.set_value("graphics", "preset", 2, false)
	check(world.day_night.env.volumetric_fog_enabled, "high preset restores it")
	Settings.set_value("controls", "mouse_sensitivity", 0.8, false)
	check(is_equal_approx(float(Settings.get_value("controls", "mouse_sensitivity")), 0.8), "sensitivity adjustable")
	Settings.set_value("controls", "mouse_sensitivity", 0.5, false)
	main.menus.settings.close()
	check(main.menus.current_screen() == "pause", "back returns to pause menu")
	main.menus.resume_requested.emit()
	await get_tree().process_frame
	check(not get_tree().paused and main.flow == 2 and main.menus.current_screen() == "", "resume continues the game")


func test_death_and_restart() -> void:
	print("\n-- death & restart")
	isolate()
	teleport(open_spot(0).x, open_spot(0).y + 10.0)
	restore_stats()
	player.thirst = 0.0
	player.health = 2.0
	await wait(2.5)
	check(player.is_dead() and player.rig.current == "Death", "deer dies of thirst", GameState.cause_of_death)
	await wait(3.5)
	check(main.flow == 4 and main.menus.current_screen() == "gameover", "game over screen appears")
	check(GameState.cause_of_death == "thirst" and GameState.time_survived > 1.0, "run statistics recorded",
		"survived %s" % GameState.format_time(GameState.time_survived))
	main.menus.restart_requested.emit()
	await wait(0.5)
	check(main.flow == 2 and not player.is_dead() and player.health == 100.0 and GameState.time_survived < 2.0, "restart begins a fresh run")
	check(world.predators.predators.size() == 13, "predators reset", world.predators.predators.size())
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(world.data.spawn_point) < 2.0, "deer back at the spawn")
	# killed by a predator -> correct cause
	player.take_damage(500.0, "Tiger")
	await wait(3.5)
	check(GameState.cause_of_death == "Tiger" and main.flow == 4, "predator kill reported on game over")
	main.menus.menu_requested.emit()
	await wait(0.3)
	check(main.flow == 1 and main.menus.current_screen() == "main" and not player.is_dead(), "main menu reachable from game over")
	check(world.grass.pooled_reuses > 0, "grass cells are pooled and reused", world.grass.pooled_reuses)
