extends Node

## Plays the project's locally generated ElevenLabs MP3s. No network access is
## needed in-game. Every cue is independently optional during development.

const AUDIO_DIRECTORY := "res://audio/generated/"
const LOOPS := ["wind", "crosswind", "heater", "engine", "plow"]
# Playback gain for each recording in dB. The horn leads the mechanical cues;
# the CB click and squelch sit closer to the cab ambience.
const ONE_SHOT_LEVELS := {
	"radio_key": -6.0,
	"radio_squelch": -17.0,
	"horn": -15.0,
	"door": -5.0,
	"blade_lift": -8.0,
	"blade_drop": -6.0,
	"tow_chain": -11.0,
	"mailbox": -10.0,
}

var _players: Dictionary = {}
var _levels: Dictionary = {}
var _in_cab := true
var _speed := 0.0
var _working := false
var _gust := 0.0
var _wind_bus: StringName
var _wind_filter: AudioEffectLowPassFilter


func _ready() -> void:
	# Only exterior wind passes through the closed cab; the heater and CB stay clear.
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, "Storm wind %d" % get_instance_id())
	_wind_bus = AudioServer.get_bus_name(bus_index)
	_wind_filter = AudioEffectLowPassFilter.new()
	_wind_filter.cutoff_hz = 1150.0
	AudioServer.add_bus_effect(bus_index, _wind_filter)
	for cue: String in LOOPS:
		var player := _make_player(cue, true)
		if player:
			if cue == "wind" or cue == "crosswind":
				player.bus = _wind_bus
			player.volume_db = -80.0
			_levels[cue] = 0.0
	for cue: String in ONE_SHOT_LEVELS:
		var player := _make_player(cue, false)
		if player:
			player.volume_db = ONE_SHOT_LEVELS[cue]
	set_process(false)


func _make_player(cue: String, looping: bool) -> AudioStreamPlayer:
	var path := AUDIO_DIRECTORY + cue + ".mp3"
	var stream: AudioStreamMP3
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStreamMP3
	elif FileAccess.file_exists(path):
		# Also allow a fresh generation to play before the editor's first import.
		stream = AudioStreamMP3.load_from_file(path)
	if stream == null:
		return null
	stream.loop = looping
	var player := AudioStreamPlayer.new()
	player.name = cue
	player.stream = stream
	add_child(player)
	_players[cue] = player
	return player


func update_state(in_cab: bool, speed_mps: float, working_snow: bool) -> void:
	_in_cab = in_cab
	_speed = clampf(absf(speed_mps) / 11.0, 0.0, 1.0)
	_working = working_snow
	if not is_processing() and not _levels.is_empty():
		for cue: String in _levels:
			_players[cue].play()
		set_process(true)


func set_gust(strength: float) -> void:
	_gust = clampf(strength, 0.0, 1.0)


func shutdown() -> void:
	set_process(false)
	for player: AudioStreamPlayer in _players.values():
		player.stop()
		player.stream = null
	_players.clear()
	_levels.clear()
	if _wind_filter:
		var index := AudioServer.get_bus_index(_wind_bus)
		if index > 0:
			AudioServer.remove_bus(index)
		_wind_filter = null


func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-delta * 5.0)
	var drift := smoothstep(0.15, 0.9, _gust)
	_wind_filter.cutoff_hz = lerpf(_wind_filter.cutoff_hz, 1150.0 if _in_cab else 16000.0, blend)
	# The gust recording measures 26 LU louder than the open-field wind.
	var wind_db := lerpf(-9.0, -6.0, drift) if _in_cab else lerpf(-2.5, 0.5, drift)
	var gust_db := lerpf(-45.0, -27.0, drift) if _in_cab else lerpf(-34.0, -16.0, drift)
	_mix("wind", wind_db, blend)
	_mix("crosswind", gust_db, blend)
	# Lift the quiet fan into the idle mix and let the scrape take the lead under load.
	_mix("heater", 6.0 if _in_cab else -INF, blend)
	_mix("engine", lerpf(-17.0, -13.0, _speed) if _in_cab else -27.0, blend)
	_mix("plow", lerpf(-11.0, -8.5, _speed) if _working else -INF, blend)
	var engine := _players.get("engine") as AudioStreamPlayer
	if engine:
		engine.pitch_scale = lerpf(engine.pitch_scale, 0.92 + 0.45 * _speed, blend)


func _mix(cue: String, target_db: float, blend: float) -> void:
	var player := _players.get(cue) as AudioStreamPlayer
	if player:
		var level := lerpf(float(_levels[cue]), db_to_linear(target_db), blend)
		_levels[cue] = level
		player.volume_db = linear_to_db(maxf(level, 0.0001))


func play_cue(cue: String) -> void:
	var player := _players.get(cue) as AudioStreamPlayer
	if player and ONE_SHOT_LEVELS.has(cue):
		player.play()
