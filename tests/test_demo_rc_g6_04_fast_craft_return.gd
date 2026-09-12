extends SceneTree
## DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고
const Harness:=preload("res://tests/harness.gd")
const Setup:=preload("res://core/demo_red_cliffs/red_cliffs_demo_setup.gd")
const Supply:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_supply.gd")
const Return:=preload("res://core/demo_red_cliffs/red_cliffs_fast_craft_return.gd")
const Battle:=preload("res://core/demo_red_cliffs/red_cliffs_turn_battle.gd")
var _pass:=0;var _fail:=0
func _ok(v:bool,l:String)->void:
	if v:_pass+=1
	else:_fail+=1;print("  x %s"%l)
func _eq(a,e,l:String)->void:_ok(a==e,"%s (%s != %s)"%[l,str(a),str(e)])
func _init()->void:call_deferred("_run")
func _run()->void:
	print("DEMO-RC-G6-04 — 비상 귀환 기준·목적지 재탐색·조기 귀환·UI 경고")
	_test_scope_contract();_test_threshold_tie_retarget_and_risk();_test_boundary_distance();_test_early_cancel_and_fuel();_test_battle_override_and_viewer()
	print("PASS %d / FAIL %d"%[_pass,_fail]);quit(Harness.EXIT_FAIL if _fail else Harness.EXIT_PASS)
func _setup()->Dictionary:
	var loaded:=Setup.load_default();_ok(loaded.ok,"setup loads");return loaded.setup.duplicate(true)
func _nav(setup:Dictionary)->Dictionary:
	var out:={};for squad in setup.squadrons:out[String(squad.id)]={"position":squad.initial_position.duplicate(),"facing_deg":float(squad.get("initial_facing_deg",0))}
	return out
func _systems()->Dictionary:
	var setup:=_setup();var supply=Supply.new();var returns=Return.new();_ok(supply.initialize(setup).ok,"supply initializes");_ok(returns.initialize(setup).ok,"return initializes")
	var nav:=_nav(setup);return {"supply":supply,"returns":returns,"nav":nav,"supply_state":supply.initial_state(nav),"return_state":returns.initial_state()}
func _test_scope_contract()->void:
	var file:=FileAccess.open("res://data/red-cliffs-fast-craft-rules.json",FileAccess.READ);_ok(file!=null,"fast-craft rules open")
	var rules=JSON.parse_string(file.get_as_text())
	_ok(rules is Dictionary,"fast-craft rules parse")
	var excluded:Array=rules.get("out_of_scope",[])
	_ok(not excluded.has("automatic_return"),"implemented automatic return is not out of scope")
	_eq(excluded,["in_battle_equipment_change","non_rescue_tactical_mission_effect","supply_source_stock","supply_source_damage","base_reloading"],"remaining deferred mission and G6-06 effects stay out of scope")
func _test_threshold_tie_retarget_and_risk()->void:
	var x:=_systems();var sources:=[{"source_id":"SRC-B","faction_id":"liu_bei","position":[320,720]},{"source_id":"SRC-A","faction_id":"liu_bei","position":[120,720]}]
	# Both sources are exactly 100 distance from the craft; stable ID breaks tie.
	var status:Dictionary=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,sources,x.nav,60)
	_eq(status.nearest_source_id,"SRC-A","equal distance uses stable source ID")
	_eq(status.required_fuel_basis_points,1000,"distance converts to required fuel")
	_eq(status.reserve_fuel_basis_points,600,"reserve is one full movement turn")
	x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=1600;status=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,sources,x.nav,60)
	_ok(status.forced and status.status=="forced_return","threshold equality forces return")
	var planned:Dictionary=x.returns.plan(x.return_state,x.supply_state,sources,x.nav,{"RC-LIU-FC-01":60},1)
	_ok(planned.overrides.has("RC-LIU-FC-01"),"forced return produces movement override")
	var moved_sources:=[{"source_id":"SRC-B","faction_id":"liu_bei","position":[230,720]},{"source_id":"SRC-A","faction_id":"liu_bei","position":[600,720]}]
	x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=700
	var replanned:Dictionary=x.returns.plan(planned.state,x.supply_state,moved_sources,x.nav,{"RC-LIU-FC-01":60},2)
	_ok(replanned.events.any(func(e):return e.status=="retargeted" and e.source_id=="SRC-B"),"provider movement triggers deterministic retarget")
	x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=10
	var risk:Dictionary=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,sources,x.nav,60)
	_eq(risk.status,"stranded_risk","no reachable source is warning only")
	_eq(risk.route,[],"stranded risk fabricates no route or drift")
func _test_boundary_distance()->void:
	var x:=_systems();var sources:=[{"source_id":"SRC-B","faction_id":"liu_bei","position":[390,720],"radius":100},{"source_id":"SRC-A","faction_id":"liu_bei","position":[120,720],"radius":0}]
	var status:Dictionary=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,sources,x.nav,60)
	_eq(status.nearest_source_id,"SRC-B","selection sorts boundary fuel before center distance")
	_eq(status.required_fuel_basis_points,700,"required fuel stops at supply-zone boundary")
	_eq(status.route,[[290.0,720.0]],"route terminates on supply-zone boundary")
	var fractional:Dictionary=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,[{"source_id":"SRC-F","faction_id":"liu_bei","position":[320.05,720],"radius":20}],x.nav,60)
	_eq(fractional.required_fuel_basis_points,801,"fractional boundary distance fuel is rounded up")
func _test_early_cancel_and_fuel()->void:
	var x:=_systems();var sources=x.supply.source_zones(x.nav);var status:Dictionary=x.returns.status("RC-LIU-FC-01",x.return_state,x.supply_state,sources,x.nav,60)
	var early:Dictionary=x.returns.request_early(x.return_state,status,1);_ok(early.ok,"threshold-before early return accepted")
	var active:Dictionary=x.returns.status("RC-LIU-FC-01",early.state,x.supply_state,sources,x.nav,60);_ok(active.can_cancel and active.status=="early_return","early return remains cancellable")
	var cancelled:Dictionary=x.returns.cancel_early(early.state,active,1);_ok(cancelled.ok,"early return cancels")
	x.supply_state.resources["RC-LIU-FC-01"].fuel_basis_points=600;var forced:Dictionary=x.returns.status("RC-LIU-FC-01",cancelled.state,x.supply_state,sources,x.nav,60)
	_ok(forced.forced and not forced.can_cancel,"forced threshold cannot be cancelled")
	var consumed:Dictionary=x.returns.consume_fuel(x.supply_state,[{"squadron_id":"RC-LIU-FC-01","actual_distance":12.5}],1)
	_eq(consumed.state.resources["RC-LIU-FC-01"].fuel_basis_points,475,"actual movement distance consumes deterministic fuel")
	var fractional_consumed:Dictionary=x.returns.consume_fuel(x.supply_state,[{"squadron_id":"RC-LIU-FC-01","actual_distance":12.51}],1)
	_eq(fractional_consumed.events[0].fuel_used_basis_points,126,"fractional actual movement fuel is rounded up")
	var recorded:Dictionary=x.returns.record_fuel_events(cancelled.state,consumed.events,1)
	_eq(recorded.state.events_by_turn[1][-1].event_type,"fast_craft_fuel_consumed","fuel event is viewer-state persisted")
	var completed:Dictionary=x.returns.clear_completed(early.state,["RC-LIU-FC-01"])
	_ok(not completed.state.early_return_intents.has("RC-LIU-FC-01"),"supply completion clears early-return intent")
func _test_battle_override_and_viewer()->void:
	var battle=Battle.new();_ok(battle.initialize(_setup()).ok,"battle initializes")
	_ok(not battle.request_fast_craft_return("cao_cao","RC-LIU-FC-01").ok,"cross-faction early return rejected")
	var requested:Dictionary=battle.request_fast_craft_return("liu_bei","RC-LIU-FC-01");_ok(requested.ok,"Liu requests early return")
	_ok(battle.set_order_move("RC-LIU-FC-01",[[1000,720]],0).ok,"conflicting user movement stages")
	_ok(battle.submit_command_draft().ok and battle.submit_sun_control_choice("ai").ok,"turn reaches resolution")
	var receipt:Dictionary=battle.resolve_turn();_ok(receipt.ok,"turn resolves with return override")
	var return_event:Dictionary=receipt.fast_craft_return_events.filter(func(e):return e.squadron_id=="RC-LIU-FC-01")[0]
	_eq(return_event.status,"early_return","early return event explicit")
	_eq(receipt.movement_events.filter(func(e):return e.squadron_id=="RC-LIU-FC-01")[0].to,return_event.route[-1],"return route overrides conflicting movement")
	_ok(receipt.weapon_allocation_events.any(func(e):return e.squadron_id=="RC-LIU-FC-01" and e.hold_fire),"returning craft is forced to hold fire before authorization")
	var own:Dictionary=battle.viewer_fast_craft_returns("liu_bei");var hostile:Dictionary=battle.viewer_fast_craft_returns("cao_cao")
	_ok(own.events.any(func(e):return e.event_type=="fast_craft_fuel_consumed"),"viewer sees own authoritative fuel event")
	_eq(own.statuses.filter(func(row):return row.squadron_id=="RC-LIU-FC-01")[0].status,"normal","completed supply clears early return before next command")
	_eq(hostile.statuses.size(),0,"viewer cannot inspect hostile return status")
