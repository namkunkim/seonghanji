extends SceneTree

## DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재
const Harness:=preload("res://tests/harness.gd")
const Setup:=preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Inventory:=preload("res://core/demo_red_cliffs/red_cliffs_supply_inventory.gd")
const Supply:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_supply.gd")
const Battle:=preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass:=0;var _fail:=0
func _ok(v:bool,label:String)->void:
	if v:_pass+=1
	else:_fail+=1;print("  x %s"%label)
func _eq(a,e,label:String)->void:_ok(a==e,"%s (%s != %s)"%[label,str(a),str(e)])
func _init()->void:call_deferred("_run")
func _run()->void:
	print("DEMO-RC-G6-06 — 보급함 재고·손상 처리량·거점 재적재")
	_test_initial_damage_destroy_capture();_test_consumption_reload_and_viewer();_test_unused_integer_capacity_does_not_accumulate();_test_supply_full_refill_skip();_test_battle_integration()
	print("PASS %d / FAIL %d"%[_pass,_fail]);quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)
func _system()->Dictionary:
	var loaded:=Setup.load_default();_ok(loaded.ok,"setup loads");var inventory=Inventory.new();var initialized:Dictionary=inventory.initialize(loaded.setup);_ok(initialized.ok,"inventory initializes")
	return {"inventory":inventory,"state":inventory.initial_state(),"setup":loaded.setup}
func _test_initial_damage_destroy_capture()->void:
	var x:=_system();var state:Dictionary=x.state;var cao:Dictionary=state.sources["SUPPLY_SHIP-RC-CAO-SQ-01"]
	_eq(cao.stock,{"fuel_basis_points":30000,"ammo_units":36,"supply_material_units":12},"three ships use one integrated stock")
	var begun:Dictionary=x.inventory.begin_turn(state,1);_eq(x.inventory.capacity("SUPPLY_SHIP-RC-CAO-SQ-01",begun.state),3,"three normal ships produce three throughput")
	var intent={"authority":"G8-00","status":"authorized_supply_ship_status","effective_turn":1,"source_id":"SUPPLY_SHIP-RC-CAO-SQ-01","source_revision":0,"ship_status_counts":{"operational":1,"moderate_damage":1,"heavy_damage":1,"destroyed":0,"captured":0}}
	var damaged:Dictionary=x.inventory.apply_authoritative_status(state,intent,1);_ok(damaged.ok,"G8 damage status applies");_eq(damaged.state.sources[intent.source_id].stock,cao.stock,"moderate and heavy damage preserve stock")
	var cadence:Dictionary=damaged.state;var capacities:Array=[]
	for turn in range(1,5):
		var r:Dictionary=x.inventory.begin_turn(cadence,turn);cadence=r.state;capacities.append(x.inventory.capacity(intent.source_id,cadence))
		while x.inventory.capacity(intent.source_id,cadence)>0:
			var a:Dictionary=x.inventory.authorize_refill(cadence,intent.source_id,"FC",{"fuel_basis_points":0,"ammo_units":0,"supply_material_units":1},turn);cadence=a.state
	_eq(capacities,[1,2,2,2],"17500bp damage throughput carries fractional credit deterministically")
	var destroyed_intent=intent.duplicate(true);destroyed_intent.source_revision=1;destroyed_intent.ship_status_counts={"operational":1,"moderate_damage":1,"heavy_damage":0,"destroyed":1,"captured":0}
	var destroyed:Dictionary=x.inventory.apply_authoritative_status(damaged.state,destroyed_intent,1);_eq(destroyed.state.sources[intent.source_id].stock,{"fuel_basis_points":20000,"ammo_units":24,"supply_material_units":8},"one of three destroyed loses floor one-third");_eq(destroyed.state.sources[intent.source_id].maximum_stock,{"fuel_basis_points":20000,"ammo_units":24,"supply_material_units":8},"destruction permanently lowers reload maximum")
	var spent:Dictionary=destroyed.state.duplicate(true);spent.sources[intent.source_id].stock={"fuel_basis_points":100,"ammo_units":1,"supply_material_units":1};var nav={"RC-CAO-SQ-01":{"position":[1460,180]}};var reloaded:Dictionary=x.inventory.finish_base_reload(spent,nav,nav,[{"squadron_id":"RC-CAO-SQ-01","actual_distance":0.0}],[{"source_id":"RC-BASE-CAO-01","source_type":"friendly_base","faction_id":"cao_cao","position":[1460,180],"radius":180}],1);_eq(reloaded.state.sources[intent.source_id].stock,{"fuel_basis_points":20000,"ammo_units":24,"supply_material_units":8},"base reload cannot restore destroyed ship share")
	var before:=JSON.stringify(destroyed.state);var replay:Dictionary=x.inventory.apply_authoritative_status(destroyed.state,destroyed_intent,1);_ok(not replay.ok and JSON.stringify(destroyed.state)==before,"stale revision rejects atomically")
	var captured:Dictionary=x.inventory.capture_source(destroyed.state,intent.source_id,1);_eq(captured.state.sources[intent.source_id].stock,{"fuel_basis_points":0,"ammo_units":0,"supply_material_units":0},"capture discards all stock");_eq(captured.event.captor_gain,0,"capture grants nothing")
func _test_consumption_reload_and_viewer()->void:
	var x:=_system();var source_id:="SUPPLY_SHIP-RC-LIU-SQ-02";var begun:Dictionary=x.inventory.begin_turn(x.state,1)
	var denied:Dictionary=x.inventory.authorize_refill(begun.state,source_id,"FC-A",{"fuel_basis_points":10001,"ammo_units":0,"supply_material_units":1},1);_ok(not denied.authorized and denied.reason=="inventory","insufficient full refill waits atomically")
	var consumed:Dictionary=x.inventory.authorize_refill(denied.state,source_id,"FC-B",{"fuel_basis_points":4000,"ammo_units":2,"supply_material_units":1},1);_ok(consumed.authorized,"next deterministic candidate can consume");_eq(consumed.state.sources[source_id].stock,{"fuel_basis_points":6000,"ammo_units":10,"supply_material_units":3},"actual deltas debit integrated stock")
	var nav:={};for squad in x.setup.squadrons:nav[String(squad.id)]={"position":squad.initial_position.duplicate()}
	nav["RC-LIU-SQ-02"].position=[120,780];var prior:=nav.duplicate(true);var moves=[{"squadron_id":"RC-LIU-SQ-02","actual_distance":0.0}];var bases=[{"source_id":"RC-BASE-LIU-01","source_type":"friendly_base","faction_id":"liu_bei","position":[120,780],"radius":180}]
	var reloaded:Dictionary=x.inventory.finish_base_reload(consumed.state,prior,nav,moves,bases,1);_eq(reloaded.state.sources[source_id].stock,reloaded.state.sources[source_id].maximum_stock,"same-faction stationary base reloads after outbound supply")
	var allied_bases=[{"source_id":"RC-BASE-SUN-01","source_type":"friendly_base","faction_id":"sun_quan","position":[120,780],"radius":180}];var not_allied:Dictionary=x.inventory.finish_base_reload(consumed.state,prior,nav,moves,allied_bases,1);_eq(not_allied.state.sources[source_id].stock,consumed.state.sources[source_id].stock,"allied base cannot reload another faction supply ship")
	var viewer:Dictionary=x.inventory.visible("liu_bei",reloaded.state);_eq(viewer.providers[0].faction_id,"liu_bei","viewer provider includes faction");_ok(viewer.providers[0].inventory.fuel.unit=="bp" and viewer.providers[0].inventory.ammo.unit=="units","viewer inventory schema uses frozen units");_ok(viewer.events.any(func(e):return e.status=="inventory_consumed") and viewer.events.any(func(e):return e.status=="base_reloaded"),"viewer exposes own safe events")
	var round_trip=JSON.parse_string(JSON.stringify(reloaded.state));_ok(x.inventory.begin_turn(round_trip,2).ok,"JSON-round-tripped inventory remains valid reducer input")
func _test_unused_integer_capacity_does_not_accumulate()->void:
	var x:=_system();var source_id:="SUPPLY_SHIP-RC-LIU-SQ-02";var state:Dictionary=x.state
	for turn in range(1,5):
		var begun:Dictionary=x.inventory.begin_turn(state,turn);_ok(begun.ok,"unused throughput turn %d begins"%turn);state=begun.state
		_eq(x.inventory.capacity(source_id,state),1,"unused whole slot does not accumulate on turn %d"%turn)
	var granted:=0
	for index in range(3):
		var result:Dictionary=x.inventory.authorize_refill(state,source_id,"FC-%d"%index,{"fuel_basis_points":0,"ammo_units":0,"supply_material_units":1},4);state=result.state
		if result.authorized:granted+=1
	_eq(granted,1,"normal one-ship provider cannot serve three candidates after three idle turns")
func _test_supply_full_refill_skip()->void:
	var x:=_system();var supply=Supply.new();_ok(supply.initialize(x.setup).ok,"supply integration initializes");var source_id:="SUPPLY_SHIP-RC-LIU-SQ-02";var inventory_state:Dictionary=x.state.duplicate(true);inventory_state.sources[source_id].stock.fuel_basis_points=5000
	var nav:={};for squad in x.setup.squadrons:nav[String(squad.id)]={"position":squad.initial_position.duplicate()}
	nav["RC-LIU-SQ-02"].position=[700,500];nav["FC-A"]={"position":[700,500]};nav["FC-B"]={"position":[700,500]}
	var state:={"resources":{"FC-A":{"squadron_id":"FC-A","faction_id":"liu_bei","fuel_basis_points":0,"maximum_basis_points":10000},"FC-B":{"squadron_id":"FC-B","faction_id":"liu_bei","fuel_basis_points":7000,"maximum_basis_points":10000}},"queue":{"FC-A":{"squadron_id":"FC-A","faction_id":"liu_bei","source_id":source_id,"entry_turn":1,"docked_turns":0},"FC-B":{"squadron_id":"FC-B","faction_id":"liu_bei","source_id":source_id,"entry_turn":1,"docked_turns":0}},"events_by_turn":{},"next_event_serial":1}
	var moves:Array=[];var ids:Array=nav.keys();ids.sort();for sid in ids:moves.append({"squadron_id":String(sid),"actual_distance":0.0})
	var result:Dictionary=supply.resolve(state,nav,nav,moves,1,[],[],inventory_state,{"FC-A":{"ammo_units":0},"FC-B":{"ammo_units":0}});_ok(result.ok,"inventory-aware supply resolves");_ok(result.events.any(func(e):return e.squadron_id=="FC-A" and e.status=="waiting_inventory"),"insufficient first candidate waits without partial refill");_ok(result.events.any(func(e):return e.squadron_id=="FC-B" and e.status=="completed"),"deterministic next candidate may complete");_eq(result.state.resources["FC-A"].fuel_basis_points,0,"failed candidate fuel is atomic");_eq(result.inventory_state.sources[source_id].stock.fuel_basis_points,2000,"successful next candidate debits exact fuel")
func _test_battle_integration()->void:
	var loaded:=Setup.load_default();var battle=Battle.new();var initialized:Dictionary=battle.initialize(loaded.setup);_ok(initialized.ok,"battle initializes: %s"%str(initialized.get("errors",[])))
	if not initialized.ok:return
	var initial_view:Dictionary=battle.viewer_supply_inventory("liu_bei");_ok(initial_view.providers.size()==1,"battle exposes own inventory only")
	var provider:Dictionary=initial_view.providers[0];_ok(_has_keys(provider,["faction_id","inventory","ship_status_counts","base_capacity_squadrons_per_turn","effective_throughput_basis_points_per_turn","available_capacity_squadrons_this_turn","automatic_supply_enabled","disabled_reason","reload"]) and not provider.has("effective_capacity_squadrons_per_turn"),"viewer provider separates weighted rate from current available capacity");_eq(provider.available_capacity_squadrons_this_turn,1,"battle turn one starts with throughput credit")
	var source_id:=String(provider.source_id);var damage_intent={"authority":"G8-00","status":"authorized_supply_ship_status","effective_turn":1,"source_id":source_id,"source_revision":0,"ship_status_counts":{"operational":0,"moderate_damage":1,"heavy_damage":0,"destroyed":0,"captured":0}}
	var damage:Dictionary=battle._apply_authoritative_supply_ship_status(damage_intent);_ok(damage.ok,"battle accepts G8-only damage status");var damaged_provider:Dictionary=battle.viewer_supply_inventory("liu_bei").providers[0];_eq(damaged_provider.inventory.fuel.current,10000,"damage preserves integrated stock");_eq(damaged_provider.effective_throughput_basis_points_per_turn,5000,"viewer exposes moderate-damage weighted rate");_eq(damaged_provider.available_capacity_squadrons_this_turn,0,"viewer exposes fractional rate as zero currently available whole slots")
	var before:=battle.digest();var malformed:=damage_intent.duplicate(true);malformed.source_revision=0;_ok(not battle._apply_authoritative_supply_ship_status(malformed).ok and battle.digest()==before,"stale G8 status leaves whole battle unchanged")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"battle reaches resolution");var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"inventory-integrated turn resolves: %s"%str(receipt.get("errors",[])))
	if receipt.ok:_ok(receipt.has("supply_inventory_events"),"turn receipt includes inventory events")
	var post_resolution:=battle.digest();var post_status:=damage_intent.duplicate(true);post_status.source_revision=1;_ok(not battle._apply_authoritative_supply_ship_status(post_status).ok and battle.digest()==post_resolution,"victory-check status intent is rejected without mutation");var post_capture={"authority":"G8-00","status":"authorized_capture","effective_turn":1,"source_id":source_id,"responder_squadron_id":"RC-CAO-SQ-01","responder_faction_id":"cao_cao"};_ok(not battle._apply_authoritative_supply_capture(post_capture).ok and battle.digest()==post_resolution,"victory-check capture intent is rejected without mutation")
	_ok(battle.continue_turn().ok,"battle continues to turn two");_eq(battle.snapshot().supply_inventory_state.sources[source_id].last_credit_turn,2,"continue_turn commits new-turn inventory credit immediately")
	var encoded:=JSON.stringify(battle.snapshot().supply_inventory_state);_ok(JSON.parse_string(encoded) is Dictionary,"inventory snapshot is save-safe")
	var capture_battle=Battle.new();_ok(capture_battle.initialize(loaded.setup).ok,"capture battle initializes");var capture={"authority":"G8-00","status":"authorized_capture","effective_turn":1,"source_id":"SUPPLY_SHIP-RC-LIU-SQ-02","responder_squadron_id":"RC-CAO-SQ-01","responder_faction_id":"cao_cao"};var captured:Dictionary=capture_battle._apply_authoritative_supply_capture(capture);_ok(captured.ok,"existing G8 capture atomically syncs inventory")
	if captured.ok:_eq(capture_battle.viewer_supply_inventory("liu_bei").providers[0].disabled_reason,"captured","captured viewer source is disabled");_eq(capture_battle.viewer_supply_inventory("liu_bei").providers[0].inventory.supply_materials.current,0,"captured inventory is discarded");_ok(capture_battle.viewer_fast_craft_recovery("liu_bei").disabled_supply_sources.size()==1,"recovery and inventory capture commit together")
	var terminal_battle=Battle.new();_ok(terminal_battle.initialize(loaded.setup).ok,"terminal phase battle initializes");terminal_battle._state.current_turn=20;terminal_battle._state.phase="turn_limit_reached";terminal_battle._state.resolved=true;var terminal_before:=terminal_battle.digest();var terminal_status=damage_intent.duplicate(true);terminal_status.effective_turn=20;_ok(not terminal_battle._apply_authoritative_supply_ship_status(terminal_status).ok and terminal_battle.digest()==terminal_before,"turn-limit status intent is rejected without mutation");var terminal_capture=capture.duplicate(true);terminal_capture.effective_turn=20;_ok(not terminal_battle._apply_authoritative_supply_capture(terminal_capture).ok and terminal_battle.digest()==terminal_before,"turn-limit capture intent is rejected without mutation")
func _has_keys(row:Dictionary,keys:Array)->bool:
	for key in keys:
		if not row.has(key):return false
	return true
