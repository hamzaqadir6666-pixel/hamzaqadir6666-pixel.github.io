extends Node
## Central audio: bus layout, music cross-fades, pooled one-shot 2D/3D sound players.

const MUSIC := {
	"menu": "res://audio/music/menu.ogg",
	"day": "res://audio/music/day.ogg",
	"night": "res://audio/music/night.ogg",
	"chase": "res://audio/music/chase.ogg",
	"gameover": "res://audio/music/gameover.ogg",
}
const POOL_3D := 20
const POOL_2D := 8

var _music_players: Array[AudioStreamPlayer] = []
var _music_active := 0
var _music_track := ""
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}
var _next3d := 0
var _next2d := 0


func _enter_tree() -> void:
	# Buses must exist before Settings applies volumes.
	for bus_name: String in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.35
		rev.damping = 0.7
		rev.wet = 0.08
		rev.dry = 1.0
		AudioServer.add_bus_effect(sfx, rev)
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectLimiter.new()
		AudioServer.add_bus_effect(master, lim)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_music_players.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.attenuation_filter_cutoff_hz = 9000.0
		add_child(p3)
		_pool3d.append(p3)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "SFX"
		add_child(p2)
		_pool2d.append(p2)
	Settings.apply_all()


func stream(path: String) -> AudioStream:
	if not _cache.has(path):
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s == null:
			push_warning("Missing audio: %s" % path)
		_cache[path] = s
	return _cache[path]


func looped(path: String) -> AudioStream:
	var s := stream(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return s


## Cross-fade to a music track ("" fades out).
func play_music(track: String, fade := 2.5, volume_db := -8.0) -> void:
	if track == _music_track:
		return
	_music_track = track
	var old := _music_players[_music_active]
	_music_active = 1 - _music_active
	var cur := _music_players[_music_active]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "volume_db", -60.0, fade)
	tw.chain().tween_callback(old.stop)
	if track != "" and MUSIC.has(track):
		cur.stream = looped(MUSIC[track])
		cur.volume_db = -60.0
		cur.play()
		var tw2 := create_tween()
		tw2.tween_property(cur, "volume_db", volume_db, fade)


func current_music() -> String:
	return _music_track


## Pooled positional one-shot.
func play_at(path: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, unit_size := 8.0, max_distance := 90.0, bus := "SFX") -> void:
	var s := stream(path)
	if s == null:
		return
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.bus = bus
	p.play()


func play_ui(path: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := stream(path)
	if s == null:
		return
	var p := _pool2d[_next2d]
	_next2d = (_next2d + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func click() -> void:
	play_ui("res://audio/ui/click.ogg", -6.0)


func hover() -> void:
	play_ui("res://audio/ui/hover.ogg", -14.0)
