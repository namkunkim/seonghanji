extends SceneTree

## DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트 UI.
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Editor := preload("res://scripts/red_cliff_turn/red_cliff_fast_craft_editor.gd")
const FormationEditor := preload("res://scripts/red_cliff_turn/red_cliff_formation_editor.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
const BattleView := preload("res://scripts/red_cliff_turn/red_cliff_turn_battle_view.gd")

var _pass := 0
var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트 UI")
	root.size = Vector2i(1600,900)
	await _test_editor()
	await _test_management_controls()
	await _test_formation_entry()
	_test_source_boundary()
	print("PASS %d / FAIL %d" % [_pass,_fail])
	quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _test_editor() -> void:
	var loaded := Setup.load_default(); _ok(loaded.ok, "setup loads")
	var editor := Editor.new(); _ok(editor.configure(loaded.setup).ok, "fast craft editor initializes"); root.add_child(editor); await _settle()
	_eq(editor.size.round(), Vector2(1600,900), "editor fills 1600x900")
	var category: Label = editor.find_child("FastCraftCategoryBoundary", true, false); _ok(category != null and category.text.contains("고속정") and category.text.contains("≠ 요격함") and category.text.contains("합산하지 않습니다"), "fast craft and interceptor category boundary is explicit")
	for mission_id in ["intercept","torpedo","recon","rescue"]:
		var button: Button = editor.find_child("FastMission_%s" % mission_id, true, false); var cost: Label = editor.find_child("FastMissionCost_%s" % mission_id, true, false)
		_ok(button != null and button.custom_minimum_size.y >= 44 and cost != null and cost.text.contains("선체 단가") and cost.text.contains("장비비") and cost.text.contains("척당 총"), "%s mission and core costs visible" % mission_id)
	var draft = editor.draft_controller(); var historical: Dictionary = draft.squadron_summary("RC-LIU-FC-01")
	_eq(historical.count, 6, "historical independent Liu fast craft squadron has six craft")
	_eq(historical.deployment.kind, "independent", "historical Liu fast craft squadron is independent")
	var before: String = draft.draft_digest(); var torpedo: Button = editor.find_child("FastMission_torpedo", true, false); _ok(not torpedo.disabled and not torpedo.get_signal_connection_list("pressed").is_empty(), "torpedo control is enabled and connected"); editor._equipment_changed("FAST-EQ-TORPEDO"); await _settle(); _ok(draft.draft_digest() != before, "torpedo equipment control mutates draft through core")
	var core_summary: Dictionary = draft.squadron_summary("RC-LIU-FC-01"); var ui_cost: Label = editor.find_child("FastCraftCostSummary", true, false)
	_ok(ui_cost.text.contains("척당 총비용  %d" % int(core_summary.total_unit_cost)) and ui_cost.text.contains("전대 소계  %d" % int(core_summary.subtotal_cost)), "UI cost equals core summary")
	var count: SpinBox = editor.find_child("FastCraftCount", true, false); count.value = count.value + 1; await _settle(); core_summary = draft.squadron_summary("RC-LIU-FC-01")
	var inventory: Dictionary = draft.faction_summary("liu_bei").inventory; var inventory_text: String = editor.find_child("FastCraftInventorySummary", true, false).text
	_ok(inventory_text.contains("기존 전대 배치  %d" % int(inventory.committed_other_squadrons)) and inventory_text.contains("잔여  %d" % int(inventory.remaining)), "inventory allocation and remaining equal core faction receipt")
	_ok(editor.find_child("FastCraftCommandMetrics", true, false).text.contains("단계 %d" % int(core_summary.penalty_tier)), "overcap tier and penalties use core summary")
	var applied := []; editor.loadout_applied.connect(func(receipt): applied.append(receipt)); editor._apply_draft(); await _settle(); _eq(applied.size(), 1, "apply emits once"); editor._apply_draft(); _eq(applied.size(), 1, "duplicate unchanged apply ignored")
	_ok(applied[0].get("applied_setup", {}).get("squadrons", []).any(func(row): return row.id == "RC-LIU-FC-01" and row.composition[0].mission_equipment_id == "FAST-EQ-TORPEDO"), "apply receipt carries actual independent fast craft loadout")
	var scope: Label = editor.find_child("FastCraftScopeBoundary", true, false); _ok(scope.text.contains("전투 시작 전에만") and scope.text.contains("변경되지 않습니다") and scope.text.contains("후속 기능"), "preparation and later-feature boundary visible")
	if DisplayServer.get_name() != "headless":
		var output_dir := "res://out/demo-rc-g6-01-fast-craft"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)); await process_frame
		var image := root.get_texture().get_image(); _ok(image != null and image.get_size() == Vector2i(1600,900), "1600x900 GPU image")
		if image != null: _ok(image.save_png(ProjectSettings.globalize_path(output_dir.path_join("fast-craft-formation-1600x900.png"))) == OK, "GPU capture saved")
	var battle = Battle.new(); _ok(battle.initialize(applied[0].applied_setup).ok, "applied setup initializes battle")
	var battle_view := BattleView.new(); battle_view.configure(battle, int(applied[0].formation_revision), String(applied[0].digest)); root.add_child(battle_view); await _settle()
	var select_fast: Button = battle_view.find_child("Select_RC-LIU-FC-01", true, false); _ok(select_fast != null, "actual Liu fast craft squadron is selectable in battle"); select_fast.pressed.emit(); await _settle()
	var immutable: Label = battle_view.find_child("AppliedFastCraftLoadout", true, false); _ok(immutable != null and immutable.text.contains("전투 중 불변") and immutable.text.contains("뇌격 장비") and immutable.text.contains("후속 기능"), "battle shows applied loadout as immutable without future results")
	editor._equipment_changed("FAST-EQ-RESCUE"); await _settle(); var battle_fast: Dictionary = battle.snapshot().applied_setup.squadrons.filter(func(row): return row.id == "RC-LIU-FC-01")[0]; _ok(battle_fast.composition[0].mission_equipment_id == "FAST-EQ-TORPEDO", "preparation draft changes cannot mutate active battle loadout")
	battle_view.free(); editor.free()

func _test_management_controls() -> void:
	var loaded := Setup.load_default(); var editor := Editor.new(); _ok(editor.configure(loaded.setup).ok, "management editor initializes"); root.add_child(editor); await _settle()
	for faction_id in ["liu_bei", "sun_quan", "cao_cao"]: _ok(editor.find_child("FastFaction_%s" % faction_id, true, false) != null, "%s faction is visible" % faction_id)
	var cao: Button = editor.find_child("FastFaction_cao_cao", true, false); cao.pressed.emit(); await _settle(); _ok(editor.find_child("CreateFastCraftSquadron", true, false).disabled, "Cao controls are read-only")
	var sun: Button = editor.find_child("FastFaction_sun_quan", true, false); sun.pressed.emit(); await _settle(); _ok(editor.find_child("CreateFastCraftSquadron", true, false).disabled, "Sun controls require opt-in")
	var manual: Button = editor.find_child("FastSunManual", true, false); manual.pressed.emit(); await _settle(); _ok(not editor.find_child("CreateFastCraftSquadron", true, false).disabled, "Sun controls enable after explicit opt-in")
	var liu: Button = editor.find_child("FastFaction_liu_bei", true, false); liu.pressed.emit(); await _settle()
	for node_name in ["CreateFastCraftSquadron", "SplitFastCraftSquadron", "DeleteFastCraftSquadron", "ToggleFastCraftDeployment", "CycleFastCraftBasing"]:
		_ok(editor.find_child(node_name, true, false) != null, "%s is reachable in preparation UI" % node_name)
	var draft = editor.draft_controller(); var initial_pure: int = draft.faction_summary("liu_bei").squadrons.size()
	var create: Button = editor.find_child("CreateFastCraftSquadron", true, false); create.pressed.emit(); await _settle()
	_eq(draft.faction_summary("liu_bei").squadrons.size(), initial_pure + 1, "spare-inventory UI creates another pure squadron")
	var created_id: String = String(editor.editor_state().selected_squadron); var fleet: Button = editor.find_child("ToggleFastCraftDeployment", true, false); fleet.pressed.emit(); await _settle()
	_eq(draft.squadron_summary(created_id).deployment.kind, "fleet", "UI can assign created squadron to faction fleet")
	var basing: Button = editor.find_child("CycleFastCraftBasing", true, false); basing.pressed.emit(); await _settle()
	_eq(draft.squadron_summary(created_id).basing_mode, "carrier", "UI exposes carrier basing metadata")
	var remove: Button = editor.find_child("DeleteFastCraftSquadron", true, false); remove.pressed.emit(); await _settle()
	_eq(draft.faction_summary("liu_bei").squadrons.size(), initial_pure, "UI deletes user-created squadron and returns stock")
	var before_committed := int(draft.faction_summary("liu_bei").inventory.committed_other_squadrons); var split: Button = editor.find_child("SplitFastCraftSquadron", true, false); split.pressed.emit(); await _settle()
	_eq(int(draft.faction_summary("liu_bei").inventory.committed_other_squadrons), before_committed - 1, "UI atomically splits one mixed-squadron craft into a pure squadron")
	var model: Label = editor.find_child("FastCraftDeploymentModel", true, false); _ok(model != null and model.text.contains("강습모함 탑재형") and model.text.contains("거점 배치형") and model.text.contains("후속 기능"), "deployment and basing model boundary is explicit")
	editor._select_squadron("RC-LIU-FC-01"); await _settle(); var delete_historical: Button = editor.find_child("DeleteFastCraftSquadron", true, false); _ok(not delete_historical.disabled, "historical default squadron is not artificially deletion-locked")
	delete_historical.pressed.emit(); await _settle(); _ok(not draft.squadron_summary("RC-LIU-FC-01").ok, "historical default can be disbanded through preparation UI")
	editor.free()

func _test_formation_entry() -> void:
	var loaded := Setup.load_default(); var editor := FormationEditor.new(); _ok(editor.configure(loaded.setup).ok, "G3 editor configures"); root.add_child(editor); await _settle()
	var open: Button = editor.find_child("OpenFastCraftEditor", true, false); _ok(open != null, "formation screen exposes fast craft editor")
	open.pressed.emit(); await _settle(); var first: Control = editor.find_child("RedCliffFastCraftEditor", true, false); _ok(first != null and first.visible, "fast craft panel opens")
	var propagated := []; editor.formation_applied.connect(func(setup, summary): propagated.append([setup,summary])); first._equipment_changed("FAST-EQ-TORPEDO"); await _settle(); first._apply_draft(); await _settle(); _eq(propagated.size(), 1, "fast craft apply propagates actual setup to preparation contract")
	_ok(editor.draft_controller().applied_snapshot().squadrons.any(func(row): return row.id == "RC-LIU-FC-01" and row.composition[0].mission_equipment_id == "FAST-EQ-TORPEDO"), "G3 applied setup receives fast craft loadout")
	var instance := first.get_instance_id(); first.close_requested.emit(); open.pressed.emit(); await _settle(); var reopened: Control = editor.find_child("RedCliffFastCraftEditor", true, false); _eq(reopened.get_instance_id(), instance, "duplicate open reuses one panel")
	_eq(reopened.draft_controller().squadron_summary("RC-LIU-FC-01").equipment_id, "FAST-EQ-TORPEDO", "reused child reconfigures from parent applied setup")
	_ok(reopened.draft_controller().restore_historical().ok and reopened.draft_controller().squadron_summary("RC-LIU-FC-01").equipment_id == "FAST-EQ-RECON", "reentered child retains true historical baseline")
	reopened.draft_controller().cancel(); reopened._refresh(); reopened.close_requested.emit()
	_ok(editor.draft_controller().set_fast_equipment("RC-LIU-FC-01", "FAST-EQ-RESCUE").ok and editor.draft_controller().apply().ok, "parent applies a loadout while child is hidden")
	open.pressed.emit(); await _settle(); _eq(reopened.draft_controller().squadron_summary("RC-LIU-FC-01").equipment_id, "FAST-EQ-RESCUE", "reopen refreshes child from latest parent applied setup")
	editor.free()

func _test_source_boundary() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/red_cliff_turn/red_cliff_fast_craft_editor.gd")
	_ok("Node3D" not in source and ".glb" not in source and "voyage_3d" not in source, "fast craft UI is pure 2D")
	_ok("28척" not in source and "global_economy" not in source, "UI has no fixed 28 or global economy cost")

func _settle() -> void:
	await process_frame
	await process_frame
