extends SceneTree

## S5-02 renderer-only sampling-cap stress and optional 1600x900 GPU capture.

const Harness := preload("res://tests/harness.gd")
const Renderer := preload("res://scripts/red_cliff_turn/visible_fleet_3d/red_cliff_visible_fleet_3d.gd")
const OUTPUT_DIR := "res://out/s5-02-red-cliff-visible-fleet-3d"

var passed := 0
var failed := 0


func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failed += 1; print("  x %s" % label)


func _init() -> void: call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var composition: Array = []
	for index in range(8): composition.append({"ship_type_id": "SHP-%02d" % (index + 1), "count": 26 if index < 4 else 25})
	var projection := {"ok": true, "errors": [], "profile_id": "S5-02", "viewer_faction_id": "liu_bei", "turn": 2, "phase": "victory_check",
		"battlefield_bounds": [0,0,1600,900], "own_squadrons": [{"squadron_id":"STRESS-204", "faction_id":"liu_bei", "name":"204척 공개 투영 스트레스", "flagship":"", "position":[620,430], "facing_deg":0, "formation_id":"FRM-05", "composition_current":composition, "hull":{}, "morale":{}, "sensor":{}, "capabilities":{}}],
		"contacts": [{"contact_id":"CNT-STRESS", "state":"estimated", "display_position":[1120,420], "effect_band":"damaged", "damage_label":"피해 추정", "morale_label":"동요 추정", "sensor_label":"관측 불확실"}],
		"terrain_zones": [], "events": [{"event_id":"EV-STRESS", "turn":2, "event_type":"shot_effect_resolved", "own_squadron_id":"STRESS-204", "contact_id":"CNT-STRESS", "visual_order":0}], "event_ordering":"turn_event_id_event_type_ascending", "visual_seed":"0".repeat(64)}
	var cold_started_usec := Time.get_ticks_usec()
	var renderer := Renderer.new(); renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); renderer.configure(projection, "STRESS-204"); root.add_child(renderer)
	await process_frame; await process_frame; await process_frame
	var cold_ready_ms := float(Time.get_ticks_usec() - cold_started_usec) / 1000.0
	var summary: Dictionary = renderer.visual_summary_for_test()
	check(int(summary.get("requested_own_ship_count", -1)) == 204 and int(summary.get("own_ship_count", -1)) == 204, "all 204 publicly projected own ships render")
	check(not bool(summary.get("sampled", true)) and int(summary.get("small_craft_count", 0)) == 25, "exact cap is not marked sampled and SHP-08 uses glyphs")
	check(int(summary.get("estimated_proxy_count", 0)) == 1 and int(summary.get("beam_count", 0)) == 1, "opaque contact and viewer event produce evidence visuals")
	composition[0].count = 27
	renderer.configure(projection, "STRESS-204"); await process_frame
	summary = renderer.visual_summary_for_test()
	check(int(summary.get("requested_own_ship_count", -1)) == 205 and int(summary.get("own_ship_count", -1)) == 204 and bool(summary.get("sampled", false)), "205th ship is deterministically sampled at the frozen 204 cap")
	for _warmup in range(60): await process_frame
	var frame_ms: Array[float] = []
	for _sample in range(300):
		var started_usec := Time.get_ticks_usec()
		await process_frame
		frame_ms.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
	frame_ms.sort()
	var p50 := _percentile(frame_ms, 0.50); var p95 := _percentile(frame_ms, 0.95); var p99 := _percentile(frame_ms, 0.99); var maximum: float = frame_ms.back()
	print("S5-02 PERF 204 ships cold=%.3fms; warm 300 frames: p50=%.3fms p95=%.3fms p99=%.3fms max=%.3fms" % [cold_ready_ms, p50, p95, p99, maximum])
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		check(p95 <= 33.3 and p99 <= 50.0, "204-ship warm frame budget meets p95<=33.3ms and p99<=50ms")
		var method := RenderingServer.get_current_rendering_method()
		var suffix := "-compatibility" if method == "gl_compatibility" else ""
		var viewport_size := [560, 436] if method == "gl_compatibility" else [720, 560]
		var metrics_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join("visible-fleet-3d-204-performance%s.json" % suffix))
		var metrics_file := FileAccess.open(metrics_path, FileAccess.WRITE)
		check(metrics_file != null, "GPU performance receipt opens")
		if metrics_file != null:
			metrics_file.store_string(JSON.stringify({"task_id":"S5-02","renderer":method,"display_server":DisplayServer.get_name(),"video_adapter":RenderingServer.get_video_adapter_name(),"godot_version":String(Engine.get_version_info().get("string", "")),"viewport_size":viewport_size,"visible_ship_count":204,"projection_sha256":JSON.stringify(projection).sha256_text(),"cold_ready_ms":cold_ready_ms,"warmup_frames":60,"sample_frames":300,"p50_ms":p50,"p95_ms":p95,"p99_ms":p99,"max_ms":maximum,"targets":{"p95_ms":33.3,"p99_ms":50.0}}, "\t"))
			metrics_file.close()
		var image := root.get_texture().get_image(); check(image != null and image.get_size() == Vector2i(1600, 900), "GPU capture is 1600x900")
		if image != null: check(image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join("visible-fleet-3d-204%s-1600x900.png" % suffix))) == OK, "GPU capture saved")
	renderer.free()
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(Harness.EXIT_FAIL if failed > 0 else Harness.EXIT_PASS)


func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty(): return 0.0
	var index := clampi(int(ceil(float(sorted_values.size()) * ratio)) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]
