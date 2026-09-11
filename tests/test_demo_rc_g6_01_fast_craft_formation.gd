extends SceneTree

## Task ID / 공식·새 작업 제목: DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트
const Harness := preload("res://tests/harness.gd")
const Setup := preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const FastCraft := preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_formation.gd")
const Battle := preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass := 0; var _fail := 0
func _ok(value: bool, label: String) -> void:
	if value: _pass += 1
	else: _fail += 1; print("  x %s" % label)
func _eq(actual, expected, label: String) -> void: _ok(actual == expected, "%s (%s != %s)" % [label, str(actual), str(expected)])
func _init() -> void: call_deferred("_run")

func _run() -> void:
	print("DEMO-RC-G6-01 — 고속정 전대와 요격·뇌격·정찰·구조 임무 장비·코스트")
	_test_historical_setup_and_catalog()
	_test_cost_inventory_and_atomic_mutations()
	_test_create_delete_permissions_and_draft_lifetime()
	_test_deployment_basing_split_transfer_and_dissolution()
	_test_apply_to_battle_immutable_loadout()
	_test_overcap_curve_and_invalid_boundaries()
	print("PASS %d / FAIL %d" % [_pass, _fail]); quit(Harness.EXIT_FAIL if _fail > 0 else Harness.EXIT_PASS)

func _setup() -> Dictionary:
	var loaded := Setup.load_default(); _ok(loaded.ok, "default setup loads"); return loaded.setup
func _editor(setup: Dictionary = {}):
	if setup.is_empty(): setup = _setup()
	var editor = FastCraft.new(); var result: Dictionary = editor.initialize(setup); _ok(result.ok, "fast-craft editor initializes: %s" % str(result.get("errors", []))); return editor
func _squad(setup: Dictionary, id: String) -> Dictionary:
	for row in setup.squadrons:
		if String(row.id) == id: return row
	return {}

func _test_historical_setup_and_catalog() -> void:
	var setup := _setup(); var historical := _squad(setup, "RC-LIU-FC-01")
	_ok(not historical.is_empty(), "demo starts with actual Liu fast-craft squadron")
	_eq(historical.deployment.kind, "independent", "historical fast-craft squadron is independently commandable")
	_ok(historical.operational and historical.composition.size() == 1, "historical fast-craft squadron starts operational and pure")
	_eq([String(historical.composition[0].ship_type_id), int(historical.composition[0].count), String(historical.composition[0].mission_equipment_id)], ["SHP-08", 6, "FAST-EQ-RECON"], "historical normal-demo loadout exact")
	_eq(historical.declared_total_cost, 18, "historical total is base 2 plus recon 1 times six")
	var editor = _editor(setup); var catalog: Dictionary = editor.catalog()
	_eq(catalog.profile_id, "normal-demo-fast-craft-v1", "scenario-local profile explicit")
	_eq(catalog.fast_craft_ship_type_id, "SHP-08", "fast craft keeps SHP-08")
	_eq(catalog.interceptor_ship_type_id, "SHP-07", "interceptor remains distinct SHP-07")
	_ok(String(catalog.category_contract.distinction).contains("합산하지 않는다"), "category boundary is explicit")
	_eq(catalog.missions.map(func(row): return String(row.equipment_id)), ["FAST-EQ-INTERCEPT", "FAST-EQ-TORPEDO", "FAST-EQ-RECON", "FAST-EQ-RESCUE"], "four equipment options exact and stable")
	_eq(catalog.missions.map(func(row): return int(row.total_unit_cost)), [3, 4, 3, 3], "base plus equipment unit costs are authoritative receipts")
	_eq(catalog.deployment_kinds, ["independent", "fleet"], "fast-craft squadron supports independent and fleet deployment")
	_eq(catalog.basing_modes, ["independent", "carrier", "base"], "independent, carrier-based, and base-deployed preparation metadata are explicit")
	_ok(String(catalog.basing_contract.carrier).contains("G6-03") and String(catalog.basing_contract.base).contains("G6-03"), "carrier/base metadata does not pretend later resupply behavior")
	_eq(catalog.penalty_application, {"mobility_percent":"active_g4_movement", "accuracy_percent":"active_pre_resource_accuracy_snapshot", "formation_change_percent":"active_resolution_start_modifier_effectiveness"}, "penalty consumer capability is explicit")
	_eq(catalog.out_of_scope, ["in_battle_equipment_change", "tactical_mission_effect", "drift", "rescue_result", "capture_result", "supply_source_stock", "supply_source_damage", "base_reloading"], "equipment mutation and remaining G6-05+ or source-stock effects remain exactly out of scope")
	var source := FileAccess.get_file_as_string("res://data/red-cliffs-fast-craft-rules.json") + FileAccess.get_file_as_string("res://core/demo_red_cliffs/red_cliffs_fast_craft_formation.gd")
	_ok(not source.contains("28척") and not source.contains("SQUADRON_SHIPS") and not source.contains("global_economy") and not source.contains("core/combat/battle.gd") and not source.contains("data/ship-types.json"), "no fixed 28-craft or global economy authority coupling")

func _test_cost_inventory_and_atomic_mutations() -> void:
	var editor = _editor(); var summary: Dictionary = editor.squadron_summary("RC-LIU-FC-01")
	_eq([summary.base_unit_cost, summary.equipment_unit_cost, summary.total_unit_cost, summary.subtotal_cost], [2, 1, 3, 18], "historical cost receipt is complete")
	_eq(summary.historical_total_cost, 18, "historical baseline cost remains separately visible")
	_eq(summary.recommended_cost, 222, "command limit uses setup 40 plus command times two")
	_eq(summary.penalty_tier, 0, "under-cap historical squad has no penalty")
	var inventory: Dictionary = editor.faction_summary("liu_bei")
	_eq(inventory.inventory, {"total": 16, "committed_other_squadrons": 6, "reserved_fast_craft_squadrons": 6, "used": 12, "remaining": 4}, "inventory distinguishes embedded craft and independent squadron")
	var torpedo: Dictionary = editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-TORPEDO"); _ok(torpedo.ok, "eligible torpedo equipment applies in preparation")
	_eq(torpedo.squadron.subtotal_cost, 24, "equipment change updates subtotal immediately")
	_ok(editor.set_count("RC-LIU-FC-01", 10).ok, "count may consume exact remaining faction inventory")
	_eq(editor.faction_summary("liu_bei").inventory.remaining, 0, "exact inventory boundary accepted")
	var before := editor.draft_digest(); var rejected: Dictionary = editor.set_count("RC-LIU-FC-01", 11)
	_ok(not rejected.ok and JSON.stringify(rejected.errors).contains("재고 초과"), "inventory overrun rejected with reason")
	_eq(editor.draft_digest(), before, "invalid count mutation is atomic")
	_ok(not editor.set_count("RC-LIU-FC-01", 0).ok, "zero-craft squadron rejected")
	_ok(not editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-UNKNOWN").ok, "unknown equipment rejected")
	_ok(not editor.set_equipment("RC-LIU-SQ-01", "FAST-EQ-RECON").ok, "mixed main squadron is not treated as fast-craft squadron")

func _test_create_delete_permissions_and_draft_lifetime() -> void:
	var editor = _editor(); var historical_digest := JSON.stringify(editor.historical_snapshot()); var applied_digest := editor.applied_digest()
	var created: Dictionary = editor.create_squadron("liu_bei", " 별동 구조정대 ", "CHR-0107", 4, "FAST-EQ-RESCUE", "FRM-07", Vector2(300, 700))
	_ok(created.ok and String(created.squadron_id).begins_with("RC-USER-LIU_BEI-FC-"), "spare inventory creates stable independent fast-craft squadron")
	_eq(created.squadron.subtotal_cost, 12, "created rescue squad cost calculated")
	_eq(created.faction.inventory.remaining, 0, "creation reserves spare inventory")
	_ok(not editor.create_squadron("liu_bei", "초과", "CHR-0107", 1, "FAST-EQ-RECON", "FRM-01", Vector2.ZERO).ok, "duplicate commander or exhausted stock rejects creation")
	_ok(editor.delete_squadron(String(created.squadron_id)).ok, "user-created squadron deletion returns stock")
	_ok(not editor.create_squadron("cao_cao", "금지", "CHR-0043", 1, "FAST-EQ-INTERCEPT", "FRM-01", Vector2.ZERO).ok, "Cao preparation remains read-only")
	_ok(not editor.create_squadron("sun_quan", "잠금", "CHR-0186", 1, "FAST-EQ-TORPEDO", "FRM-01", Vector2.ZERO).ok, "Sun creation requires explicit opt-in")
	_ok(editor.set_sun_manual(true).ok, "Sun manual opt-in applies")
	var sun_created: Dictionary = editor.create_squadron("sun_quan", "손권 구조정대", "CHR-0186", 4, "FAST-EQ-RESCUE", "FRM-07", Vector2(400, 600)); _ok(sun_created.ok, "Sun can create after opt-in")
	_ok(editor.set_sun_manual(false).ok, "disabling Sun manual restores applied faction")
	_ok(_squad(editor.draft_snapshot(), String(sun_created.squadron_id)).is_empty(), "Sun uncommitted draft is discarded on relock")
	editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-TORPEDO"); _ok(editor.cancel().ok, "cancel discards draft")
	_eq(editor.draft_digest(), applied_digest, "cancel returns exact applied setup")
	editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-TORPEDO"); _ok(editor.restore_historical().ok, "historical restore succeeds")
	_eq(editor.draft_digest(), historical_digest, "historical restore is exact deep copy")

func _test_deployment_basing_split_transfer_and_dissolution() -> void:
	var editor = _editor(); var original := editor.draft_digest()
	_ok(editor.set_deployment("RC-LIU-FC-01", "fleet", "RC-LIU-FLT-01").ok, "pure fast-craft squadron may join same-faction fleet")
	var fleet_setup := editor.draft_snapshot(); var fleet_squad := _squad(fleet_setup, "RC-LIU-FC-01")
	_eq(fleet_squad.deployment, {"kind":"fleet", "fleet_id":"RC-LIU-FLT-01"}, "fleet deployment metadata is authoritative")
	_ok(fleet_setup.fleet_groups[0].squadron_ids.has("RC-LIU-FC-01"), "fleet membership list receives fast-craft squadron")
	var before_bad_fleet := editor.draft_digest(); _ok(not editor.set_deployment("RC-LIU-FC-01", "fleet", "RC-CAO-FLT-01").ok, "cross-faction fleet assignment rejected")
	_eq(editor.draft_digest(), before_bad_fleet, "invalid deployment leaves draft atomic")
	_ok(editor.set_deployment("RC-LIU-FC-01", "independent").ok, "fleet fast-craft may return to independent command")
	_ok(editor.set_basing_mode("RC-LIU-FC-01", "carrier").ok, "carrier-based source type is selectable")
	_eq(editor.squadron_summary("RC-LIU-FC-01").basing_mode, "carrier", "carrier source metadata is preserved")
	_ok(editor.set_basing_mode("RC-LIU-FC-01", "base").ok, "base-deployed source type is selectable")
	var before_bad_base := editor.draft_digest(); _ok(not editor.set_basing_mode("RC-LIU-FC-01", "unknown").ok, "unknown source type rejected")
	_eq(editor.draft_digest(), before_bad_base, "invalid source type leaves draft atomic")

	var split := editor.split_from_mixed_squadron("RC-LIU-SQ-01", "혼성 분리 뇌격정대", "CHR-0107", 2, "FAST-EQ-TORPEDO", "FRM-07", Vector2(330, 700), "fleet", "RC-LIU-FLT-01", "carrier")
	_ok(split.ok, "mixed-squadron SHP-08 split creates a pure squadron atomically: %s" % str(split.get("errors", [])))
	_eq(split.get("transferred_count", 0), 2, "split receipt records transferred craft")
	_eq(_squad(editor.draft_snapshot(), "RC-LIU-SQ-01").composition.filter(func(row): return row.ship_type_id == "SHP-08")[0].count, 4, "mixed source loses exact split count")
	_eq(split.get("squadron", {}).get("basing_mode", ""), "carrier", "split target keeps requested source metadata")
	_eq(split.get("squadron", {}).get("deployment", {}).get("kind", ""), "fleet", "split target may be inserted directly into a fleet")
	var before_over_split := editor.draft_digest(); _ok(not editor.split_from_mixed_squadron("RC-LIU-SQ-01", "초과", "CHR-0107", 99, "FAST-EQ-RECON", "FRM-01", Vector2.ZERO).ok, "oversized split rejected")
	_eq(editor.draft_digest(), before_over_split, "failed split cannot partially subtract source")

	var transfer_editor = _editor(); var transferred := transfer_editor.transfer_from_mixed_squadron("RC-LIU-SQ-01", "RC-LIU-FC-01", 3)
	_ok(transferred.ok and transferred.transferred_count == 3, "mixed craft may transfer into an existing pure squadron")
	_eq(transfer_editor.squadron_summary("RC-LIU-FC-01").count, 9, "transfer increases pure target count")
	_eq(_component_count(_squad(transfer_editor.draft_snapshot(), "RC-LIU-SQ-01"), "SHP-08"), 3, "transfer decreases mixed source count")

	var dissolve = _editor(); var released := dissolve.delete_squadron("RC-LIU-FC-01")
	_ok(released.ok and released.released_to_inventory == 6, "historical default squadron may be legally dissolved to inventory")
	_ok(_squad(dissolve.draft_snapshot(), "RC-LIU-FC-01").is_empty(), "historical squadron is absent from valid draft after dissolution")
	_eq(dissolve.faction_summary("liu_bei").inventory.remaining, 10, "dissolution releases exact craft to faction inventory")
	var dissolved_applied := dissolve.apply(); _ok(dissolved_applied.ok, "historical dissolution applies as a valid setup")
	var dissolved_reopen = FastCraft.new(); _ok(dissolved_reopen.initialize(dissolved_applied.applied_setup).ok, "persisted dissolution reopens against the separate historical baseline")
	_ok(dissolved_reopen.restore_historical().ok and not _squad(dissolved_reopen.draft_snapshot(), "RC-LIU-FC-01").is_empty(), "reopened dissolution can restore historical squadron")
	_ok(dissolve.restore_historical().ok and not _squad(dissolve.draft_snapshot(), "RC-LIU-FC-01").is_empty(), "historical restore recreates dissolved baseline")
	var recover = _editor(); var recovered := recover.delete_squadron("RC-LIU-FC-01", "RC-LIU-SQ-01")
	_ok(recovered.ok and recovered.recovered_count == 6, "dissolution may recover craft directly into another same-faction squadron")
	_eq(_component_count(_squad(recover.draft_snapshot(), "RC-LIU-SQ-01"), "SHP-08"), 12, "recovery target receives exact dissolved count")
	var forbidden = _editor(); var forbidden_before := forbidden.draft_digest(); _ok(not forbidden.delete_squadron("RC-LIU-FC-01", "RC-CAO-SQ-01").ok, "cross-faction recovery rejected")
	_eq(forbidden.draft_digest(), forbidden_before, "forbidden recovery is atomic")
	_ok(original != editor.draft_digest(), "successful deployment and split operations change only the draft")

func _test_apply_to_battle_immutable_loadout() -> void:
	var editor = _editor(); _ok(editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-TORPEDO").ok, "battle loadout staged")
	var applied: Dictionary = editor.apply(); _ok(applied.ok and applied.formation_revision == 1, "apply returns merged setup with revision")
	_eq(_squad(applied.applied_setup, "RC-LIU-FC-01").composition[0].mission_equipment_id, "FAST-EQ-TORPEDO", "applied setup contains selected loadout")
	var reopened = FastCraft.new(); _ok(reopened.configure(editor.historical_snapshot(), applied.applied_setup).ok, "reopen keeps separate historical and applied setups")
	var reopened_single = FastCraft.new(); _ok(reopened_single.initialize(applied.applied_setup).ok, "persisted applied setup reopens through default historical baseline")
	_eq(_squad(reopened_single.historical_snapshot(), "RC-LIU-FC-01").composition[0].mission_equipment_id, "FAST-EQ-RECON", "single-argument reopen does not redefine historical loadout")
	_ok(reopened.restore_historical().ok and String(_squad(reopened.draft_snapshot(), "RC-LIU-FC-01").composition[0].mission_equipment_id) == "FAST-EQ-RECON", "reopen can restore original historical loadout")
	_ok(reopened.cancel().ok and String(_squad(reopened.draft_snapshot(), "RC-LIU-FC-01").composition[0].mission_equipment_id) == "FAST-EQ-TORPEDO", "cancel returns reopened applied loadout")
	var battle = Battle.new(); var initialized: Dictionary = battle.initialize(applied.applied_setup); _ok(initialized.ok, "battle accepts applied pure fast-craft squadron")
	var own_ids: Array = battle.viewer_snapshot("liu_bei").own_squadrons.map(func(row): return String(row.id)); _ok(own_ids.has("RC-LIU-FC-01"), "battle starts with operational independent fast-craft squadron")
	var battle_before := battle.snapshot(); editor.set_equipment("RC-LIU-FC-01", "FAST-EQ-RESCUE")
	_eq(battle.snapshot(), battle_before, "later preparation draft cannot mutate active battle loadout")
	var leaked: Dictionary = applied.applied_setup.duplicate(true); _squad(leaked, "RC-LIU-FC-01").composition[0].mission_equipment_id = "FAST-EQ-INTERCEPT"
	_eq(_squad(battle.snapshot().applied_setup, "RC-LIU-FC-01").composition[0].mission_equipment_id, "FAST-EQ-TORPEDO", "battle deep-copies applied setup")

func _test_overcap_curve_and_invalid_boundaries() -> void:
	var setup := _setup(); _faction(setup, "liu_bei").inventory["SHP-08"] = 200
	var editor = _editor(setup); _ok(editor.set_count("RC-LIU-FC-01", 100).ok, "expanded fixture stages high-cost squad within inventory")
	var metric: Dictionary = editor.squadron_summary("RC-LIU-FC-01")
	_eq(metric.subtotal_cost, 300, "high-count scenario-local cost exact")
	_eq(metric.penalty_tier, 2, "78 over 222 gives second started 25-percent tier")
	_eq(metric.penalties, {"mobility_percent": -10, "accuracy_percent": -8, "formation_change_percent": -16}, "over-cap penalty curve reuses setup authority")
	_eq(metric.pending_penalties, [], "all command penalties have active core consumers")
	_eq(metric.penalty_application.mobility_percent, "active_g4_movement", "active mobility consumer is distinguished from pending consumers")
	_eq(metric.penalty_application.accuracy_percent, "active_pre_resource_accuracy_snapshot", "accuracy penalty publishes its active downstream snapshot consumer")
	_eq(metric.penalty_application.formation_change_percent, "active_resolution_start_modifier_effectiveness", "formation-change penalty publishes its active modifier-effectiveness consumer")
	_ok(editor.apply().ok, "over-cap warning does not forbid apply")
	var missing := _setup(); missing.squadrons.erase(_squad(missing, "RC-LIU-FC-01")); var invalid = FastCraft.new()
	_ok(not invalid.initialize(missing).ok, "missing historical actual squadron rejected")
	var bad_equipment := _setup(); _squad(bad_equipment, "RC-LIU-FC-01").composition[0].mission_equipment_id = "FAST-EQ-UNKNOWN"
	_ok(not FastCraft.new().initialize(bad_equipment).ok, "unknown equipment rejected at loader boundary")
	var negative := _setup(); _squad(negative, "RC-LIU-FC-01").composition[0].count = -1
	_ok(not FastCraft.new().initialize(negative).ok, "negative count rejected at loader boundary")

func _faction(setup: Dictionary, id: String) -> Dictionary:
	for row in setup.factions:
		if String(row.id) == id: return row
	return {}

func _component_count(squad: Dictionary, ship_type_id: String) -> int:
	for row in squad.get("composition", []):
		if String(row.get("ship_type_id", "")) == ship_type_id: return int(row.get("count", 0))
	return 0
