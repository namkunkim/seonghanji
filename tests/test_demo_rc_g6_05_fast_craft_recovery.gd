extends SceneTree
## DEMO-RC-G6-05 — 표류·구조·나포와 나포 보급함 무력화
const Harness:=preload("res://tests/harness.gd")
const Setup:=preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Mission:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_mission.gd")
const Supply:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_supply.gd")
const Recovery:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_recovery.gd")
const Battle:=preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass:=0;var _fail:=0
func _ok(v:bool,label:String)->void:
	if v:_pass+=1
	else:_fail+=1;print("  x %s"%label)
func _eq(a,e,label:String)->void:_ok(a==e,"%s (%s != %s)"%[label,str(a),str(e)])
func _near(a:float,e:float,label:String)->void:_ok(is_equal_approx(a,e),"%s (%s != %s)"%[label,str(a),str(e)])
func _init()->void:call_deferred("_run")
func _run()->void:
	print("DEMO-RC-G6-05 — 표류·구조·나포와 나포 보급함 무력화")
	_test_clamp_drift_and_viewer();_test_capture_contact();_test_rescue_priority();_test_supply_capture_authority();_test_battle_zero_fuel_integration();_test_terminal_exclusion();_test_depleted_docked_reactivation();_test_ai_terminal_exclusion();_test_turn20_boundary_and_snapshot()
	print("PASS %d / FAIL %d"%[_pass,_fail]);quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)
func _systems()->Dictionary:
	var loaded:=Setup.load_default();_ok(loaded.ok,"setup loads");var setup:Dictionary=loaded.setup
	var recovery=Recovery.new();var supply=Supply.new();var mission=Mission.new();_ok(recovery.initialize(setup).ok,"recovery initializes");_ok(supply.initialize(setup).ok,"supply initializes");_ok(mission.initialize(setup).ok,"mission initializes")
	var nav:={};for squad in setup.squadrons:nav[String(squad.id)]={"position":squad.initial_position.duplicate(),"facing_deg":float(squad.get("initial_facing_deg",0))}
	return {"setup":setup,"recovery":recovery,"supply":supply,"mission":mission,"nav":nav,"state":recovery.initial_state(),"supply_state":supply.initial_state(nav),"mission_state":mission.initial_state()}
func _test_clamp_drift_and_viewer()->void:
	var x:=_systems();x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=405
	var orders:Array=[];for squad in x.setup.squadrons:orders.append({"squadron_id":String(squad.id),"action":"hold"})
	orders[orders.find_custom(func(row):return row.squadron_id=="RC-LIU-FC-01")]={"squadron_id":"RC-LIU-FC-01","action":"move","waypoints":[[1000,720]],"facing_deg":0.0}
	var prepared:Dictionary=x.recovery.prepare_orders(x.state,x.supply_state,orders,x.nav);_ok(prepared.ok,"orders prepare")
	_eq(prepared.orders.filter(func(row):return row.squadron_id=="RC-LIU-FC-01")[0].waypoints,[[260.5,720.0]],"fuel clamps route before movement")
	x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=0;x.nav["RC-LIU-FC-01"].position=[700,700]
	var moved=[{"squadron_id":"RC-LIU-FC-01","from":[660,700],"to":[700,700],"actual_distance":40.0,"terrain_segments":[{"from":[660,700],"to":[700,700],"length":40.0}]}]
	var changed:Dictionary=x.recovery.transition_after_fuel(x.state,x.supply_state,x.supply.source_zones(x.nav),x.nav,moved,1);_eq(changed.state.squadrons["RC-LIU-FC-01"].status,"drifting","zero fuel outside supply becomes drifting")
	var drifted:Dictionary=x.recovery.prepare_orders(changed.state,x.supply_state,orders,x.nav);_eq(drifted.orders.filter(func(row):return row.squadron_id=="RC-LIU-FC-01")[0].waypoints,[[740.0,700.0]],"existing drift moves 40 along last direction")
	var own:Dictionary=x.recovery.visible("liu_bei",changed.state,x.supply_state);var hostile:Dictionary=x.recovery.visible("cao_cao",changed.state,x.supply_state)
	_ok(own.statuses[0].command_locked and not own.statuses[0].can_attack,"own viewer receives authoritative command lock")
	_eq(hostile.statuses.size(),0,"hostile viewer receives no hidden status")
func _test_capture_contact()->void:
	var x:=_systems();var state:Dictionary=x.state.duplicate(true);state.squadrons["RC-LIU-FC-01"].status="drifting";state.squadrons["RC-LIU-FC-01"].drift_started_turn=1;state.squadrons["RC-LIU-FC-01"].drift_vector=[1.0,0.0];x.nav["RC-LIU-FC-01"].position=[730,300];x.nav["RC-CAO-SQ-01"].position=[700,300]
	var events:Array=[];for squad in x.setup.squadrons:events.append({"squadron_id":String(squad.id),"from":x.nav[String(squad.id)].position.duplicate(),"to":x.nav[String(squad.id)].position.duplicate(),"actual_distance":0.0,"terrain_segments":[]})
	events[events.find_custom(func(row):return row.squadron_id=="RC-LIU-FC-01")]={"squadron_id":"RC-LIU-FC-01","from":[650,300],"to":[730,300],"actual_distance":80.0,"terrain_segments":[{"from":[650,300],"to":[730,300],"length":80.0}]}
	var result:Dictionary=x.recovery.resolve_contacts(state,x.mission_state,x.nav,events,2);_eq(result.state.squadrons["RC-LIU-FC-01"].status,"captured","enemy operational responder captures eligible prior-turn drift")
	_eq(result.events[0].contact_progress,0.0,"holding responder catches target swept drift path")
	_ok(result.events[0].responder_route is Array and result.events[0].target_route is Array,"contact event exposes authoritative responder and target routes")
	var target_view:Dictionary=x.recovery.visible("liu_bei",result.state,x.supply_state,[],x.nav);_eq(target_view.events[0].responder_route,[],"own captured target cannot see hidden enemy responder route")
	var crossing:Dictionary=state.duplicate(true);var crossing_events:Array=events.duplicate(true);crossing_events[crossing_events.find_custom(func(row):return row.squadron_id=="RC-CAO-SQ-01")]={"squadron_id":"RC-CAO-SQ-01","from":[700,250],"to":[700,350],"actual_distance":100.0,"terrain_segments":[{"from":[700,250],"to":[700,350],"length":100.0}]};crossing_events[crossing_events.find_custom(func(row):return row.squadron_id=="RC-LIU-FC-01")]={"squadron_id":"RC-LIU-FC-01","from":[650,300],"to":[750,300],"actual_distance":100.0,"terrain_segments":[{"from":[650,300],"to":[750,300],"length":100.0}]};x.nav["RC-LIU-FC-01"].position=[750,300];x.nav["RC-CAO-SQ-01"].position=[700,350]
	var crossed:Dictionary=x.recovery.resolve_contacts(crossing,x.mission_state,x.nav,crossing_events,2);_eq(crossed.state.squadrons["RC-LIU-FC-01"].status,"captured","swept relative paths detect mid-turn crossing")
func _test_rescue_priority()->void:
	var loaded:=Setup.load_default();var setup:Dictionary=loaded.setup.duplicate(true);setup.squadrons.append({"id":"RC-LIU-FC-RESCUE","faction_id":"liu_bei","name":"구조 고속정대","commander":{"id":"CHR-0107","name":"관우"},"flagship":false,"operational":true,"initial_position":[700,300],"formation_id":"FRM-07","deployment":{"kind":"independent"},"fast_craft_basing":{"source_type":"base_deployed","source_id":"RC-BASE-LIU-01"},"composition":[{"ship_type_id":"SHP-08","count":1,"mission_equipment_id":"FAST-EQ-RESCUE"}],"declared_total_cost":3})
	var recovery=Recovery.new();var mission=Mission.new();_ok(recovery.initialize(setup).ok and mission.initialize(setup).ok,"rescue fixture initializes")
	var state:Dictionary=recovery.initial_state();state.squadrons["RC-LIU-FC-01"].status="drifting";state.squadrons["RC-LIU-FC-01"].drift_started_turn=1;state.squadrons["RC-LIU-FC-01"].drift_vector=[1.0,0.0]
	var nav:={};var events:Array=[];for squad in setup.squadrons:nav[String(squad.id)]={"position":[700,300],"facing_deg":0.0};events.append({"squadron_id":String(squad.id),"from":[700,300],"to":[700,300],"actual_distance":0.0,"terrain_segments":[]})
	var result:Dictionary=recovery.resolve_contacts(state,mission.initial_state(),nav,events,2);_eq(result.state.squadrons["RC-LIU-FC-01"].status,"rescued","exact contact tie resolves rescue before capture")
	_eq(result.state.squadrons["RC-LIU-FC-01"].responder_squadron_id,"RC-LIU-FC-RESCUE","rescue requires eligible rescue-equipped active mission craft")
	var capacity_state:Dictionary=recovery.initial_state();for sid in ["RC-LIU-FC-01","RC-LIU-FC-RESCUE"]:capacity_state.squadrons[sid].status="drifting";capacity_state.squadrons[sid].drift_vector=[1.0,0.0]
	capacity_state.squadrons["RC-LIU-FC-01"].drift_started_turn=2;capacity_state.squadrons["RC-LIU-FC-RESCUE"].drift_started_turn=1
	var capacity_result:Dictionary=recovery.resolve_contacts(capacity_state,mission.initial_state(),nav,events,3);_eq(capacity_result.state.squadrons["RC-LIU-FC-RESCUE"].status,"captured","earlier drift target has deterministic priority")
	_eq(capacity_result.state.squadrons["RC-LIU-FC-01"].status,"drifting","one responder handles at most one target per turn")
func _test_supply_capture_authority()->void:
	var x:=_systems();var sources:Array=x.supply.source_zones(x.nav);var source:Dictionary=sources.filter(func(row):return row.source_type=="supply_ship" and row.faction_id=="liu_bei")[0]
	var denied:Dictionary=x.recovery.apply_authoritative_supply_capture(x.state,{"source_id":source.source_id},sources,1);_ok(not denied.ok,"normal proximity cannot capture healthy supply source")
	var before:=JSON.stringify(x.state);var bad_faction:Dictionary=x.recovery.apply_authoritative_supply_capture(x.state,{"authority":"G8-00","status":"authorized_capture","effective_turn":1,"source_id":source.source_id,"responder_squadron_id":"RC-CAO-SQ-01","responder_faction_id":"liu_bei"},sources,1);_ok(not bad_faction.ok and JSON.stringify(x.state)==before,"mismatched responder faction rejects atomically")
	var friendly:Dictionary=x.recovery.apply_authoritative_supply_capture(x.state,{"authority":"G8-00","status":"authorized_capture","effective_turn":1,"source_id":source.source_id,"responder_squadron_id":"RC-LIU-SQ-01","responder_faction_id":"liu_bei"},sources,1);_ok(not friendly.ok,"friendly responder cannot capture supply source")
	var accepted:Dictionary=x.recovery.apply_authoritative_supply_capture(x.state,{"authority":"G8-00","status":"authorized_capture","effective_turn":1,"source_id":source.source_id,"responder_squadron_id":"RC-CAO-SQ-01","responder_faction_id":"cao_cao"},sources,1);_ok(accepted.ok,"G8 authority disables exact supply source")
	if not accepted.ok:return
	_eq(accepted.state.disabled_supply_sources[source.source_id].capacity_squadrons_per_turn,0,"captured supply source capacity is zero")
	_eq(accepted.event.captor_gain,0,"captor gains no G6-06 inventory")
	var filtered:Array=x.supply.source_zones(x.nav,x.recovery.disabled_source_ids(accepted.state));_ok(not filtered.any(func(row):return row.source_id==source.source_id),"captured exact supply source disappears")
	_ok(filtered.any(func(row):return row.source_type=="carrier") and filtered.any(func(row):return row.source_type=="friendly_base"),"carrier and base sources remain")
	x.nav["RC-LIU-FC-01"].position=source.position.duplicate();var supply_state:Dictionary=x.supply.initial_state(x.nav);supply_state.queue["RC-LIU-FC-01"]={"squadron_id":"RC-LIU-FC-01","faction_id":"liu_bei","source_id":source.source_id,"entry_turn":1,"docked_turns":1};var holds:Array=[];for squad in x.setup.squadrons:holds.append({"squadron_id":String(squad.id),"actual_distance":0.0})
	var interrupted:Dictionary=x.supply.resolve(supply_state,x.nav,x.nav,holds,1,x.recovery.disabled_source_ids(accepted.state));_ok(interrupted.ok,"supply resolves after source capture")
	_ok(interrupted.events.any(func(row):return row.status=="interrupted" and row.reason=="source_captured") and not interrupted.events.any(func(row):return row.status=="completed" and row.source_id==source.source_id),"captured source interrupts queue and grants no refill")
	var observed_state:Dictionary=x.state.duplicate(true);observed_state.squadrons["RC-LIU-FC-01"].status="captured";var confirmed:Dictionary=x.recovery.visible("cao_cao",observed_state,x.supply_state,[{"recovery_target_id":"RC-LIU-FC-01","target_squadron_id":"RC-LIU-FC-01","contact_id":"CONTACT-X","state":"confirmed","display_position":[700,700],"error_radius":0,"confidence_basis_points":10000,"staleness_turns":0}]);_eq(confirmed.statuses[0].squadron_id,"RC-LIU-FC-01","confirmed recovery contact exposes exact ID")
	var estimated:Dictionary=x.recovery.visible("cao_cao",observed_state,x.supply_state,[{"recovery_target_id":"RC-LIU-FC-01","contact_id":"CONTACT-X","state":"estimated","display_position":[680,690],"error_radius":40,"confidence_basis_points":6000,"staleness_turns":1}]);_eq(estimated.statuses[0].squadron_id,"","estimated recovery contact redacts exact ID")
	_eq(estimated.statuses[0].viewer_state,"estimated","estimated viewer state and uncertainty are explicit")
func _test_battle_zero_fuel_integration()->void:
	var loaded:=Setup.load_default();var battle=Battle.new();_ok(battle.initialize(loaded.setup).ok,"battle initializes with recovery")
	battle._state.live_navigation["RC-LIU-FC-01"].position=[700,700];battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=405;battle._state.fast_craft_supply_state.queue.erase("RC-LIU-FC-01")
	var preview:Dictionary=battle.movement_preview("RC-LIU-FC-01",[[1000,700]],0)
	_ok(preview.ok and preview.fuel_limited,"low-fuel preview exposes authoritative clamp")
	_eq(preview.available_fuel_basis_points,405,"preview exposes available fuel");_near(preview.maximum_fuel_distance,40.5,"preview exposes maximum fuel distance")
	_near(preview.requested_total_distance,300.0,"preview preserves requested distance");_near(preview.predicted_actual_distance,40.5,"preview predicts clamped actual distance")
	_near(float(preview.predicted_position[0]),740.5,"preview predicts clamped endpoint");_eq(preview.effective_waypoints,[[740.5,700.0]],"preview exposes effective clamped waypoints")
	_ok(not preview.path_complete and preview.eta_turns==-1,"fuel-limited path is explicitly incomplete")
	_ok(battle.set_order_move("RC-LIU-FC-01",[[1000,700]],0).ok,"long movement stages before clamp")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"battle reaches recovery resolution")
	var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"recovery-integrated turn resolves")
	if not receipt.ok:return
	var movement:Dictionary=receipt.movement_events.filter(func(row):return row.squadron_id=="RC-LIU-FC-01")[0]
	_ok(float(movement.actual_distance)<=40.500001,"actual movement never exceeds remaining fuel distance")
	_near(float(movement.actual_distance),preview.predicted_actual_distance,"preview distance matches authoritative resolve");_eq(movement.to,preview.predicted_position,"preview endpoint matches authoritative resolve")
	_eq(battle.snapshot().fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points,0,"clamped movement consumes remaining fuel exactly")
	_ok(receipt.fast_craft_recovery_events.any(func(row):return row.status=="drifting"),"zero fuel outside zone becomes newly drifting in battle")
	_ok(not receipt.opportunity_fire_events.any(func(row):return String(row.get("shooter_squadron_id",""))=="RC-LIU-FC-01") and not receipt.estimated_fire_events.any(func(row):return String(row.get("shooter_squadron_id",""))=="RC-LIU-FC-01"),"newly drifting craft has no actual estimated or opportunity fire")
	var viewer:Dictionary=battle.viewer_fast_craft_recovery("liu_bei");_ok(viewer.statuses[0].command_locked,"battle viewer exposes command lock");_eq(viewer.statuses[0].display_position,movement.to,"locked own drift marker keeps authoritative map position")
	_ok(battle.continue_turn().ok,"second turn starts")
	_ok(not battle.movement_preview("RC-LIU-FC-01",[[900,700]],0).ok,"recovery-locked movement preview is rejected")
	_ok(not battle.set_order_move("RC-LIU-FC-01",[[900,700]],0).ok,"drifting public movement mutation is rejected")
func _test_terminal_exclusion()->void:
	var loaded:=Setup.load_default();var battle=Battle.new();_ok(battle.initialize(loaded.setup).ok,"terminal fixture battle initializes")
	battle._state.fast_craft_recovery_state.squadrons["RC-LIU-FC-01"].status="captured";battle._state.fast_craft_recovery_state.squadrons["RC-LIU-FC-01"].resolved_turn=1
	_eq(battle.viewer_fast_craft_returns("liu_bei").statuses.size(),0,"terminal craft has no phantom return status")
	_ok(not battle.request_fast_craft_return("liu_bei","RC-LIU-FC-01").ok and not battle.set_fast_craft_mission("liu_bei","RC-LIU-FC-01","recon").ok,"terminal return and mission mutations reject")
	_ok(not battle.set_formation_order("RC-LIU-FC-01","FRM-01").ok and not battle.set_hold_fire("RC-LIU-FC-01",false).ok,"terminal formation and weapon mutations reject")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"terminal placeholder orders still resolve internally")
	var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"terminal exclusion turn resolves")
	if not receipt.ok:return
	_ok(not receipt.fast_craft_return_events.any(func(row):return String(row.get("squadron_id",""))=="RC-LIU-FC-01"),"terminal craft creates no return event")
	_ok(not receipt.opportunity_fire_events.any(func(row):return String(row.get("shooter_squadron_id",""))=="RC-LIU-FC-01" or String(row.get("target_squadron_id",""))=="RC-LIU-FC-01"),"terminal craft excluded from authorized shot endpoints")
	_ok(not battle.snapshot().detection_state.values().any(func(row):return String(row.get("observer_squadron_id",""))=="RC-LIU-FC-01" or String(row.get("target_squadron_id",""))=="RC-LIU-FC-01"),"terminal craft excluded from persisted detection candidates")
func _test_depleted_docked_reactivation()->void:
	var loaded:=Setup.load_default();var battle=Battle.new();_ok(battle.initialize(loaded.setup).ok,"depleted dock fixture initializes")
	battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=0
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"depleted dock reaches resolution")
	var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"depleted dock resolution completes")
	if not receipt.ok:return
	_ok(receipt.fast_craft_recovery_events.any(func(row):return row.status=="depleted_docked"),"inside-zone zero fuel enters locked depleted dock state")
	_ok(receipt.fast_craft_supply_events.any(func(row):return row.squadron_id=="RC-LIU-FC-01" and row.status=="completed"),"G6-03 dwell completes depleted dock supply")
	_eq(battle.viewer_fast_craft_recovery("liu_bei").statuses[0].status,"active","completed supply atomically restores active state")
	_ok(battle.continue_turn().ok and battle.set_order_hold("RC-LIU-FC-01").ok,"restored craft is commandable next turn")
func _test_ai_terminal_exclusion()->void:
	var loaded:=Setup.load_default();var setup:Dictionary=loaded.setup.duplicate(true);setup.squadrons.append({"id":"RC-CAO-FC-01","faction_id":"cao_cao","name":"조조 요격 고속정대","commander":{"id":"CHR-0033","name":"조인"},"flagship":false,"operational":true,"initial_position":[900,330],"formation_id":"FRM-07","deployment":{"kind":"independent"},"fast_craft_basing":{"source_type":"independent","source_id":""},"composition":[{"ship_type_id":"SHP-08","count":1,"mission_equipment_id":"FAST-EQ-INTERCEPT"}],"declared_total_cost":3})
	var battle=Battle.new();_ok(battle.initialize(setup).ok,"AI terminal fixture initializes");battle._state.fast_craft_recovery_state.squadrons["RC-CAO-FC-01"].status="captured";battle._state.fast_craft_recovery_state.squadrons["RC-CAO-FC-01"].resolved_turn=1
	var mission_before:String=battle._state.fast_craft_mission_state.active["RC-CAO-FC-01"].mission_id
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"AI prepares with terminal craft")
	var decision:Dictionary=battle.viewer_ai_decision("cao_cao");_ok(decision.ok and decision.available,"AI decision receipt available")
	_ok(not decision.orders.any(func(row):return String(row.squadron_id)=="RC-CAO-FC-01") and not decision.weapon_allocation_orders.any(func(row):return String(row.squadron_id)=="RC-CAO-FC-01"),"AI decision exposes no terminal movement or weapon intent")
	_eq(battle._state.fast_craft_mission_state.active["RC-CAO-FC-01"].mission_id,mission_before,"AI terminal mission remains unchanged")
	_ok(not battle.viewer_snapshot("cao_cao").own_squadrons.any(func(row):return String(row.id)=="RC-CAO-FC-01"),"AI own planning snapshot removes terminal craft")
	var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"AI terminal turn resolves with internal placeholders")
	if receipt.ok:_ok(not receipt.opportunity_fire_events.any(func(row):return String(row.get("shooter_squadron_id",""))=="RC-CAO-FC-01" or String(row.get("target_squadron_id",""))=="RC-CAO-FC-01"),"AI terminal craft has no fire endpoint")
func _test_turn20_boundary_and_snapshot()->void:
	var loaded:=Setup.load_default();var battle=Battle.new();_ok(battle.initialize(loaded.setup).ok,"turn20 fixture initializes");battle._state.current_turn=20;battle._state.turn_log[0].turn=20;battle._state.live_navigation["RC-LIU-FC-01"].position=[700,700];battle._state.fast_craft_supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=0;battle._state.fast_craft_supply_state.queue.erase("RC-LIU-FC-01")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"turn20 reaches resolution");var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok and battle.phase()=="turn_limit_reached","turn20 records recovery before terminal boundary")
	_ok(not battle.continue_turn().ok,"turn21 drift cannot execute")
	var encoded:=JSON.stringify(battle.snapshot().fast_craft_recovery_state);_ok(JSON.parse_string(encoded) is Dictionary,"recovery snapshot is save-serializable primitive state")
