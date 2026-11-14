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
	# the classic tests run on the fixed spawn, with the full-speed deer and the endless roster
	GameState.test_mode = true
	GameState.set_mode(GameState.Mode.ENDLESS)
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
	# the real game: campaign level, random spawn, slow deer, weather
	GameState.test_mode = false
	GameState.set_mode(GameState.Mode.CAMPAIGN)
	GameState.abilities = {}
	GameState.level = int(OS.get_environment("WS_LEVEL")) if OS.get_environment("WS_LEVEL") != "" else 2
	var weather_seen := {}
	var levels_won := 0
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
		weather_seen[world.weather.state_name()] = int(weather_seen.get(world.weather.state_name(), 0)) + 1
		if main.flow == 5:
			levels_won += 1
			main.menus.next_level_requested.emit()
			await wait(0.5)
			hp = player.health
		if main.flow == 4:
			deaths.append("%s at %s (day %d %s)" % [GameState.cause_of_death, GameState.format_time(GameState.time_survived), world.day_night.day, world.day_night.clock_text()])
			main.menus.restart_requested.emit()
			await wait(0.5)
			hp = player.health
	release_all()
	print("  [info] predator state seconds: ", hist)
	print("  [info] bot deaths: ", deaths)
	print("  [info] level %d, weather seconds %s, plants found %d, wildlife seen %s, levels won %d" % [GameState.level + 1, weather_seen, GameState.plants_found, GameState.spotted.keys(), levels_won])
	print("  [info] hits taken %d, seconds hunted %.0f, escapes %d, clock day %d %s" % [hits, hunted_time, GameState.escapes, world.day_night.day, world.day_night.clock_text()])
	print("  [info] prey: %d alive of %d, %d killed by predators" % [world.prey.living(), world.prey.animals.size(), world.prey.kills])
	check(true, "soak finished without stalling")


## Frame-by-frame smoothness probe (WS_PROBE=1): looks for visual glitches a player would notice —
## clip flicker, heading jitter, vertical pops, speed oscillation — for every species.
func _probe_run(pred: Predator, label: String, frames: int, keep_alive: bool) -> void:
	var clip_switches := 0
	var state_switches := 0
	var last_clip := pred.rig.current
	var last_state := pred.state
	var last_heading := pred.rotation.y
	var last_pos := pred.global_position
	var last_dh := 0.0
	var max_dh := 0.0
	var flips := 0
	var max_dy := 0.0
	var max_step := 0.0
	var speed_rev := 0
	var last_speed := pred._speed
	var last_ds := 0.0
	var clips := {}
	var states := {}
	var max_tilt := 0.0
	var off_ground := 0.0
	var timeline: PackedStringArray = []
	for i in frames:
		await get_tree().physics_frame
		if keep_alive:
			player.health = player.max_health
		if pred.rig.current != last_clip:
			clip_switches += 1
			last_clip = pred.rig.current
			if timeline.size() < 40:
				timeline.append("%.2f:%s" % [i / 60.0, last_clip])
		if pred.state != last_state:
			state_switches += 1
			last_state = pred.state
			if timeline.size() < 40:
				timeline.append("%.2f:[%s]" % [i / 60.0, pred.state_name()])
		clips[pred.rig.current] = int(clips.get(pred.rig.current, 0)) + 1
		states[pred.state_name()] = int(states.get(pred.state_name(), 0)) + 1
		var dh := angle_difference(last_heading, pred.rotation.y)
		max_dh = maxf(max_dh, absf(dh))
		if absf(dh) > 0.004 and absf(last_dh) > 0.004 and signf(dh) != signf(last_dh):
			flips += 1
		if absf(dh) > 0.004:
			last_dh = dh
		last_heading = pred.rotation.y
		var d := pred.global_position - last_pos
		max_dy = maxf(max_dy, absf(d.y))
		max_step = maxf(max_step, Vector2(d.x, d.z).length())
		last_pos = pred.global_position
		var ds := pred._speed - last_speed
		if absf(ds) > 0.02 and absf(last_ds) > 0.02 and signf(ds) != signf(last_ds):
			speed_rev += 1
		if absf(ds) > 0.02:
			last_ds = ds
		last_speed = pred._speed
		max_tilt = maxf(max_tilt, maxf(absf(pred.rig.rotation.x), absf(pred.rig.rotation.z)))
		off_ground = maxf(off_ground, absf(pred.global_position.y - world.data.height_at(pred.global_position.x, pred.global_position.z)))
	print("  [probe] %-22s clips %s states %s" % [label, clips, states])
	print("          clip switches %d, state switches %d, heading: max %.3f rad/frame, reversals %d; max dy %.3f, max step %.3f m, speed reversals %d, max tilt %.2f, off ground %.2f" % [
		clip_switches, state_switches, max_dh, flips, max_dy, max_step, speed_rev, max_tilt, off_ground])
	print("          timeline ", " ".join(timeline))


func probe() -> void:
	print("\n-- glitch probe")
	main.menus.start_requested.emit()
	await wait(0.5)
	world.day_night.set_time(12.0)
	world.day_night.paused = true
	for kind: String in ["lion", "cheetah", "tiger", "hyena"]:
		var pred := _first(kind)
		# 1: patrolling 30 m from a hidden, motionless deer
		isolate(pred)
		restore_stats()
		var s := open_spot(1)
		teleport(s.x, s.y)
		place(pred, s.x + 30.0, s.y)
		pred.awareness = 0.0
		pred.vision_range = 0.01
		pred.hearing = 0.0
		pred.set_state(Predator.State.PATROL)
		await _probe_run(pred, kind + " patrol", 1500, true)
		# 2: resting next to the deer
		pred.set_state(Predator.State.REST)
		pred._wait = 999.0
		await _probe_run(pred, kind + " rest", 600, true)
		# 3: full hunt on a deer that stands still
		pred._configure()
		await _setup_encounter(pred, 22.0, 1, true)
		pred.last_known = player.global_position
		pred.awareness = 1.0
		pred._on_detected()
		await _probe_run(pred, kind + " hunt standing deer", 1200, true)
		# 4: hunt on a deer running away
		await _setup_encounter(pred, 22.0, 1, true)
		world.camera.rotation.y = 0.0
		Input.action_press("move_forward")
		Input.action_press("sprint")
		pred.last_known = player.global_position
		pred.awareness = 1.0
		pred._on_detected()
		await _probe_run(pred, kind + " hunt fleeing deer", 1800, true)
		release_all()


func _run() -> void:
	if OS.get_environment("WS_STRIDES") != "":
		measure_strides()
		return
	if OS.get_environment("WS_MAP") != "":
		export_map(OS.get_environment("WS_MAP"))
		return
	# wild-prey hunts are switched on only inside the prey tests, so they cannot disturb the others
	world.predators.allow_hunts = false
	if OS.get_environment("WS_PROBE") != "":
		await probe()
		return
	if OS.get_environment("WS_SOAK") != "":
		world.predators.allow_hunts = true
		await soak(float(OS.get_environment("WS_SOAK")))
		return
	if OS.get_environment("WS_ONLY") != "":
		# run a few named tests only, e.g. WS_ONLY=cheetah,expansion
		await test_menu_flow()
		for t in OS.get_environment("WS_ONLY").split(","):
			await call("test_" + t)
		return
	await test_load()
	await test_layout()
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
	await test_prey()
	await test_feet()
	await test_touch_controls()
	await test_day_night()
	await test_audio()
	await test_pause_settings()
	await test_death_and_restart()
	await test_expansion()


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


## Measure, for every animal model, how fast the feet travel over the ground in each locomotion clip
## at playback rate 1 (per unit of model scale). WS_STRIDES=1 writes animations/strides.json, which
## AnimalRig uses to match animation speed to movement speed so feet do not slide.
func measure_strides() -> void:
	var out := {}
	for path: String in ["lion", "tiger", "cheetah", "hyena", "deer", "gazelle", "boar", "crocodile", "wolf", "goat", "zebu", "fox", "chicken"]:
		var full := "res://models/animals/%s.glb" % path
		var rig := AnimalRig.new()
		add_child(rig)
		rig.setup(full, 1.0, {"Run": "Gallop"}, not (path in ["gazelle", "boar", "crocodile", "wolf", "goat", "zebu", "fox", "chicken"]))
		var skel: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		var entry := {}
		for clip: String in ["Walk", "Run"]:
			if not rig.has(clip):
				continue
			var length := rig.length(clip)
			var n := 60
			var tracks: Array = []
			for i in skel.get_bone_count():
				tracks.append([])
			rig.anim.play(clip, 0.0)
			for k in n + 1:
				rig.anim.seek(length * k / n, true)
				var xf := rig.global_transform.affine_inverse() * skel.global_transform
				for i in skel.get_bone_count():
					(tracks[i] as Array).append(xf * skel.get_bone_global_pose(i).origin)
			# model length, to scale thresholds
			var zmin := INF
			var zmax := -INF
			for i in tracks.size():
				zmin = minf(zmin, tracks[i][0].z)
				zmax = maxf(zmax, tracks[i][0].z)
			var body := zmax - zmin
			var cands: Array = []
			for i in tracks.size():
				var t: Array = tracks[i]
				var lo := INF
				var hi := -INF
				var ymean := 0.0
				for v: Vector3 in t:
					lo = minf(lo, v.z)
					hi = maxf(hi, v.z)
					ymean += v.y
				if hi - lo > body * 0.08:
					cands.append([ymean / t.size(), i])
			cands.sort()
			var feet: Array = []
			for c: Array in cands:
				var p0: Vector3 = tracks[c[1]][0]
				var distinct := true
				for f: int in feet:
					var q: Vector3 = tracks[f][0]
					if Vector2(p0.x - q.x, p0.z - q.z).length() < body * 0.12:
						distinct = false
				if distinct:
					feet.append(c[1])
				if feet.size() == 4:
					break
			var speeds: Array = []
			var dt := length / n
			for f: int in feet:
				var t: Array = tracks[f]
				var ylo := INF
				var yhi := -INF
				for v: Vector3 in t:
					ylo = minf(ylo, v.y)
					yhi = maxf(yhi, v.y)
				var vs: Array = []
				for k in range(1, n):
					if t[k].y < ylo + (yhi - ylo) * 0.2 + 0.0001:
						vs.append((t[k + 1].z - t[k - 1].z) / (2.0 * dt))
				vs.sort()
				if not vs.is_empty():
					speeds.append(vs[vs.size() / 2])
			# keep the bones that really are planted feet: the ones travelling at a good part of the
			# fastest stance speed (drops tails, ears and bones that never touch the ground)
			var top := 0.0
			for v: float in speeds:
				top = maxf(top, v)
			var good: Array = []
			for v: float in speeds:
				if v > top * 0.5:
					good.append(v)
			good.sort()
			var mean: float = good[good.size() / 2] if not good.is_empty() else 0.0
			if good.size() > 1 and good.size() % 2 == 0:
				mean = (good[good.size() / 2] + good[good.size() / 2 - 1]) * 0.5
			var names: Array = []
			for f: int in feet:
				names.append(skel.get_bone_name(f))
			print("  [stride] %s %s  len %.2f  feet %s  stance speeds %s  -> %.3f" % [path, clip, length, names, speeds, mean])
			if mean > 0.05:
				entry[clip] = snappedf(mean, 0.001)
		out[full] = entry
		rig.queue_free()
	var f := FileAccess.open("res://animations/strides.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ") + "\n")
	f.close()
	check(true, "strides written")


func _on_screen(c: Control) -> bool:
	var view := Rect2(Vector2.ZERO, c.get_viewport_rect().size).grow(1.0)
	return c.size.x > 4.0 and c.size.y > 4.0 and view.encloses(c.get_global_rect())


## Things a player sees first: every menu page must be laid out on screen where it belongs.
func test_layout() -> void:
	print("\n-- menu layout")
	var m: Menus = main.menus
	var view := m._root.get_viewport_rect().size
	check(m._root.size.distance_to(view) < 2.0, "menu root covers the screen", "%s of %s" % [m._root.size, view])
	check(_on_screen(m._main) and m._main.size.distance_to(view) < 2.0, "main menu page covers the screen", m._main.size)
	var buttons := m._main.find_children("*", "Button", true, false)
	var ok := buttons.size() == 7
	for b: Button in buttons:
		ok = ok and _on_screen(b) and b.global_position.x < view.x * 0.3 and b.size.x < 400.0
	check(ok, "main menu buttons sit on the left, on screen", "%d buttons, first at %s" % [buttons.size(), (buttons[0] as Button).global_position])
	m._help.show()
	await wait(0.1)
	check(_on_screen(m._help) and m._help.get_global_rect().get_center().x > view.x * 0.55, "help panel opens on the right, on screen", m._help.get_global_rect())
	var overlap := false
	for b: Button in buttons:
		overlap = overlap or b.get_global_rect().intersects(m._help.get_global_rect())
	check(not overlap, "help panel does not cover the buttons")
	m._help.hide()
	m.show_loading("Testing", 0.5)
	await wait(0.1)
	var bar := m._loading_bar.get_global_rect()
	check(_on_screen(m._loading_bar) and absf(bar.get_center().x - view.x * 0.5) < 4.0 and absf(bar.get_center().y - view.y * 0.5) < 160.0,
		"loading bar is centred on screen", "%s in %s" % [bar, view])
	check(absf(m._loading_text.get_global_rect().get_center().x - view.x * 0.5) < 4.0 and m._loading_text.get_global_rect().end.y <= bar.position.y + 1.0,
		"loading text is centred above the bar")
	m._loading.hide()
	m._open_settings(m._main)
	await wait(0.1)
	var panel: Control = m.settings.find_children("*", "PanelContainer", true, false)[0]
	check(_on_screen(panel) and panel.get_global_rect().get_center().distance_to(view * 0.5) < 6.0, "settings panel is centred on screen", panel.get_global_rect())
	var tabs: TabContainer = m.settings.find_children("*", "TabContainer", true, false)[0]
	var fits := true
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await wait(0.05)
		fits = fits and _on_screen(panel)
	tabs.current_tab = 0
	check(fits, "every settings tab fits on screen")
	m.settings.close()
	for page: Control in [m._pause, m._over]:
		page.show()
		await wait(0.05)
		var pp: Control = page.find_children("*", "PanelContainer", true, false)[0]
		check(_on_screen(pp) and pp.get_global_rect().get_center().distance_to(view * 0.5) < 6.0, "%s panel is centred" % ("pause" if page == m._pause else "game over"), pp.get_global_rect())
		page.hide()
	m.show_main()
	# HUD and touch layer
	var hud: HUD = main.hud
	check(hud._root.size.distance_to(view) < 2.0 and hud.touch.size.distance_to(view) < 2.0, "HUD and touch layer cover the screen", "%s %s" % [hud._root.size, hud.touch.size])
	hud.visible = true
	await wait(0.1)
	var bad: PackedStringArray = []
	for c: Control in hud._root.find_children("*", "Control", true, false):
		if c is Container or c is ProgressBar or (c is Label and (c as Label).text != ""):
			if c.is_visible_in_tree() and c.size.x > 0.0 and not Rect2(Vector2.ZERO, view).grow(2.0).encloses(c.get_global_rect()):
				bad.append("%s %s" % [c.get_class(), c.get_global_rect()])
	check(bad.is_empty(), "HUD elements are all on screen", bad)
	hud.visible = false


func _prey_of(kind: String) -> Prey:
	for a in world.prey.animals:
		if a.kind == kind and a.alive():
			return a
	return null


func _place_prey(a: Prey, x: float, z: float) -> void:
	a.respawn_at(Vector2(x, z))
	a.process_mode = Node.PROCESS_MODE_INHERIT


func test_prey() -> void:
	print("\n-- prey animals")
	isolate()
	var pm: PreyManager = world.prey
	var counts := {}
	for a in pm.animals:
		counts[a.kind] = int(counts.get(a.kind, 0)) + 1
	check(int(counts.get("gazelle", 0)) >= 12 and int(counts.get("boar", 0)) >= 8, "herds of gazelle and boar spawned", counts)
	var dry := true
	for a in pm.animals:
		dry = dry and world.data.is_walkable(a.global_position.x, a.global_position.z) and a.rig.has("Walk") and a.rig.has("Idle")
	check(dry, "all prey stand on walkable land and have animations")
	# park everything, then work with a few animals in a clearing
	for a in pm.animals:
		a.process_mode = Node.PROCESS_MODE_DISABLED
	var c := open_spot(1)
	teleport(c.x + 60.0, c.y + 60.0)
	var gz := _prey_of("gazelle")
	var boar := _prey_of("boar")
	_place_prey(gz, c.x, c.y)
	await wait(0.5)
	# model orientation: the head (highest bone) must be ahead of the body
	var skel: Skeleton3D = gz.rig.find_children("*", "Skeleton3D", true, false)[0]
	var top := Vector3.ZERO
	var top_y := -INF
	for i in skel.get_bone_count():
		var p := skel.global_transform * skel.get_bone_global_pose(i).origin
		if p.y > top_y:
			top_y = p.y
			top = p
	check((top - gz.global_position).dot(gz.forward()) > 0.1, "gazelle model faces the way it walks", "head %.2f m ahead, %.2f m up" % [(top - gz.global_position).dot(gz.forward()), top_y - gz.global_position.y])
	check(top_y - gz.global_position.y > 0.6 and top_y - gz.global_position.y < 1.6, "gazelle is a sensible size", "%.2f m" % (top_y - gz.global_position.y))
	check(absf(gz.global_position.y - world.data.height_at(gz.global_position.x, gz.global_position.z)) < 0.3, "gazelle stands on the ground")
	# grazing and wandering
	gz._wait = 0.5
	await wait(4.0)
	check(gz.state == Prey.State.WANDER or gz.pos2().distance_to(c) > 0.5, "prey wanders between grazing spots", "moved %.1f m" % gz.pos2().distance_to(c))
	check(gz._speed < gz.walk_speed + 0.3, "prey walks calmly when undisturbed", "%.1f m/s" % gz._speed)
	# the deer walks into it
	_place_prey(gz, c.x, c.y)
	teleport(c.x + 5.0, c.y)
	await wait(1.5)
	var d1 := gz.global_position.distance_to(player.global_position)
	check(gz.is_fleeing() and d1 > 9.0, "prey bolts when the deer blunders close", "%.1f m away, %.1f m/s" % [d1, gz._speed])
	check(gz.rig.current == "Walk" and gz.rig.anim.get_playing_speed() > 1.5, "fleeing prey plays a fast gait", "%s x%.2f" % [gz.rig.current, gz.rig.anim.get_playing_speed()])
	teleport(c.x + 80.0, c.y + 60.0)
	await wait(9.0)
	check(not gz.is_fleeing() and gz._speed < 2.0, "prey calms down once the danger has gone", Prey.State.keys()[gz.state])
	# a herd mate is warned
	var mate: Prey = null
	for a in pm.animals:
		if a != gz and a.herd_id == gz.herd_id:
			mate = a
	_place_prey(gz, c.x, c.y)
	_place_prey(mate, c.x + 6.0, c.y + 3.0)
	await wait(0.3)
	gz.startle(gz.global_position + Vector3(4, 0, 0))
	await wait(0.3)
	check(mate.is_fleeing(), "herd mates are warned when one bolts")
	mate.process_mode = Node.PROCESS_MODE_DISABLED
	gz.process_mode = Node.PROCESS_MODE_DISABLED
	gz.global_position = Vector3(-400, 60, 400)
	mate.global_position = Vector3(-405, 60, 400)

	# a lion hunts a boar
	var lion := _first("lion")
	isolate(lion)
	place(lion, c.x, c.y)
	_place_prey(boar, c.x + 22.0, c.y)
	lion._hunt_cd = 0.0
	world.predators.allow_hunts = true
	await wait(1.0)
	check(lion.state == Predator.State.HUNT and lion.prey_target == boar, "an idle lion goes after nearby prey", lion.state_name())
	check(lion.threat_level() == GameState.Threat.CALM, "a lion hunting prey is no threat to the deer")
	var fled := false
	var top_speed := 0.0
	for i in 1200:
		await get_tree().physics_frame
		fled = fled or boar.is_fleeing()
		top_speed = maxf(top_speed, boar._speed)
		if not boar.alive():
			break
	check(fled and top_speed > 6.0, "the boar ran for its life", "top %.1f m/s" % top_speed)
	check(not boar.alive() and pm.kills == 1, "the lion brought the boar down", "lion %s, boar %s" % [lion.state_name(), Prey.State.keys()[boar.state]])
	check(lion.state == Predator.State.FEED, "the lion stays to feed on its kill", lion.state_name())
	await wait(1.5)
	check(absf(boar.rig.rotation.z) > 1.2 and lion._speed < 0.5, "the carcass lies on its side and the lion stands over it", "roll %.2f" % boar.rig.rotation.z)
	# the deer shows up: the lion forgets its meal
	teleport(lion.global_position.x + 9.0, lion.global_position.z + 3.0)
	await wait(2.5)
	check(lion.state == Predator.State.CHASE or lion.state == Predator.State.ATTACK or lion.state == Predator.State.SPECIAL, "a feeding lion still turns on a deer it notices", lion.state_name())
	isolate()
	teleport(c.x + 80.0, c.y + 60.0)
	# a lost hunt is abandoned
	var cheetah := _first("cheetah")
	isolate(cheetah)
	place(cheetah, c.x, c.y)
	_place_prey(gz, c.x + 20.0, c.y)
	cheetah._hunt_cd = 0.0
	await wait(0.6)
	check(cheetah.state == Predator.State.HUNT, "a cheetah hunts gazelle", cheetah.state_name())
	gz.global_position = Vector3(c.x + 20.0, world.data.height_at(c.x + 20.0, c.y + 150.0), c.y + 150.0)
	await wait(1.0)
	check(cheetah.state != Predator.State.HUNT and cheetah.prey_target == null and gz.hunter == null, "a hunt is abandoned when the prey gets away", cheetah.state_name())
	world.predators.allow_hunts = false
	isolate()
	# carcasses are recycled far from the deer
	boar._carcass_time = 0.1
	await wait(0.5)
	check(boar.alive() and boar.global_position.distance_to(player.global_position) > 100.0, "a carcass is replaced by a new animal far away", "%.0f m" % boar.global_position.distance_to(player.global_position))
	check(pm.living() == pm.animals.size(), "prey population is back to full", "%d / %d" % [pm.living(), pm.animals.size()])
	for a in pm.animals:
		a.process_mode = Node.PROCESS_MODE_DISABLED
	restore_stats()


## Feet: animation speed must match ground speed (no skating) and the body must follow the slope.
func test_feet() -> void:
	print("\n-- feet and ground contact")
	isolate()
	var table := AnimalRig.stride_table()
	check(table.size() >= 6, "stride table loaded", table.keys().size())
	# Mirrored (negative-scale) bones are posed wrongly by the engine: legs fly up in the air. The
	# models must not contain any, and nothing above a skeleton may be scaled a hundredfold.
	for kind: String in ["lion", "cheetah", "tiger", "hyena"]:
		var pr := _first(kind)
		var sk: Skeleton3D = pr.rig.find_children("*", "Skeleton3D", true, false)[0]
		var bad: PackedStringArray = []
		for i in sk.get_bone_count():
			var b := sk.get_bone_rest(i).basis
			if b.determinant() < 0.0 or absf(b.get_scale().x - 1.0) > 0.01 or absf(b.get_scale().y - 1.0) > 0.01 or absf(b.get_scale().z - 1.0) > 0.01:
				bad.append(sk.get_bone_name(i))
		check(bad.is_empty(), "%s skeleton has no mirrored or scaled bones" % kind, bad)
		var mi: MeshInstance3D = pr.rig.find_children("*", "MeshInstance3D", true, false)[0]
		var size := mi.get_aabb().size * mi.global_transform.basis.get_scale().x
		check(maxf(size.x, maxf(size.y, size.z)) > 0.8 and maxf(size.x, maxf(size.y, size.z)) < 3.5, "%s mesh bounds are animal-sized in the world" % kind, size)
	var c := open_spot(1)
	teleport(c.x + 70.0, c.y + 70.0)
	for kind: String in ["lion", "cheetah", "tiger", "hyena"]:
		var pred := _first(kind)
		isolate(pred)
		place(pred, c.x, c.y)
		for gait: Array in [["walk", pred.walk_speed, 2.0], ["trot", pred.trot_speed, lerpf(1.7, 3.0, clampf(pred.trot_speed / pred.run_speed, 0.0, 1.0))]]:
			for i in 150:
				pred.has_target = true
				pred.move_target = pred.global_position + pred.forward() * 8.0
				pred.move_speed = gait[1]
				await get_tree().physics_frame
			var clip := pred.rig.current
			var rate := pred.rig.anim.get_playing_speed()
			var foot_speed: float = float(pred.rig._strides.get(clip, 0.0)) * pred.rig._scale * rate
			var cps := rate / pred.rig.length(clip)
			# feet either match the ground speed, or the clip is already at its fastest sensible cadence
			var grips := absf(foot_speed - pred._speed) < pred._speed * 0.12 + 0.05
			check((clip == "Walk" or clip == "Run") and (grips or cps > float(gait[2]) - 0.06),
				"%s paws keep pace with the ground at a %s" % [kind, gait[0]],
				"%s: moving %.2f m/s, feet %.2f m/s, %.2f steps/s%s" % [clip, pred._speed, foot_speed, cps, "" if grips else " (cadence limit)"])
		# no clip flicker when creeping at the walk/idle boundary
		var switches := 0
		var last := pred.rig.current
		for i in 180:
			pred.has_target = true
			pred.move_target = pred.global_position + pred.forward() * 5.0
			pred.move_speed = 0.34 if (i / 6) % 2 == 0 else 0.1
			await get_tree().physics_frame
			if pred.rig.current != last:
				switches += 1
				last = pred.rig.current
		check(switches <= 4, "%s does not flick between clips at a crawl" % kind, "%d switches in 3 s" % switches)
		pred.stop_moving()
	# slope: find a steady incline and stand a lion on it facing uphill
	var lion := _first("lion")
	isolate(lion)
	var d := world.data
	var spot := Vector2.ZERO
	var best := 0.0
	var dir := Vector2.ZERO
	for i in 4000:
		var x := -420.0 + fposmod(i * 37.7, 840.0)
		var z := -420.0 + fposmod(i * 91.3, 840.0)
		var s := d.slope_at(x, z)
		if s > 0.08 and s < 0.2 and d.height_at(x, z) > 2.0 and s > best:
			var n := d.normal_at(x, z)
			var up := Vector2(-n.x, -n.z).normalized()
			# the slope must be even under the whole body
			var hf := d.height_at(x + up.x, z + up.y)
			var hb := d.height_at(x - up.x, z - up.y)
			if hf - hb > 0.35:
				best = s
				spot = Vector2(x, z)
				dir = up
	check(best > 0.0, "found a slope to stand on", "slope %.2f at %s" % [best, spot])
	place(lion, spot.x, spot.y)
	lion.set_state(Predator.State.REST)
	lion._heading = atan2(-dir.x, -dir.y)
	await wait(1.5)
	var fwd := lion.forward()
	var nose := lion.rig.global_transform * Vector3(0.0, 0.0, -1.0)
	var tail := lion.rig.global_transform * Vector3(0.0, 0.0, 1.0)
	var gf := d.height_at(nose.x, nose.z)
	var gb := d.height_at(tail.x, tail.z)
	check(nose.y - tail.y > 0.1 and gf > gb, "body pitches nose-up when facing uphill", "nose %.2f tail %.2f (ground %.2f / %.2f)" % [nose.y, tail.y, gf, gb])
	check(absf((nose.y - gf) - (tail.y - gb)) < 0.25, "fore and hind feet are equally close to the ground on a slope", "front gap %.2f, rear gap %.2f" % [nose.y - gf, tail.y - gb])
	check(fwd.length() > 0.9, "lion still upright")
	# the deer uses the same correction
	teleport(spot.x, spot.y, atan2(-dir.x, -dir.y))
	isolate()
	await wait(1.2)
	var dn := player.rig.global_transform * Vector3(0.0, 0.0, -1.0)
	var dt2 := player.rig.global_transform * Vector3(0.0, 0.0, 1.0)
	check(dn.y > dt2.y + 0.05, "the deer also pitches nose-up facing uphill", "nose %.2f tail %.2f" % [dn.y, dt2.y])
	restore_stats()


func test_menu_flow() -> void:
	print("\n-- menu flow")
	check(main.flow == 1 and main.menus.current_screen() == "main", "main menu shown after loading")
	check(not player.control_enabled, "player frozen in menu")
	main.menus.start_requested.emit()
	await wait(0.2)
	check(main.flow == 2 and main.hud.visible and GameState.in_game, "start button begins the game")
	check(world.predators.predators.size() == PredatorManager.ROSTER_SIZE, "predator roster spawned", world.predators.predators.size())
	check(world.prey.animals.size() >= 20, "prey herds spawned", world.prey.animals.size())
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
	check(t_chase >= 0.0, "cheetah spots the deer from 45 m", "after %.1f s (state %s, awareness %.2f, rest left %.1f s, deer visibility %.2f, sees %s, dist %.0f)" % [t_chase,
		cheetah.state_name(), cheetah.awareness, cheetah._exhausted_until - Time.get_ticks_msec() * 0.001, player.visibility, cheetah.sees_player, cheetah.player_distance])
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


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	# positions are given in UI (stretched viewport) units; real events arrive in window pixels
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = get_viewport().get_final_transform() * pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	var xf := get_viewport().get_final_transform()
	ev.position = xf * pos
	ev.relative = xf.basis_xform(rel)
	Input.parse_input_event(ev)


func test_touch_controls() -> void:
	print("\n-- touch controls")
	var tc: TouchControls = main.hud.touch
	isolate()
	check(not tc.is_active(), "touch controls stay hidden on desktop (auto)")
	Settings.set_value("controls", "touch_controls", 1, false)
	await wait(0.1)
	check(tc.is_active(), "touch controls can be switched on")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse is not grabbed while touch controls are on")
	var size := get_viewport().get_visible_rect().size
	var s := open_spot(1)
	teleport(s.x, s.y)
	world.camera.rotation.y = 0.0
	restore_stats()
	await wait(0.3)
	# stick: finger down in the lower left, pushed up = forward
	var base := Vector2(260.0, size.y - 250.0)
	var p0 := player.global_position
	_touch(0, base, true)
	_drag(0, base + Vector2(0.0, -130.0), Vector2(0.0, -130.0))
	await wait(1.5)
	var walked := player.global_position - p0
	check(walked.z < -3.0 and absf(walked.x) < 1.5, "stick pushed up moves the deer forward", "moved %.1f m forward" % -walked.z)
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.9, "stick drives the movement actions")
	# RUN toggle with a second finger while the stick is held
	var run_pos: Vector2 = tc._buttons["sprint"]["pos"]
	_touch(1, run_pos, true)
	_touch(1, run_pos, false)
	await wait(1.2)
	check(player.is_sprinting, "RUN toggles sprinting (second finger)", "speed %.1f" % player._speed)
	# look with a third finger: drag on the right half turns the camera
	var yaw0 := world.camera.rotation.y
	var look := Vector2(size.x * 0.62, size.y * 0.3)
	_touch(2, look, true)
	_drag(2, look + Vector2(120.0, 0.0), Vector2(120.0, 0.0))
	await wait(0.1)
	check(absf(angle_difference(yaw0, world.camera.rotation.y)) > 0.1, "dragging the right side turns the camera",
		"%.2f rad" % angle_difference(yaw0, world.camera.rotation.y))
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.9, "looking does not disturb the stick")
	_touch(2, look, false)
	# releasing the stick stops the deer and ends the run
	_touch(0, base, false)
	await wait(1.0)
	check(player._speed < 0.3 and not Input.is_action_pressed("sprint"), "releasing the stick stops the deer and the run", "speed %.2f" % player._speed)
	# JUMP
	var y0 := player.global_position.y
	var jump_pos: Vector2 = tc._buttons["jump"]["pos"]
	_touch(0, jump_pos, true)
	var top := y0
	for i in 40:
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	_touch(0, jump_pos, false)
	check(top > y0 + 0.5, "JUMP button jumps", "+%.2f m" % (top - y0))
	check(not Input.is_action_pressed("jump"), "JUMP is a single tap, not held")
	await wait(0.8)
	# EAT is a hold button
	var eat_pos: Vector2 = tc._buttons["interact"]["pos"]
	_touch(0, eat_pos, true)
	await wait(0.1)
	var held := Input.is_action_pressed("interact")
	_touch(0, eat_pos, false)
	await wait(0.1)
	check(held and not Input.is_action_pressed("interact"), "EAT is held while the finger is down")
	# SNEAK toggle
	var sneak_pos: Vector2 = tc._buttons["sneak"]["pos"]
	_touch(0, sneak_pos, true)
	_touch(0, sneak_pos, false)
	await wait(0.2)
	check(Input.is_action_pressed("sneak"), "SNEAK toggles on")
	_touch(0, sneak_pos, true)
	_touch(0, sneak_pos, false)
	await wait(0.2)
	check(not Input.is_action_pressed("sneak"), "SNEAK toggles off")
	# pinch zoom with two fingers on the right
	var d0: float = world.camera._distance
	_touch(3, Vector2(size.x * 0.55, size.y * 0.3), true)
	_touch(4, Vector2(size.x * 0.75, size.y * 0.3), true)
	_drag(4, Vector2(size.x * 0.65, size.y * 0.3), Vector2(-size.x * 0.1, 0.0))
	await wait(0.1)
	check(world.camera._distance > d0 + 0.3, "pinching in zooms the camera out", "%.1f -> %.1f m" % [d0, world.camera._distance])
	_touch(3, Vector2.ZERO, false)
	_touch(4, Vector2.ZERO, false)
	world.camera._distance = d0
	# pause button, and everything is let go while paused
	_touch(0, base, true)
	_drag(0, base + Vector2(0.0, -130.0), Vector2(0.0, -130.0))
	await wait(0.2)
	var pause_pos: Vector2 = tc._buttons["pause"]["pos"]
	_touch(1, pause_pos, true)
	_touch(1, pause_pos, false)
	await wait(0.3)
	check(main.flow == 3 and get_tree().paused, "pause button opens the pause menu")
	check(not Input.is_action_pressed("move_forward"), "pausing releases the stick")
	main.resume()
	await wait(0.3)
	check(main.flow == 2, "game resumes")
	Settings.set_value("controls", "touch_controls", 0, false)
	await wait(0.1)
	check(not tc.is_active() and not Input.emulate_touch_from_mouse, "touch controls can be switched off again")
	release_all()


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
	check(world.predators.predators.size() == PredatorManager.ROSTER_SIZE, "predators reset", world.predators.predators.size())
	check(Vector2(player.global_position.x, player.global_position.z).distance_to(world.data.spawn_point) < 2.0, "deer back at the spawn")
	# killed by a predator -> correct cause
	player.take_damage(500.0, "Tiger")
	await wait(3.5)
	check(GameState.cause_of_death == "Tiger" and main.flow == 4, "predator kill reported on game over")
	main.menus.menu_requested.emit()
	await wait(0.3)
	check(main.flow == 1 and main.menus.current_screen() == "main" and not player.is_dead(), "main menu reachable from game over")
	check(world.grass.pooled_reuses > 0, "grass cells are pooled and reused", world.grass.pooled_reuses)


func _count(kind: String) -> int:
	var n := 0
	for p in world.predators.predators:
		if p.species == kind:
			n += 1
	return n


func _prey_count(kind: String) -> int:
	var n := 0
	for a in world.prey.animals:
		if a.kind == kind:
			n += 1
	return n


## The expansion: levels, random spawn, slow start + speed plants, abilities, night vision, weather,
## new animals and birds, icon HUD, window settings, more convincing attacks.
func test_expansion() -> void:
	print("\n-- expansion: HUD icons")
	var hud: HUD = main.hud
	var kinds: PackedStringArray = []
	for key: String in ["health", "stamina", "hunger", "thirst"]:
		kinds.append((hud._icons[key] as HudIcon).kind)
	check(kinds == PackedStringArray(["heart", "bolt", "leaf", "drop"]), "stats use heart / bolt / leaf / drop icons", kinds)
	check(hud._root.find_children("*", "HudIcon", true, false).size() >= 14, "icons for stats, abilities, goal and weather", hud._root.find_children("*", "HudIcon", true, false).size())
	check(hud._ability_icons.size() == GameState.ABILITIES.size(), "one HUD icon per ability", hud._ability_icons.size())

	print("\n-- expansion: window")
	check(int(ProjectSettings.get_setting("display/window/size/mode")) == 0 and bool(ProjectSettings.get_setting("display/window/size/resizable"))
		and not bool(ProjectSettings.get_setting("display/window/size/borderless")), "game starts in a resizable window with a title bar")
	check(int(ProjectSettings.get_setting("display/window/size/window_width_override")) == 1280, "window opens smaller than a 1080p screen", ProjectSettings.get_setting("display/window/size/window_width_override"))
	check(Settings.DEFAULTS["graphics"].has("window_mode") and int(Settings.DEFAULTS["graphics"]["window_mode"]) == 0, "window mode setting defaults to windowed")
	var wm := int(Settings.get_value("graphics", "window_mode"))
	Settings.toggle_fullscreen()
	check(int(Settings.get_value("graphics", "window_mode")) == 2, "F11 toggle selects fullscreen")
	Settings.toggle_fullscreen()
	check(int(Settings.get_value("graphics", "window_mode")) == 0, "F11 toggle returns to the window")
	Settings.set_value("graphics", "window_mode", wm, false)
	check(main.menus.settings.find_children("*", "OptionButton", true, false).size() >= 3, "settings menu has the window mode option")

	print("\n-- expansion: low-end options")
	var preset0 := int(Settings.get_value("graphics", "preset"))
	Settings.set_value("graphics", "preset", 0, false)
	check(not bool(Settings.get_value("graphics", "animal_shadows")) and not bool(Settings.get_value("graphics", "ssao"))
		and float(Settings.get_value("graphics", "render_scale")) < 0.7, "Low preset: no animal shadows, no SSAO, reduced render scale")
	check(world.weather._max_drops <= 500, "Low preset: fewer rain particles", world.weather._max_drops)
	Settings.set_value("graphics", "preset", preset0, false)
	check(Settings.guess_preset() >= 0 and Settings.guess_preset() <= 2, "hardware guess picks a preset", Settings.guess_preset())

	print("\n-- expansion: levels, random spawn, slow start")
	GameState.test_mode = false
	check(GameState.LEVELS.size() >= 8, "eight campaign levels", GameState.LEVELS.size())
	var harder := true
	for i in range(1, GameState.LEVELS.size()):
		var a: Dictionary = GameState.LEVELS[i - 1]
		var b: Dictionary = GameState.LEVELS[i]
		harder = harder and float(b["speed"]) >= float(a["speed"]) and float(b["damage"]) >= float(a["damage"]) and float(b["minutes"]) >= float(a["minutes"])
	check(harder, "levels get longer and the hunters faster and stronger")
	GameState.new_campaign()
	var spawns: Array = []
	for run in 3:
		main.start_game()
		await wait(0.3)
		var sp := Vector2(player.global_position.x, player.global_position.z)
		spawns.append(sp)
		check(world.data.is_walkable(sp.x, sp.y) and world.data.water_depth(sp.x, sp.y) <= 0.0, "random spawn %d is on dry walkable ground" % run, sp)
		var near := INF
		for p in world.predators.predators:
			near = minf(near, p.global_position.distance_to(player.global_position))
		check(near > 40.0, "no hunter next to random spawn %d" % run, "%.0f m" % near)
	check((spawns[0] as Vector2).distance_to(spawns[1]) > 5.0 or (spawns[1] as Vector2).distance_to(spawns[2]) > 5.0, "the deer starts somewhere different each game", spawns)
	check(GameState.level == 0 and _count("lion") >= 1 and _count("tiger") >= 1 and _count("cheetah") >= 1 and _count("hyena") >= 2 and _count("crocodile") >= 1,
		"level 1 has every big cat, hyenas and crocodiles", "%d lion %d tiger %d cheetah %d hyena %d croc" % [_count("lion"), _count("tiger"), _count("cheetah"), _count("hyena"), _count("crocodile")])
	var lvl1 := world.predators.predators.size()
	var shore := true
	var croc_info: PackedStringArray = []
	for p in world.predators.predators:
		if p.species == "crocodile":
			var wd := world.data.water_distance(p.global_position.x, p.global_position.z)
			croc_info.append("%.1f m" % wd)
			shore = shore and wd < 8.0
	check(shore, "crocodiles lie at the water's edge", croc_info)
	for kind: String in ["gazelle", "boar", "goat", "buffalo", "fox", "junglefowl"]:
		check(_prey_count(kind) >= 3, "%s live in the jungle" % kind, _prey_count(kind))
	check(_prey_count("boar") >= 20, "plenty of boar", _prey_count("boar"))
	var boar_near := 0
	for a2 in world.prey.animals:
		if a2.kind == "boar" and a2.global_position.distance_to(player.global_position) < 70.0:
			boar_near += 1
	check(boar_near >= 2, "boar root about near where the deer starts", boar_near)
	for a3 in world.prey.animals:
		if a3.rig.anim == null or not a3.rig.has("Walk"):
			check(false, "%s model animates" % a3.kind)
			break
	check(absf(player.speed_mult - GameState.SWIFT_START) < 0.001, "a new deer starts slow", player.speed_mult)
	world.predators.process_mode = Node.PROCESS_MODE_DISABLED
	# measured sprint speed, slow deer
	var s := open_spot(1)
	teleport(s.x, s.y)
	restore_stats()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait(2.0)
	var slow := player.horizontal_speed()
	release_all()
	await wait(0.5)
	check(slow < Player.SPRINT_SPEED * 0.86 and slow > Player.SPRINT_SPEED * 0.7, "starting sprint is clearly slower", "%.1f m/s" % slow)

	print("\n-- expansion: rare plants and abilities")
	var forage := world.forage
	var per_kind := {}
	var dry := true
	for it in forage.items:
		per_kind[it["kind"]] = int(per_kind.get(it["kind"], 0)) + 1
		var ip: Vector3 = it["pos"]
		dry = dry and world.data.is_walkable(ip.x, ip.z) and world.data.water_depth(ip.x, ip.z) <= 0.0
	check(per_kind.size() == Forage.KINDS.size() and forage.items.size() > 60, "every kind of rare plant grows", per_kind)
	check(dry, "all rare plants are on dry reachable ground")
	var moon := forage.nearest(player.global_position, 2000.0, "moonpetal")
	var start_moon := forage.nearest(Vector3(world.data.run_spawn.x, 0.0, world.data.run_spawn.y), 2000.0, "moonpetal")
	check(Vector2(start_moon["pos"].x, start_moon["pos"].z).distance_to(world.data.run_spawn) < 90.0, "a Moonpetal grows within reach of the start")
	# --- minimap: plants stay hidden until the deer has found them
	print("\n-- expansion: minimap")
	check(hud.minimap != null and hud.minimap.texture != null and hud.minimap.texture.get_width() == 512, "minimap has a picture of the world")
	check(hud.minimap.is_visible_in_tree() and _on_screen(hud.minimap) and hud.minimap.get_global_rect().position.x > hud._root.size.x * 0.7, "minimap sits top right, on screen", hud.minimap.get_global_rect())
	check(not hud.minimap.get_global_rect().intersects(hud._notes.get_global_rect()), "notifications sit below the minimap")
	var water_px := world.map_texture.get_image().get_pixelv(Vector2i(WorldMap.to_uv(-285.0, -170.0) * 512.0))
	check(water_px.b > water_px.g and water_px.b > water_px.r, "lake is drawn blue on the map", water_px)
	teleport(s.x, s.y)
	for it0 in forage.items:
		it0["seen"] = false
	GameState.discoveries.clear()
	await wait(0.5)
	var far_clover := forage.nearest(player.global_position, 2000.0, "clover")
	var plant_marks := func() -> int:
		var n := 0
		for m in hud.minimap.markers():
			if m["shape"] == "dot":
				n += 1
		return n
	var seen_near := 0
	for it1 in forage.items:
		if it1["seen"]:
			seen_near += 1
	check(plant_marks.call() == seen_near and seen_near < 4, "undiscovered rare plants are not on the map", "%d marked of %d plants" % [plant_marks.call(), forage.items.size()])
	check(hud.minimap.markers().filter(func(m: Dictionary) -> bool: return m["shape"] == "ring").is_empty(), "undiscovered thickets are not on the map")
	var fp: Vector3 = far_clover["pos"]
	teleport(fp.x + 15.0, fp.z)
	await wait(0.6)
	check(far_clover["seen"] and plant_marks.call() >= 1, "a rare plant appears on the map once the deer comes near it", plant_marks.call())
	var named := false
	for m2 in hud.minimap.markers():
		named = named or m2["name"] == "Swift Clover"
	check(named, "the marker knows which plant it is")
	var g0: Dictionary = world.data.groves[0]
	teleport(g0["center"].x, g0["center"].y)
	await wait(0.7)
	check(hud.minimap.markers().filter(func(m: Dictionary) -> bool: return m["shape"] == "ring").size() == 1, "a safe thicket is marked after it is discovered")
	Input.action_press("map")
	await wait(0.2)
	Input.action_release("map")
	check(hud.is_full_map_open() and _on_screen(hud._map_box) and hud.full_map.size.x > 230.0, "M opens the full map, on screen", hud._map_box.get_global_rect())
	Input.action_press("map")
	await wait(0.2)
	Input.action_release("map")
	check(not hud.is_full_map_open(), "M closes it again")
	var fixed_before: Array = []
	for i in forage.fixed_count:
		fixed_before.append(forage.items[i]["pos"])
	check(forage.fixed_count > 60, "most rare plants have fixed places", forage.fixed_count)
	# walk up to a clover and eat it with the interact key
	var clover := forage.nearest(player.global_position, 2000.0, "clover")
	var cp: Vector3 = clover["pos"]
	teleport(cp.x + 1.0, cp.z)
	await wait(0.3)
	check(player.interaction_hint().contains("Swift Clover"), "prompt appears next to a rare plant", player.interaction_hint())
	Input.action_press("interact")
	await wait(0.4)
	release_all()
	check(not hud.minimap.markers().any(func(m: Dictionary) -> bool: return m["shape"] == "dot" and (m["pos"] as Vector2).distance_to(Vector2(cp.x, cp.z)) < 0.5), "an eaten plant leaves the map")
	check(clover["eaten"] and GameState.stacks("swift") == 1 and player.speed_mult > GameState.SWIFT_START + 0.03, "eating Swift Clover makes the deer faster", player.speed_mult)
	check(GameState.plants_found == 1, "rare plant counted toward the level goal", GameState.plants_found)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	teleport(s.x, s.y)
	player.stamina = player.max_stamina
	await wait(2.0)
	var faster := player.horizontal_speed()
	release_all()
	await wait(0.4)
	check(faster > slow + 0.25, "sprint really is faster after the clover", "%.2f -> %.2f m/s" % [slow, faster])
	for i in 20:
		GameState.grant("swift")
	player.apply_abilities(false)
	check(player.speed_mult <= GameState.SWIFT_START + GameState.SWIFT_STEP * GameState.SWIFT_MAX + 0.001 and player.speed_mult > 1.2, "speed gain is capped", player.speed_mult)
	# night vision
	var dn := world.day_night
	dn.set_time(0.5)
	await wait(1.5)
	var dark := dn.env.ambient_light_energy * dn.env.ambient_light_color.get_luminance() * lerpf(1.0, 0.1, dn.env.ambient_light_sky_contribution)
	forage.eat(moon, player)
	await wait(2.5)
	check(GameState.has_ability("night_vision") and dn.env.ambient_light_energy * dn.env.ambient_light_color.get_luminance() * lerpf(1.0, 0.1, dn.env.ambient_light_sky_contribution) > dark * 4.0
		and dn.env.ambient_light_energy < 1.2, "Moonpetal unlocks night vision (clearly brighter nights, not washed out)",
		"ambient light %.3f -> %.3f" % [dark, dn.env.ambient_light_energy * dn.env.ambient_light_color.get_luminance() * lerpf(1.0, 0.1, dn.env.ambient_light_sky_contribution)])
	dn.set_time(12.0)
	await wait(0.3)
	var noon_amb := dn.env.ambient_light_energy
	check(noon_amb < 0.7, "night vision does not wash out the day", noon_amb)
	# the other gifts
	var mh := player.max_health
	forage.eat(forage.nearest(player.global_position, 2000.0, "ironbark"), player)
	check(player.max_health == mh + 10.0 and GameState.has_ability("iron_hide"), "Ironbark raises max health")
	var ms := player.max_stamina
	forage.eat(forage.nearest(player.global_position, 2000.0, "sunberry"), player)
	check(player.max_stamina == ms + 10.0, "Sunberry raises max stamina")
	forage.eat(forage.nearest(player.global_position, 2000.0, "ghostfern"), player)
	check(player.noise_mult < 0.6, "Ghost Fern quiets the deer", player.noise_mult)
	forage.eat(forage.nearest(player.global_position, 2000.0, "springlily"), player)
	check(player.jump_mult > 1.2, "Spring Lily gives a higher jump", player.jump_mult)
	forage.eat(forage.nearest(player.global_position, 2000.0, "lotus"), player)
	check(player.swim_mult > 1.5, "Lotus Root gives fast swimming", player.swim_mult)
	forage.eat(forage.nearest(player.global_position, 2000.0, "owlcap"), player)
	check(GameState.has_ability("keen_senses"), "Owl-eye Mushroom gives keen senses")
	player.health = 30.0
	forage.eat(forage.nearest(player.global_position, 2000.0, "herb"), player)
	check(player.health >= 74.0, "Healing Herb heals", player.health)
	player.hunger = 20.0
	forage.eat(forage.nearest(player.global_position, 2000.0, "honey"), player)
	check(player.hunger >= 99.0, "Honeycomb fills the stomach", player.hunger)
	var found := GameState.plants_found
	forage.eat(forage.nearest(player.global_position, 2000.0, "toadstool"), player)
	var hp := player.health
	await wait(2.0)
	check(player.poisoned > 0.0 and player.health < hp and GameState.plants_found == found, "Red Toadstool poisons and does not count", "%.1f -> %.1f" % [hp, player.health])
	player.poisoned = 0.0
	await wait(0.3)
	var lit := 0
	for id: String in hud._ability_icons:
		if not (hud._ability_icons[id] as HudIcon).dim:
			lit += 1
	check(lit == GameState.ABILITIES.size(), "HUD lights up every unlocked ability", lit)

	print("\n-- expansion: weather")
	var w := world.weather
	restore_stats()
	dn.set_time(12.0)
	w.auto = false
	w.set_state(Weather.State.CLEAR, true)
	await wait(0.3)
	var sun_clear := dn.sun.light_energy
	var fog_clear := dn.env.fog_density
	check(not w._rain.emitting and not w.is_raining() and w.sense_factor() == 1.0, "clear sky: no rain")
	w.set_state(Weather.State.RAIN, true)
	await wait(0.5)
	check(w._rain.emitting and w._splash.emitting and w.is_raining(), "rain falls", "rain %.2f" % w.rain)
	check(dn.sun.light_energy < sun_clear * 0.6 and dn.env.fog_density > fog_clear * 1.8, "rain darkens the sky and thickens the air",
		"sun %.2f -> %.2f, fog %.4f -> %.4f" % [sun_clear, dn.sun.light_energy, fog_clear, dn.env.fog_density])
	check(w._loop.playing and w._loop.volume_db > -20.0, "rain can be heard", w._loop.volume_db)
	check(float(dn.sky_material.get_shader_parameter("cloud_cover")) > 0.9, "sky clouds over")
	check(w.sense_factor() < 0.85 and world.predators.sense_factor() < 0.85, "rain blunts the hunters' senses", w.sense_factor())
	player.thirst = 50.0
	GameState.in_game = true
	await wait(3.0)
	check(player.thirst > 50.0 - 0.235 * player.drain_mult * 3.0 + 0.1, "rain slows thirst", player.thirst)
	w.set_state(Weather.State.STORM, true)
	w.strike()
	await get_tree().process_frame
	await get_tree().process_frame
	check(w.flash > 0.5 and dn.flash > 0.5, "lightning flashes in a storm", w.flash)
	check((w._loop.stream as AudioStreamWAV).data.size() > 100000, "rain sound generated", (w._loop.stream as AudioStreamWAV).data.size())
	w.set_state(Weather.State.CLEAR, true)
	await wait(0.4)
	check(not w._rain.emitting and absf(dn.sun.light_energy - sun_clear) < 0.05, "weather clears again")
	w.auto = true
	w.storminess = 1.0
	w._timer = 0.1
	await wait(0.5)
	check(w.state != Weather.State.CLEAR, "weather changes by itself over time", w.state_name())
	w.auto = false
	w.set_state(Weather.State.CLEAR, true)

	print("\n-- expansion: birds")
	var birds := world.birds
	check(birds.count("hawk") >= 4 and birds.count("crow") >= 12, "hawks and crows in the sky", "%d hawks, %d crows" % [birds.count("hawk"), birds.count("crow")])
	var b0: Vector3 = (birds.birds[0]["node"] as Node3D).position
	await wait(1.0)
	var b1: Vector3 = (birds.birds[0]["node"] as Node3D).position
	check(b0.distance_to(b1) > 3.0 and b1.y > world.data.height_at(b1.x, b1.z) + 20.0, "birds fly, high above the ground", "moved %.1f m, altitude %.0f m" % [b0.distance_to(b1), b1.y - world.data.height_at(b1.x, b1.z)])
	check(((birds.birds[0]["rig"] as AnimalRig).anim != null), "bird models animate")
	birds.gather_over(Vector3(s.x, 0.0, s.y))
	var gathering := 0
	for b in birds.birds:
		if b.has("visit"):
			gathering += 1
	check(gathering == 5, "a crow flock gathers above a kill", gathering)

	print("\n-- expansion: new hunters and attacks")
	world.predators.process_mode = Node.PROCESS_MODE_INHERIT
	world.predators.allow_hunts = false
	# a lion next to a deer that stands still must close in, strike, and keep moving between strikes
	var lion := _first("lion")
	await _setup_encounter(lion, 14.0)
	lion.awareness = 1.0
	lion.last_known = player.global_position
	lion._on_detected()
	var start := lion.global_position
	var hits := 0
	var path_len := 0.0
	var prev := lion.global_position
	var max_lift := 0.0
	var hp0 := player.health
	for i in 60 * 9:
		await get_tree().physics_frame
		path_len += lion.global_position.distance_to(prev)
		prev = lion.global_position
		max_lift = maxf(max_lift, lion.rig.lift)
		if player.health < hp0 - 1.0:
			hits += 1
			hp0 = player.health
			player.health = player.max_health
			hp0 = player.health
	check(hits >= 2, "lion reaches a standing deer and strikes repeatedly", "%d hits in 9 s" % hits)
	check(path_len > 14.0 + 3.0, "lion keeps prowling between strikes instead of standing still", "path %.1f m" % path_len)
	check(max_lift > 0.15, "the strike is a visible leap", max_lift)
	restore_stats()
	# idle hunters come looking for the deer
	isolate()
	var roamer_src := _first("tiger")
	roamer_src.process_mode = Node.PROCESS_MODE_INHERIT
	place(roamer_src, s.x + 150.0, s.y)
	teleport(s.x, s.y)
	var d_before := roamer_src.global_position.distance_to(player.global_position)
	var roamer := world.predators.send_roamer()
	check(roamer == roamer_src and roamer.has_target and Vector2(roamer.move_target.x, roamer.move_target.z).distance_to(Vector2(s.x, s.y)) < 50.0,
		"an idle hunter is sent prowling toward the deer's area", "from %.0f m" % d_before)
	check(world.predators.roam_interval > 20.0, "hunters roam toward the deer on a timer", world.predators.roam_interval)
	place(roamer_src, -430.0, -400.0)
	roamer_src.process_mode = Node.PROCESS_MODE_DISABLED
	# crocodile ambush
	var croc := _first("crocodile")
	check(croc != null and croc.rig.anim != null and croc.rig.has("Walk"), "crocodile exists and animates")
	await _setup_encounter(croc, 7.0, 1, true)
	hp0 = player.health
	await wait(6.0)
	check(player.health < hp0, "crocodile lunges at a deer that comes close", "%.0f -> %.0f, state %s" % [hp0, player.health, croc.state_name()])
	restore_stats()
	place(croc, -400.0, -400.0)
	# wolves (level 3 onward)
	GameState.level = 2
	main.start_game()
	await wait(0.3)
	var same := world.forage.fixed_count == fixed_before.size()
	for i in mini(world.forage.fixed_count, fixed_before.size()):
		same = same and (world.forage.items[i]["pos"] as Vector3).distance_to(fixed_before[i]) < 0.01
	check(same, "rare plants grow in the same places every game and level (the printed map stays true)")
	check(_count("wolf") >= 3 and world.predators.predators.size() > lvl1, "wolves join from level 3 and the roster grows", "%d wolves, %d hunters (level 1: %d)" % [_count("wolf"), world.predators.predators.size(), lvl1])
	check(GameState.stacks("swift") >= 1 and player.speed_mult > 1.2 and GameState.has_ability("night_vision"), "gifts are kept from level to level", player.speed_mult)
	var wolf := _first("wolf")
	check(absf(wolf.run_speed - 10.6 * 0.95) < 0.01, "level difficulty scales hunter speed", wolf.run_speed)
	await _setup_encounter(wolf, 20.0)
	wolf.awareness = 1.0
	wolf.last_known = player.global_position
	wolf._on_detected()
	hp0 = player.health
	await wait(6.0)
	check(player.health < hp0, "wolf runs the deer down and bites", "%.0f -> %.0f" % [hp0, player.health])
	restore_stats()
	isolate()
	# wildlife spotting: look straight at a tiger
	var tiger := _first("tiger")
	check(tiger != null, "tiger is in the level")
	teleport(s.x, s.y)
	place(tiger, s.x, s.y - 12.0)
	tiger.process_mode = Node.PROCESS_MODE_DISABLED
	world.camera.rotation.y = 0.0
	world.camera.snap_to_target()
	GameState.spotted.erase("Tiger")
	var boar := _prey_of("boar")
	_place_prey(boar, s.x + 3.0, s.y - 10.0)
	GameState.spotted.erase("Boar")
	await wait(1.2)
	check(GameState.spotted.has("Tiger"), "seeing a tiger is recorded (wildlife spotted)", GameState.spotted.keys())
	check(GameState.spotted.has("Boar"), "seeing a boar is recorded", GameState.spotted.keys())
	place(tiger, -420.0, -420.0)

	print("\n-- expansion: level completion")
	restore_stats()
	GameState.level = 0
	main.start_game()
	await wait(0.3)
	world.predators.process_mode = Node.PROCESS_MODE_DISABLED
	check(hud._goal_title.text.begins_with("Level 1") and hud._goal_plants.text.contains("/ 2"), "HUD shows the level goal", "%s | %s | %s" % [hud._goal_title.text, hud._goal_time.text, hud._goal_plants.text])
	GameState.time_survived = GameState.goal_seconds() + 1.0
	await wait(0.3)
	check(main.flow == 2, "time alone does not finish a level")
	GameState.plants_found = 2
	await wait(0.3)
	check(main.flow == 5 and main.menus.current_screen() == "won" and GameState.unlocked >= 1, "goal met: level complete screen, next level unlocked", main.menus.current_screen())
	main.menus.next_level_requested.emit()
	await wait(0.4)
	check(main.flow == 2 and GameState.level == 1 and GameState.plants_found == 0 and GameState.time_survived < 2.0, "next level starts fresh", "level %d" % (GameState.level + 1))
	check(absf(world.day_night.time_of_day - float(GameState.LEVELS[1]["start"])) < 0.2, "level sets its own time of day", world.day_night.time_of_day)
	# the last level is far harder than the first
	GameState.level = GameState.LEVELS.size() - 1
	main.start_game()
	await wait(0.4)
	world.predators.process_mode = Node.PROCESS_MODE_DISABLED
	check(world.predators.predators.size() >= lvl1 * 4 and _first("lion").attack_damage > 34.0 * 1.5, "final level: many more, much stronger hunters",
		"%d hunters, lion damage %.0f" % [world.predators.predators.size(), _first("lion").attack_damage])
	GameState.time_survived = GameState.goal_seconds() + 1.0
	GameState.plants_found = 99
	await wait(0.3)
	check(main.flow == 5 and main.menus._won_title.text.contains("RULE"), "beating the last level ends the campaign")
	# endless mode still works and keeps the classic cast
	main.menus.menu_requested.emit()
	await wait(0.3)
	GameState.set_mode(GameState.Mode.ENDLESS)
	main.start_game()
	await wait(0.3)
	check(GameState.mode == GameState.Mode.ENDLESS and _count("lion") == 5 and _count("tiger") == 5 and _count("cheetah") == 4 and _count("hyena") == 8
		and _count("wolf") == 3 and _count("crocodile") >= 3, "endless survival keeps the full classic roster plus wolves and crocodiles", world.predators.predators.size())
	check(GameState.abilities.is_empty() and absf(player.speed_mult - GameState.SWIFT_START) < 0.001, "endless run starts without gifts")
	GameState.set_mode(GameState.Mode.CAMPAIGN)
	check(GameState.has_ability("night_vision"), "campaign gifts are kept while playing endless")
	main.menus.menu_requested.emit()
	await wait(0.3)
	GameState.test_mode = true


## WS_MAP=<folder>: write the world picture (1 pixel per metre) and the positions of everything on
## it, for drawing the full "everything visible" map outside the game.
func export_map(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	WorldMap.build_image(world.data, 1024).save_png(dir.path_join("base.png"))
	world.forage.scatter(world.data.spawn_point)
	var plants: Array = []
	for i in world.forage.fixed_count:
		var it: Dictionary = world.forage.items[i]
		plants.append({"kind": it["kind"], "name": it["name"], "x": it["pos"].x, "z": it["pos"].z})
	var out := {"plants": plants, "groves": [], "pois": [], "lakes": [], "clearings": []}
	for g in world.data.groves:
		out["groves"].append({"name": g["name"], "x": g["center"].x, "z": g["center"].y})
	for p in world.data.pois:
		out["pois"].append({"name": p["name"], "type": p["type"], "x": p["pos"].x, "z": p["pos"].y})
	for l in world.data.lakes:
		out["lakes"].append({"name": l["name"], "x": l["center"].x, "z": l["center"].y})
	for c in world.data.clearings:
		out["clearings"].append({"x": c["center"].x, "z": c["center"].y})
	var colors := {}
	for k: String in WorldMap.PLANT_COLORS:
		colors[k] = (WorldMap.PLANT_COLORS[k] as Color).to_html(false)
	out["colors"] = colors
	var f := FileAccess.open(dir.path_join("map.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[info] map exported to ", dir)
