extends SceneTree

## DEMO-RC-QA-02 native-renderer input-event acceptance.
## This intentionally drives the shipped Main scene only through Godot's public
## Input.parse_input_event route. It neither injects campaign data nor calls
## product methods/signals directly. It is a renderer-level substitute for the
## unavailable Windows physical-input surface, not an OS-input acceptance.

const OUTPUT_DIR := "res://out/demo-rc-qa02-windows-input"

var passed := 0
var failed := 0
var evidence: Array[String] = []

func _ok(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		evidence.append("PASS | " + label)
	else:
		failed += 1
		evidence.append("FAIL | " + label)

func _button(text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and (node as Button).text == text:
			return node as Button
	return null

func _click(button: Button, label: String) -> bool:
	if button == null:
		_ok(false, "%s button is visible" % label)
		return false
	var point := button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	await process_frame
	_ok(true, "%s mouse press/release injected at %s" % [label, str(point)])
	return true

func _click_point(point: Vector2, label: String) -> void:
	var press := InputEventMouseButton.new()
	press.position = point; press.global_position = point; press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = point; release.global_position = point; release.button_index = MOUSE_BUTTON_LEFT; release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	_ok(true, "%s mouse press/release injected at %s" % [label, str(point)])

func _key(keycode: Key, label: String) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	_ok(true, "%s keyboard press/release injected" % label)

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	_ok(image != null, "%s renderer image available" % name)
	if image == null:
		return
	_ok(image.get_size() == Vector2i(1600, 900), "%s viewport is 1600x900" % name)
	_ok(image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(name))) == OK,
		"%s PNG saved" % name)

func _write_report() -> void:
	var report := "DEMO-RC-QA-02 native-renderer Input.parse_input_event acceptance\n"
	report += "Scope: Godot-native renderer input events; NOT Windows OS physical input.\n"
	report += "Result: %d passed / %d failed\n\n" % [passed, failed]
	report += "\n".join(evidence) + "\n"
	var file := FileAccess.open(ProjectSettings.globalize_path(OUTPUT_DIR.path_join("qa02-native-input-report.txt")), FileAccess.WRITE)
	if file != null:
		file.store_string(report)

func _run() -> void:
	print("DEMO-RC-QA-02 native-renderer input-event acceptance")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	root.size = Vector2i(1600, 900)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if not await _click(_button("적벽"), "demo start"):
		_write_report(); quit(1); return
	# The real renderer may need a few frames to mount the full-rect briefing
	# after a top-bar click; this is observation time, not a state injection.
	for _mount_frame in 12:
		if root.find_child("RedCliffScenarioBriefing", true, false) != null:
			break
		await process_frame
	_ok(root.find_child("RedCliffScenarioBriefing", true, false) != null,
		"scenario briefing is mounted")
	for label in ["남하를 완수한다", "강동의 독립을 지킨다", "조조에 맞선다", "군사 협정과 장강 방어선을 세운다"]:
		if not await _click(_button(label), "scenario choice " + label):
			_write_report(); quit(1); return
	if not await _click(_button("적벽 전투 준비"), "activate canonical Red Cliffs battle"):
		_write_report(); quit(1); return
	await _capture("01-demo-active-banner-1600x900.png")
	# LT-02 immediately routes the accepted public activation through the same
	# canonical entry boundary as the home banner.  Retain the banner click when
	# it is visible, but do not require a second UI action after an auto-entry.
	var entry_button := _button("전투 진입")
	if entry_button != null:
		if not await _click(entry_button, "battle banner entry"):
			_write_report(); quit(1); return
	else:
		_ok(root.find_child("RedCliffBattleView", true, false) != null,
			"activation auto-entered through the canonical battle boundary")
	var tactical_map: Control=root.find_child("TacticalMapTwoThirds", true, false)
	_ok(tactical_map != null, "battle tactical map is mounted")
	_ok(root.find_child("BattleStillImageOneThird", true, false) != null, "battle still image is mounted")
	var fleet_point: Vector2=tactical_map.get_global_transform()*tactical_map.fleet_anchor_points()["wei_primary"]
	await _click_point(fleet_point,"select Wei fleet marker")
	_ok(tactical_map.selection_snapshot().get("id","")=="wei_primary",
		"native pointer opens the selected fleet detail")
	await _capture("02-battle-entry-1600x900.png")
	if not await _click(_button("진형 비교"), "open formation comparison"):
		_write_report(); quit(1); return
	_ok(main.red_cliff_battle_view._comparison_panel.visible,
		"formation comparison is visible through native pointer path")
	if not await _click(_button("닫기"), "close formation comparison"):
		_write_report(); quit(1); return

	if not await _click(_button("진형 유지"), "hold formation"):
		_write_report(); quit(1); return
	_ok("명령 접수" in main.red_cliff_battle_view._feedback.text
		or "명령 적용" in main.red_cliff_battle_view._feedback.text,
		"command feedback explains accepted UI submission")
	await _capture("03-hold-formation-1600x900.png")
	# The mouse activation leaves the hold button focused. Traverse the shipped
	# control order and activate delegation with the keyboard, proving both input
	# families reach the same public Control path.
	# Godot preserves the control-tree traversal slot for the disabled phase button.
	for _focus_step in 5:
		await _key(KEY_TAB, "move combat focus")
	var delegate_button := _button("AI에 위임")
	_ok(delegate_button != null and delegate_button.has_focus(), "keyboard focus reached AI delegation")
	await _key(KEY_ENTER, "delegate five-phase resolution")
	await _capture("04-ai-delegated-1600x900.png")
	if not await _click(_button("홈으로"), "return home for clock control"):
		_write_report(); quit(1); return
	# Visible 1x → 2x → 4x → 16x → 64x product control; this keeps the
	# acceptance bounded without reaching into the campaign clock.
	for _speed in 4:
		var speed_button := _button("1x")
		if speed_button == null:
			speed_button = _button("2x")
		if speed_button == null:
			speed_button = _button("4x")
		if speed_button == null:
			speed_button = _button("16x")
		if not await _click(speed_button, "increase visible playback speed"):
			_write_report(); quit(1); return
	_ok(_button("64x") != null, "visible playback control reached 64x")
	if not await _click(_button("II"), "resume campaign clock"):
		_write_report(); quit(1); return
	var clock_campaign = main.get("campaign")
	_ok(clock_campaign != null and not clock_campaign.world.clock.paused,
		"visible pause control resumed the campaign clock")

	# AI owns phases 2-5 after the UI delegation command. Await renderer frames,
	# not campaign calls; model state below is read only for the machine verdict.
	var resolved := false
	for _frame in 400:
		await create_timer(0.03).timeout
		await process_frame
		var campaign = main.get("campaign")
		if campaign != null and campaign.active_battles.size() == 1 \
				and String(campaign.active_battles[0].status) == ActiveBattle.STATUS_RESOLVED:
			resolved = true
			break
	_ok(resolved, "delegated battle reached resolved state through renderer input path")
	await _capture("05-five-phase-result-1600x900.png")
	# Stop the real-time campaign clock through the same visible product button.
	if _button("II") != null:
		await _click(_button("II"), "pause after result")
	_ok(_button("전투 진입") == null, "resolved battle no longer exposes active-entry banner")
	await _capture("06-home-after-result-1600x900.png")

	_write_report()
	main.free()
	print("DEMO-RC-QA-02 native input: %d passed / %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _init() -> void:
	call_deferred("_run")
