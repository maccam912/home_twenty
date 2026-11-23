extends SceneTree

const Soundscape := preload("res://audio/soundscape.gd")
const REQUIRED_CUES := ["wind", "crosswind", "heater", "engine", "plow", "radio_key",
		"radio_squelch", "horn", "door", "blade_lift", "blade_drop"]
var sound := Soundscape.new()
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in 90:
		sound._process(1.0 / 60.0)

func cue_rms_db(cue: String) -> float:
	var player := sound.get_node(NodePath(cue)) as AudioStreamPlayer
	var playback := player.stream.instantiate_playback()
	playback.start()
	var frames := int(player.stream.get_length() * AudioServer.get_mix_rate())
	var samples := playback.mix_audio(1.0, frames)
	playback.stop()
	var sum_squares := 0.0
	for frame in samples:
		sum_squares += frame.length_squared()
	return linear_to_db(sqrt(sum_squares / (2.0 * samples.size()))) + player.volume_db

func _run() -> void:
	var initial_bus_count := AudioServer.bus_count
	root.add_child(sound)
	for cue in REQUIRED_CUES:
		var player := sound.get_node_or_null(NodePath(cue)) as AudioStreamPlayer
		expect(player != null, "Missing game cue: %s" % cue)
		if player == null:
			continue
		expect(player.stream is AudioStreamMP3 and player.stream.get_length() > 0.25, "Imported MP3 is empty: %s" % cue)
		expect(not player.playing, "Title should be quiet: %s" % cue)
		expect(player.stream.loop == (cue in Soundscape.LOOPS), "Loop flag: %s" % cue)
	if failures == 0:
		var key_db := cue_rms_db("radio_key")
		expect(absf(key_db - cue_rms_db("radio_squelch")) < 6.0, "CB press and release have comparable levels")
		expect(cue_rms_db("horn") - key_db < 15.0, "Horn stays within 15 dB of the mic switch")
		await _check_mix()
	sound.shutdown()
	expect(AudioServer.bus_count == initial_bus_count, "Storm bus removed at shutdown")
	expect(not sound.is_processing(), "Mixing stopped at shutdown")
	for player: AudioStreamPlayer in sound.get_children():
		expect(not player.playing and player.stream == null, "Decoder released: %s" % player.name)
	sound.queue_free()
	# The dummy audio driver runs on a wall-clock thread even with --fixed-fps.
	var finish := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < finish:
		OS.delay_msec(10)
		await process_frame
	print("%d soundscape checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_mix() -> void:
	sound.update_state(true, 0.0, false)
	sound.set_gust(1.0)
	settle()
	for cue in Soundscape.LOOPS:
		expect(sound.get_node(NodePath(cue)).playing, "Loop starts on first driving update: %s" % cue)
	var wind: AudioStreamPlayer = sound.get_node("wind")
	var gust: AudioStreamPlayer = sound.get_node("crosswind")
	var heater: AudioStreamPlayer = sound.get_node("heater")
	var wind_bus := AudioServer.get_bus_index(wind.bus)
	expect(wind_bus > 0 and gust.bus == wind.bus and heater.bus != wind.bus, "Only exterior wind passes through the cab filter")
	var low_pass := AudioServer.get_bus_effect(wind_bus, 0) as AudioEffectLowPassFilter
	expect(low_pass != null, "Wind bus has its low-pass filter")
	var inside_peak := gust.volume_db
	expect(low_pass.cutoff_hz < 2000, "Closed cab muffles the high end")
	sound.update_state(false, 0.0, false)
	sound.set_gust(0.0)
	settle()
	var outside_lull := gust.volume_db
	sound.set_gust(1.0)
	sound._process(1.0 / 60.0)
	var first_rise := gust.volume_db
	settle()
	expect(gust.volume_db > outside_lull + 15.0, "Outdoor squalls rise distinctly above lulls")
	expect(first_rise > outside_lull and first_rise < gust.volume_db - 4.0, "Gust gains ramp smoothly")
	expect(gust.volume_db > inside_peak + 8, "Closing the cab attenuates a gust")
	expect(low_pass.cutoff_hz > 10000 and heater.volume_db < -60, "Open air releases the filter and removes the fan")
	sound.play_cue("horn")
	expect(sound.get_node("horn").playing, "Horn one-shot plays")

	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(0, capture)
	var deadline := Time.get_ticks_msec() + 3000
	while capture.get_frames_available() < 4096 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
		await process_frame
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in samples:
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	expect(samples.size() >= 4096 and peak > 0.002, "Bundled recordings produce decoded PCM at the master output")
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
