extends SceneTree

## DEMO-RC-G8-00 — 전투 피해·사기·센서·지형 효과 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0

func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)

func _eq(actual, expected, label: String) -> void:
	_ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])

func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G8-00 — 전투 피해·사기·센서·지형 효과 UI")
	root.size = Vector2i(1600, 900)
	await _test_public_battle_flow()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass, _fail])
	quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)

func _test_public_battle_flow() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads"); var setup: Dictionary = loaded.setup.duplicate(true)
	var positions := {"RC-LIU-SQ-01":[700,49], "RC-LIU-SQ-02":[700,49], "RC-LIU-FC-01":[700,49], "RC-SUN-SQ-01":[550,100], "RC-CAO-SQ-01":[781,11]}
	for squad in setup.squadrons: squad.initial_position = positions[String(squad.id)].duplicate(); squad.initial_facing_deg = 0
	var battle = Battle.new(); var initialized: Dictionary = battle.initialize(setup); _ok(initialized.ok, "battle initializes public combat-effects flow")
	if not initialized.ok:
		print("  initialization errors ", initialized.get("errors", []))
		return
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual", false).ok and battle.submit_command_draft().ok and battle.resolve_turn().ok and battle.continue_turn().ok, "turn 1 establishes public confirmed contact")
	var readiness: Dictionary = battle.chain_explosion_readiness(); _ok(readiness.ok and readiness.ready, "public chain operation reaches authoritative readiness")
	if not readiness.get("ready", false):
		print("  readiness debug ", readiness)
		return
	_ok(battle.stage_chain_explosion(String(readiness.detachment_id), String(readiness.contact_id)).ok, "public stage command accepts viewer-safe contact")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("manual", false).ok and battle.submit_command_draft().ok, "turn 2 public commands submit")
	var resolved: Dictionary = battle.resolve_turn(); _ok(resolved.ok, "turn 2 resolves actual combat effects")
	var chain: Dictionary = battle.viewer_chain_explosion_state("liu_bei")
	_ok(chain.get("effects_resolved", false) and String(chain.get("effects_status", "")) == "applied", "chain viewer reports authoritative effect application")
	var effects: Dictionary = battle.viewer_combat_effects("liu_bei")
	_ok(effects.ok and not effects.own_squadrons.is_empty() and effects.events.any(func(row): return String(row.get("event_type", "")) == "chain_effects_applied"), "public viewer receives actual own state and resolved chain event")
	_ok(not JSON.stringify(effects).contains("RC-CAO-SQ-01"), "Liu projection contains no raw enemy squadron id")
	_ok(effects.contacts.all(func(row): return not row.has("squadron_id") and not row.has("hull") and not row.has("morale") and not row.has("sensor")), "enemy contacts expose observed bands without exact state")
	_ok(bool(effects.victory_boundary.input_ready) and not bool(effects.victory_boundary.winner_present), "G8-00 prepares G8-01 input without declaring a winner")
	_ok(battle.continue_turn().ok, "turn 3 activates scheduled temporary terrain")
	effects = battle.viewer_combat_effects("liu_bei")
	_ok(not effects.temporary_terrain_zones.is_empty() and effects.temporary_terrain_zones[0].status == "active", "public receipt exposes active temporary terrain")
	var snapshot: Dictionary = battle.viewer_snapshot("liu_bei"); var hazard_id := String(effects.temporary_terrain_zones[0].zone_id)
	_ok(snapshot.terrain_zones.any(func(row): return String(row.get("zone_id", "")) == hazard_id), "existing viewer terrain projection includes temporary hazard for map reuse")
	var view := BattleView.new(); _ok(view.configure(battle, 0, JSON.stringify(setup)).ok, "battle view configures from public controller"); root.add_child(view); await _settle()
	var title: Label = view.find_child("CombatEffectsTitle", true, false); var hazard: Label = view.find_child("TemporaryTerrainEffect_%s" % hazard_id, true, false)
	_ok(title != null and hazard != null, "product view renders combat status and temporary terrain from public receipt")
	var own_labels := view.find_children("CombatEffectsOwn_*", "Label", true, false); _ok(own_labels.size() == 1, "selected product view shows one exact own row")
	if own_labels.size() == 1:
		var own_label: Label = own_labels[0]; var own_id := String(own_label.name).trim_prefix("CombatEffectsOwn_"); var own_receipt: Dictionary = {}
		for row in effects.own_squadrons:
			if String(row.get("squadron_id", "")) == own_id: own_receipt = row; break
		_ok(not own_receipt.is_empty(), "rendered own row originates in public viewer receipt")
		if not own_receipt.is_empty():
			var hull: Dictionary = own_receipt.hull; var morale: Dictionary = own_receipt.morale; var sensor: Dictionary = own_receipt.sensor
			_ok(own_label.text.contains("함체 %d/%d" % [int(hull.current), int(hull.maximum)]) and own_label.text.contains("사기 %d/%d" % [int(morale.current), int(morale.maximum)]) and own_label.text.contains("누적 사상 %d" % int(own_receipt.casualties_total)), "product own row renders exact public hull, morale, and casualty values")
			_ok(own_label.text.contains("보정 %s%d%%" % ["+" if int(sensor.modifier_percent) >= 0 else "", int(sensor.modifier_percent)]) and own_label.text.contains("명령 %s" % ("가능" if bool(own_receipt.capabilities.can_command) else "잠김")), "product own row renders public sensor and capability state")
	var contact_labels := view.find_children("CombatEffectsContact_*", "Label", true, false); _ok(contact_labels.size() == effects.contacts.size() and not contact_labels.is_empty(), "product view shows every viewer-safe observed enemy effect")
	for contact_row in effects.contacts:
		var contact_label: Label = view.find_child("CombatEffectsContact_%s" % String(contact_row.contact_id), true, false)
		_ok(contact_label != null and contact_label.text.contains(String(contact_row.damage_label)) and contact_label.text.contains(String(contact_row.morale_label)) and contact_label.text.contains(String(contact_row.sensor_label)) and not contact_label.text.contains("RC-CAO"), "enemy row renders only public observed labels for %s" % String(contact_row.contact_id))
	var hazard_receipt: Dictionary = effects.temporary_terrain_zones[0]; var hazard_effects: Dictionary = hazard_receipt.effects
	_ok(hazard != null and hazard.text.contains("활성") and hazard.text.contains("T%d~T%d" % [int(hazard_receipt.active_from_turn), int(hazard_receipt.expires_after_turn)]) and hazard.text.contains("이동 %d bp" % int(hazard_effects.movement_cost_basis_points)) and hazard.text.contains("탐지 %s%d%%" % ["+" if int(hazard_effects.observer_sensor_percent) >= 0 else "", int(hazard_effects.observer_sensor_percent)]), "product temporary terrain row renders public status, lifetime, and effects")
	var recent_events: Array = effects.events.slice(maxi(0, effects.events.size() - 4))
	for event_row in recent_events:
		var event_label: Label = view.find_child("CombatEffectEvent_%s" % String(event_row.event_id), true, false); var safe_text := String(event_row.headline)
		for detail in event_row.details: safe_text += String(detail)
		var rendered_all := event_label != null and event_label.text.contains(String(event_row.headline))
		if event_label != null:
			for detail in event_row.details: rendered_all = rendered_all and event_label.text.contains(String(detail))
		_ok(rendered_all and not safe_text.contains("RC-CAO-SQ-01"), "product event renders viewer-safe public headline/details for %s" % String(event_row.event_id))
	var victory: Label = view.find_child("CombatEffectsVictoryBoundary", true, false); _ok(victory != null and victory.text.contains("pending_G8_01") and victory.text.contains("입력 준비") and victory.text.contains("승자 미확정"), "product view keeps G8-01 winner boundary explicit")
	var privacy: Label = view.find_child("CombatEffectsPrivacy", true, false); _ok(privacy != null and privacy.text.contains("숨은 전대") and privacy.text.contains("수동 조작하는 버튼은 없습니다"), "product view states privacy and read-only boundaries")
	var forbidden := view.find_children("*", "Button", true, false).filter(func(node):
		var value := String(node.text); return value.contains("피해 적용") or value.contains("사기 변경") or value.contains("센서 장애") or value.contains("지형 생성"))
	_eq(forbidden.size(), 0, "no combat-effect mutation controls exist in product view")
	var map = view.find_child("AppliedSquadronMap", true, false)
	_ok(map.terrain_zones_for_test().any(func(row): return String(row.get("zone_id", "")) == hazard_id), "2D tactical map receives active temporary hazard")
	var applied: Label = view.find_child("ChainExplosionEffectsApplied", true, false); _ok(applied != null and applied.text.contains("G8-01"), "product chain panel shows effects applied and keeps victory pending")
	if DisplayServer.get_name() != "headless":
		var scroll: ScrollContainer = view.find_child("MovementOrderScroll", true, false)
		if scroll != null and title != null: scroll.scroll_vertical = maxi(0, int(title.position.y) - 24)
		await process_frame; await process_frame
		var output_dir := "res://out/demo-rc-g8-00-combat-effects"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600, 900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("combat-effects-1600x900.png"))) == OK, "GPU capture saved")
	view.free()


func _test_source_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")
	_ok("viewer_combat_effects" in source and "own_squadrons" in source and "temporary_terrain_zones" in source and "victory_boundary" in source, "UI consumes public combat-effects projection")
	_ok("apply_damage" not in source and "set_morale" not in source and "create_temporary_terrain" not in source, "UI contains no effect mutation API")
	_ok("Node3D" not in source and ".glb" not in source, "combat-effects presentation remains Control-based 2D")

func _settle() -> void:
	await process_frame
	await process_frame
