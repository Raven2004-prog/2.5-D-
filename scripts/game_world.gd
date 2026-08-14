extends Node2D
class_name GreyfenGameWorld

signal autosave_requested(data: Dictionary)
signal story_completed(state: AshGameState)
signal return_to_title_requested

const MapScene := preload("res://scripts/world_map.gd")
const PlayerScene := preload("res://scripts/player.gd")
const NpcScene := preload("res://scripts/npc.gd")
const EnemyScene := preload("res://scripts/enemy_agent.gd")
const HotspotScene := preload("res://scripts/hotspot.gd")
const UIScene := preload("res://scripts/game_ui.gd")
const RainScene := preload("res://scripts/rain_overlay.gd")
const Content := preload("res://scripts/story_content.gd")

const FOUNDATION_NAMES := {
	"powder": "Powder beneath the refugee granary",
	"signal": "A counterfeit cadence in the west horn",
	"gate": "A deliberately jammed water gate",
}

var game_state: AshGameState
var world_map: GreyfenMap
var player: PlayerActor
var ui: GameUI
var rain: RainOverlay

var npcs: Dictionary = {}
var hotspots: Dictionary = {}
var agents: Array[EnemyAgent] = []
var nearest_interactable: Node2D

var _interaction_tick := 0.0
var _pending_return: Dictionary = {}
var _finale_remaining := 0.0
var _finale_events: Dictionary = {}
var _stage_before_dialogue := ""
var _started := false


func configure(state: AshGameState) -> void:
	game_state = state


func _ready() -> void:
	if game_state == null:
		game_state = AshGameState.new()
	_build_world()
	call_deferred("_begin_current_stage")


func _process(delta: float) -> void:
	if not _started:
		return
	_interaction_tick -= delta
	if _interaction_tick <= 0.0:
		_interaction_tick = 0.08
		_update_nearest_interactable()
	if _stage() == "finale_defense" and not ui.dialogue_open and not ui.folio_open:
		_tick_finale(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("folio") and not ui.dialogue_open:
		if ui.folio_open:
			ui.hide_folio()
		else:
			_open_folio()
		get_viewport().set_input_as_handled()


func _build_world() -> void:
	var modulate := CanvasModulate.new()
	modulate.color = Color("b8c1c3")
	add_child(modulate)

	world_map = MapScene.new()
	add_child(world_map)

	player = PlayerScene.new()
	player.name = "Evan"
	player.position = _saved_or_anchor_position()
	player.health_changed.connect(_on_health_changed)
	player.stamina_changed.connect(_on_stamina_changed)
	player.interact_requested.connect(_interact)
	player.focus_changed.connect(_on_focus_changed)
	player.defeated.connect(_on_player_defeated)
	player.shove_emitted.connect(_on_player_shove)
	add_child(player)

	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.5
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(GreyfenMap.WORLD_SIZE.x)
	camera.limit_bottom = int(GreyfenMap.WORLD_SIZE.y)
	player.add_child(camera)
	camera.make_current()

	_build_npcs()
	_build_hotspots()
	_build_agents()

	var rain_canvas := CanvasLayer.new()
	rain_canvas.layer = 15
	add_child(rain_canvas)
	rain = RainScene.new()
	rain.reduced_motion = bool(game_state.settings.get("reduce_motion", false))
	rain.intensity = float(game_state.settings.get("rain_intensity", 1.0))
	rain_canvas.add_child(rain)

	ui = UIScene.new()
	ui.dialogue_finished.connect(_on_dialogue_finished)
	ui.dialogue_choice.connect(_on_dialogue_choice)
	ui.folio_closed.connect(_on_folio_closed)
	ui.pause_requested.connect(_on_pause_requested)
	add_child(ui)
	ui.set_condition(player.health, PlayerActor.MAX_HEALTH, player.stamina, PlayerActor.MAX_STAMINA)
	_refresh_world_state()


func _build_npcs() -> void:
	_add_npc("mara", "Mara", "Warden of Greyfen", Color("58636a"), Color("d49a45"), world_map.get_landmark("mara"))
	_add_npc("tamsin", "Tamsin", "Captain", Color("394950"), Color("91aeb5"), world_map.get_landmark("tamsin"))
	_add_npc("lysa", "Lysa", "Courier", Color("5c4e66"), Color("c77955"), world_map.get_landmark("lysa"))
	_add_npc("nessa", "Nessa", "Surgeon", Color("45625f"), Color("87b8a2"), world_map.get_landmark("nessa"))
	_add_npc("brann", "Brann", "Gate commander", Color("5a5147"), Color("c3a15e"), world_map.get_landmark("brann"))
	_add_npc("kesh", "Kesh", "Aruun envoy", Color("514b61"), Color("db7045"), world_map.get_landmark("kesh"), true)
	_add_npc("piri", "Piri", "Signal apprentice", Color("4b5c68"), Color("dfa750"), world_map.get_landmark("piri"), true)
	_add_npc("tomas", "Tomas", "Quartermaster", Color("675b4a"), Color("c7834d"), world_map.get_landmark("tomas"))


func _add_npc(id: String, name_text: String, role_text: String, color: Color, accent: Color, at: Vector2, daevar: bool = false) -> void:
	var npc := NpcScene.new()
	npc.configure(id, name_text, role_text, color, accent, daevar)
	npc.position = at
	npcs[id] = npc
	add_child(npc)


func _build_hotspots() -> void:
	_add_hotspot("powder", "Granary undercroft", "Inspect the disturbed floorboards", Color("d28a49"), world_map.get_landmark("granary") + Vector2(0, 8))
	_add_hotspot("signal", "Signal horn", "Compare the horn assembly", Color("e0b25c"), world_map.get_landmark("piri") + Vector2(0, -25))
	_add_hotspot("gate", "Water-gate wheel", "Inspect the jammed gearing", Color("62a6aa"), world_map.get_landmark("water_gate") + Vector2(-72, 0))
	_add_hotspot("tunnel", "Drainage prints", "Trace the tunnel buyer's route", Color("af7a63"), world_map.get_landmark("tunnel"))


func _add_hotspot(id: String, label_text: String, prompt: String, color: Color, at: Vector2) -> void:
	var hotspot := HotspotScene.new()
	hotspot.configure(id, label_text, prompt, color)
	hotspot.position = at
	hotspots[id] = hotspot
	add_child(hotspot)


func _build_agents() -> void:
	_add_agent("West-road observer", PackedVector2Array([Vector2(360, 730), Vector2(560, 820), Vector2(680, 735), Vector2(520, 570)]))
	_add_agent("Granary watch", PackedVector2Array([Vector2(1160, 610), Vector2(1440, 660), Vector2(1540, 600), Vector2(1280, 690)]))
	_add_agent("Tunnel buyer", PackedVector2Array([Vector2(980, 970), Vector2(1180, 1000), Vector2(1270, 900), Vector2(1040, 850)]))
	_add_agent("Signal runner", PackedVector2Array([Vector2(875, 420), Vector2(1120, 375), Vector2(1160, 560), Vector2(920, 575)]))


func _add_agent(name_text: String, points: PackedVector2Array) -> void:
	var agent := EnemyScene.new()
	agent.configure(player, points, name_text)
	agent.surrendered.connect(_on_agent_surrendered)
	agents.append(agent)
	add_child(agent)


func _begin_current_stage() -> void:
	_started = true
	var stage := _stage()
	match stage:
		"arrival":
			ui.set_chapter("Chapter 1", "The Blink")
			ui.set_clock("4:20 PM", "THE FIRST RAIN")
			_show_story("intro_earth")
		"return_one":
			ui.set_chapter("Chapter 4", "The Same Rain")
			ui.set_clock("4:20 PM", "PASS TWO")
			_show_story("return_one")
		"return_two":
			ui.set_chapter("Chapter 6", "Three Hands on the Knife")
			ui.set_clock("4:20 PM", "PASS THREE")
			_show_story("return_two")
		"return_three":
			ui.set_chapter("Chapter 10", "No One Owes Him Yesterday")
			ui.set_clock("4:20 PM", "THE SURVIVING LINE")
			_show_story("return_three")
		"finale_to_tomas", "finale_defense":
			ui.set_chapter("Chapter 12", "Six People Break the Pattern")
			ui.set_clock("BEFORE THE HORN", "FINAL OPERATION")
			if stage == "finale_defense":
				_finale_remaining = maxf(5.0, float(game_state.current_line.get("finale_time", 36.0)))
				_activate_finale_agents()
			else:
				_set_objective_for_stage()
		"complete":
			_show_story("ending")
		_:
			_set_objective_for_stage()
	_refresh_world_state()


func _stage() -> String:
	return str(game_state.current_line.get("stage", "arrival"))


func _set_stage(value: String) -> void:
	game_state.current_line["stage"] = value
	_set_objective_for_stage()
	_refresh_world_state()
	_autosave()


func _set_objective_for_stage() -> void:
	match _stage():
		"arrival":
			ui.set_objective("Find the fleeing courier", "A girl in a red scarf crossed the hollow ahead.")
		"reach_mara":
			ui.set_objective("Bring the bloodied token to Greyfen", "Mara is below the Grey Keep. Follow the amber ward-lights.")
		"baseline_find_granary":
			ui.set_objective("Reach Refuge Row", "Someone is moving powder beneath the granary.")
		"return_one":
			ui.set_objective("Make Brann listen", "One prediction must be specific enough to verify.")
		"one_fuse":
			ui.set_objective("Stop the granary charge", "You remember the loose undercroft boards.")
		"one_fuse_report":
			ui.set_objective("Report to Mara", "The powder is safe. The rest of the pattern is not.")
		"return_two":
			ui.set_objective("Reconstruct the three-part attack", "%d of 3 foundations recorded in this line." % game_state.present_foundation_count())
		"wrong_hero_report":
			ui.set_objective("Give Mara your complete plan", "You know the routes. You have not asked who will risk them.")
		"return_three":
			var ready := game_state.contribution_count()
			ui.set_objective("Build a plan people choose", "%d/3 present facts · %d/5 allies ready before Mara." % [game_state.present_foundation_count(), mini(ready, 5)])
		"mara_ready":
			ui.set_objective("Tell Mara what is fact—and what is fear", "No one owes you a relationship from an erased line.")
		"finale_to_tomas":
			ui.set_objective("Reach Tomas beneath the granary", "The coerced sapper can still choose to stop.")
		"finale_defense":
			ui.set_objective("Keep Tomas alive", "Hold long enough for six independent choices to break the pattern.")
		"tribunal":
			ui.set_objective("Give one surviving account", "The dead and the living both deserve accurate names.")


func _update_nearest_interactable() -> void:
	if ui.dialogue_open or ui.folio_open or not player.controls_enabled:
		ui.show_prompt("")
		return
	var best: Node2D
	var best_distance := 78.0
	for npc_value in npcs.values():
		var npc := npc_value as NpcActor
		if not npc.available:
			continue
		var distance := player.global_position.distance_to(npc.global_position)
		if distance < best_distance:
			best = npc
			best_distance = distance
	for hotspot_value in hotspots.values():
		var hotspot := hotspot_value as EvidenceHotspot
		if not hotspot.available:
			continue
		var distance := player.global_position.distance_to(hotspot.global_position)
		if distance < best_distance:
			best = hotspot
			best_distance = distance
	nearest_interactable = best
	for hotspot_value in hotspots.values():
		(hotspot_value as EvidenceHotspot).set_active(hotspot_value == nearest_interactable or player.focus_active)
	for npc_value in npcs.values():
		var npc := npc_value as NpcActor
		npc.set_highlighted(npc_value == nearest_interactable or (player.focus_active and _npc_has_available_action(npc.npc_id)))
	if nearest_interactable is NpcActor:
		var npc := nearest_interactable as NpcActor
		ui.show_prompt("E  TALK TO %s" % npc.display_name.to_upper())
	elif nearest_interactable is EvidenceHotspot:
		var hotspot := nearest_interactable as EvidenceHotspot
		ui.show_prompt("E  %s" % hotspot.prompt_text.to_upper())
	else:
		ui.show_prompt("")


func _interact() -> void:
	if ui.dialogue_open:
		ui.advance_dialogue()
		return
	if ui.folio_open or nearest_interactable == null:
		return
	if nearest_interactable is NpcActor:
		_interact_npc(nearest_interactable as NpcActor)
	elif nearest_interactable is EvidenceHotspot:
		_interact_hotspot(nearest_interactable as EvidenceHotspot)


func _interact_npc(npc: NpcActor) -> void:
	match npc.npc_id:
		"lysa": _talk_lysa()
		"mara": _talk_mara()
		"brann": _talk_brann()
		"piri": _talk_piri()
		"nessa": _talk_nessa()
		"kesh": _talk_kesh()
		"tamsin": _talk_tamsin()
		"tomas": _talk_tomas()


func _talk_lysa() -> void:
	if _stage() == "arrival" and not game_state.has_item("token"):
		_show_story("lysa_token")
	elif _stage() == "return_three" and game_state.has_physical_evidence("tunnel") and not game_state.has_contribution("lysa"):
		_show_story("lysa_contribution")
	else:
		_say("lysa_bark", "Lysa", "Greyfen courier", [
			"You have the expression of a man arguing with a map. Maps usually win.",
			"If you need a route, ask. If you already know one you should not, ask more carefully."
		])


func _talk_mara() -> void:
	match _stage():
		"reach_mara":
			if game_state.has_item("token"):
				_show_story("mara_arrest")
		"one_fuse_report":
			_trigger_authored_return(
				"catastrophe_two", "Corvin's knife after the clinic blast",
				"Stopping one fuse moved the fire to Nessa's clinic. Corvin asked what I remembered.",
				"phantom_knife", "return_two"
			)
		"wrong_hero_report":
			_show_story("wrong_hero")
		"mara_ready":
			_show_story("mara_disclosure", [
				{"id": "separate_fact", "text": "Separate fact from inference. Ask what risk she accepts."},
				{"id": "claim_control", "text": "Insist that only your complete plan can save everyone."}
			])
		"return_three":
			if game_state.all_foundations_present() and _first_five_ready():
				_set_stage("mara_ready")
				_talk_mara()
			else:
				_say("mara_status", "Mara", "Warden of Greyfen", [
					"Fact first. Then tell me who has seen it in this line. I will not stake Greyfen on a memory no one else can examine."
				])
		_:
			_say("mara_bark", "Mara", "Warden of Greyfen", ["Tell me what fails first. Fear can wait until people are moving."])


func _talk_brann() -> void:
	if _stage() == "return_one" and not game_state.has_flag("brann_prediction"):
		_show_story("brann_prediction")
	elif _stage() == "return_three" and game_state.has_physical_evidence("gate") and not game_state.has_contribution("brann"):
		_show_story("brann_contribution")
	else:
		_say("brann_bark", "Brann", "Gate commander", ["Two royal orders contradicting each other before supper. Untidy."])


func _talk_piri() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("signal") and not game_state.has_contribution("piri"):
		_show_story("piri_contribution")
	else:
		_say("piri_bark", "Piri", "Signal apprentice", ["Signal manual, page forty-two: do not improvise cadence during rain. Stars and cinders, no one reads page forty-two."])


func _talk_nessa() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("powder") and not game_state.has_contribution("nessa"):
		_show_story("nessa_contribution")
	else:
		_say("nessa_bark", "Nessa", "Border surgeon", ["Feet first, prophecy second. Bleeding is not an argument."])


func _talk_kesh() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("gate") and not game_state.has_contribution("kesh"):
		_show_story("kesh_contribution")
	else:
		_say("kesh_bark", "Kesh", "Aruun envoy", ["Daevar is the word. If someone intends an insult, they should at least have the courage to choose it themselves."])


func _talk_tamsin() -> void:
	_say("tamsin_bark", "Tamsin", "Mara's captain", [
		"Who told you? Who benefits? Why now?",
		"One prediction earns attention, Hale. Trust costs more."
	])


func _talk_tomas() -> void:
	if _stage() == "finale_to_tomas" and not game_state.has_flag("tomas_surrendered"):
		_show_story("tomas_surrender", [
			{"id": "offer_exit", "text": "Name the harm. Offer him a way to surrender."},
			{"id": "threaten", "text": "Tell him you know where his captors keep his husband."}
		])
	elif _stage() == "finale_defense":
		_say("tomas_hold", "Tomas", "Coerced quartermaster", ["Six powder kegs. Two keys. Thirty breaths until they realize I have stopped. I am sorry—that is not enough. I know."])
	else:
		_say("tomas_bark", "Tomas", "Quartermaster", ["Stores are closed by order of the magistrate. No, I do not know when they reopen."])


func _interact_hotspot(hotspot: EvidenceHotspot) -> void:
	if not hotspot.available:
		return
	match hotspot.hotspot_id:
		"powder": _inspect_foundation("powder", "powder_discovery")
		"signal": _inspect_foundation("signal", "signal_discovery")
		"gate": _inspect_foundation("gate", "gate_discovery")
		"tunnel":
			if _stage() != "return_three":
				ui.notify("Only ordinary drainage marks—until you know which route matters.")
				return
			if game_state.add_physical_evidence("tunnel"):
				game_state.remember("tunnel", "The tunnel buyer used Lysa's route and paid in clipped border coin.")
				hotspot.set_discovered(true)
				ui.notify("Present-line evidence: the tunnel buyer's route")
				_autosave()
			else:
				ui.notify("You have already traced these prints in this line.")
	_refresh_world_state()


func _inspect_foundation(id: String, dialogue_id: String) -> void:
	var stage := _stage()
	if id != "powder" and stage not in ["return_two", "return_three", "wrong_hero_report", "mara_ready"]:
		ui.notify("You do not yet know what detail to look for.")
		return
	if id == "powder" and stage not in ["baseline_find_granary", "one_fuse", "return_two", "return_three", "wrong_hero_report", "mara_ready"]:
		ui.notify("The floorboards look ordinary from here.")
		return
	var newly_present := game_state.add_physical_evidence(id)
	game_state.remember(id, FOUNDATION_NAMES[id])
	(hotspots[id] as EvidenceHotspot).set_discovered(true)
	if newly_present:
		_show_story(dialogue_id)
	else:
		ui.notify("Already recorded in this line: %s" % FOUNDATION_NAMES[id])
	_refresh_world_state()
	_autosave()


func _on_dialogue_finished(id: String) -> void:
	player.controls_enabled = true
	if _pending_return.get("dialogue_id", "") == id:
		_perform_return()
		return
	match id:
		"intro_earth":
			_show_story("arrival")
		"arrival":
			game_state.retained["g0_formed"] = true
			_set_objective_for_stage()
		"lysa_token":
			game_state.add_inventory("token")
			game_state.remember("token", "Lysa pressed a bloodied courier token into my hand.")
			_set_stage("reach_mara")
		"mara_arrest":
			_set_stage("baseline_find_granary")
		"powder_discovery":
			if _stage() == "baseline_find_granary":
				_trigger_authored_return(
					"catastrophe_one", "Crushed beneath the refugee granary",
					"The false horn moved the garrison. The water gate jammed. Mara died opening Refuge Row. Then the granary fell.",
					"crushing_and_smoke", "return_one"
				)
			elif _stage() == "one_fuse":
				_set_stage("one_fuse_report")
			elif _stage() == "return_two":
				_check_investigation_complete()
			elif _stage() == "return_three":
				_refresh_fourth_pass_objective()
		"signal_discovery", "gate_discovery":
			if _stage() == "return_two":
				_check_investigation_complete()
			elif _stage() == "return_three":
				_refresh_fourth_pass_objective()
		"brann_prediction":
			game_state.add_flag("brann_prediction")
			game_state.set_npc_tag("brann", "listened_to_prediction")
			_set_stage("one_fuse")
		"wrong_hero":
			_trigger_authored_return(
				"catastrophe_three", "Deliberately remained beneath the secondary collapse",
				"Lysa knew I remembered the danger and chose her route anyway. She died in a plan she never accepted.",
				"lysa_erased_grief", "return_three"
			)
		"nessa_contribution": _accept_contribution("nessa", "Nessa chose to move the clinic before the alarm.")
		"piri_contribution": _accept_contribution("piri", "Piri chose to mark and counter the false cadence.")
		"brann_contribution": _accept_contribution("brann", "Brann chose to reject the forged withdrawal in public.")
		"kesh_contribution": _accept_contribution("kesh", "Kesh chose to bring the refugees inside Greyfen's wall.")
		"lysa_contribution": _accept_contribution("lysa", "Lysa chose to expose the tunnel buyer on her own route.")
		"ash_compact":
			game_state.remember("ash_witness", "Mara staked her claim and public liability on Evan and Kesh's testimony.")
			_set_stage("finale_to_tomas")
		"corvin_lens":
			_set_stage("tribunal")
			_show_story("tribunal")
		"tribunal":
			game_state.retained["g1_formed"] = true
			game_state.current_line["stage"] = "complete"
			_autosave()
			_show_story("ending")
		"ending":
			story_completed.emit(game_state)
	_refresh_world_state()


func _on_dialogue_choice(id: String, choice_id: String) -> void:
	player.controls_enabled = true
	if id == "mara_disclosure":
		if choice_id == "separate_fact":
			game_state.accept_contribution("mara")
			game_state.set_npc_tag("mara", "accepted_disclosure")
			_show_story("ash_compact")
		else:
			game_state.set_npc_tag("mara", "refused_control")
			ui.notify("Mara refuses the plan, not the warning.", Color("d17a64"), 3.4)
			_say("mara_boundary", "Mara", "Warden of Greyfen", [
				"No. You brought facts; those I can use. You do not get to spend my people because your fear feels like certainty. Ask us."
			])
	elif id == "tomas_surrender":
		if choice_id == "offer_exit":
			game_state.add_flag("tomas_surrendered")
			game_state.set_npc_tag("tomas", "surrendered_without_violence")
			ui.notify("Tomas sets down both keys.", Color("85c2b2"), 3.0)
			_begin_finale_defense()
		else:
			game_state.set_npc_tag("tomas", "frightened_by_threat")
			ui.notify("Tomas freezes. The threat made his captors feel closer.", Color("d17a64"), 3.4)
			for agent in agents:
				if agent.global_position.distance_to(player.global_position) < 420.0:
					agent.last_known_position = player.global_position
					agent.state = EnemyAgent.State.INVESTIGATE
	_refresh_world_state()
	_autosave()


func _show_story(id: String, choices: Array = []) -> void:
	var data: Dictionary = Content.get_dialogue(id)
	if data.is_empty():
		data = {"speaker": "Narrator", "role": "Greyfen", "pages": PackedStringArray([id.replace("_", " ").capitalize()])}
	data["portrait"] = _portrait_id(str(data.get("speaker", "narrator")))
	_stage_before_dialogue = _stage()
	player.controls_enabled = false
	ui.show_dialogue(id, data, choices)


func _say(id: String, speaker: String, role: String, pages: Array) -> void:
	var packed := PackedStringArray()
	for page in pages:
		packed.append(str(page))
	_show_data(id, {"speaker": speaker, "role": role, "pages": packed, "portrait": _portrait_id(speaker)})


func _show_data(id: String, data: Dictionary, choices: Array = []) -> void:
	player.controls_enabled = false
	ui.show_dialogue(id, data, choices)


func _portrait_id(speaker: String) -> String:
	var lowered := speaker.to_lower()
	for id in ["evan", "mara", "lysa", "nessa", "brann", "kesh", "piri", "tamsin", "tomas", "corvin"]:
		if lowered.contains(id):
			return id
	return "narrator"


func _trigger_authored_return(dialogue_id: String, cause: String, echo: String, trauma: String, next_stage: String) -> void:
	_pending_return = {
		"dialogue_id": dialogue_id,
		"cause": cause,
		"echo": echo,
		"trauma": trauma,
		"next_stage": next_stage,
	}
	_show_story(dialogue_id)


func _perform_return() -> void:
	player.controls_enabled = false
	rain.begin_return()
	game_state.record_authored_return(
		str(_pending_return["cause"]), str(_pending_return["echo"]),
		str(_pending_return["trauma"]), str(_pending_return["next_stage"])
	)
	_pending_return.clear()
	for hotspot_value in hotspots.values():
		var hotspot := hotspot_value as EvidenceHotspot
		hotspot.set_discovered(false)
	for npc_value in npcs.values():
		(npc_value as NpcActor).set_contribution_ready(false)
	for agent in agents:
		agent.reset_agent()
	player.reset_body(world_map.get_landmark("anchor"), int(game_state.retained.get("soul_scars", 0)))
	ui.set_condition(player.health, PlayerActor.MAX_HEALTH, player.stamina, PlayerActor.MAX_STAMINA)
	_refresh_world_state()
	_autosave()
	await get_tree().create_timer(0.72).timeout
	_begin_current_stage()


func _check_investigation_complete() -> void:
	if game_state.all_foundations_present():
		_set_stage("wrong_hero_report")
	else:
		_set_objective_for_stage()


func _refresh_fourth_pass_objective() -> void:
	if game_state.all_foundations_present() and _first_five_ready():
		_set_stage("mara_ready")
	else:
		_set_objective_for_stage()


func _accept_contribution(id: String, notification: String) -> void:
	if game_state.accept_contribution(id):
		game_state.set_npc_tag(id, "accepted_risk")
		ui.notify(notification, Color("85c2b2"), 3.2)
		(npcs[id] as NpcActor).set_contribution_ready(true)
	_refresh_fourth_pass_objective()
	_autosave()


func _first_five_ready() -> bool:
	for id in ["nessa", "piri", "brann", "kesh", "lysa"]:
		if not game_state.has_contribution(id):
			return false
	return true


func _npc_has_available_action(id: String) -> bool:
	if _stage() != "return_three" and _stage() != "mara_ready":
		return false
	match id:
		"nessa": return game_state.has_physical_evidence("powder") and not game_state.has_contribution("nessa")
		"piri": return game_state.has_physical_evidence("signal") and not game_state.has_contribution("piri")
		"brann", "kesh": return game_state.has_physical_evidence("gate") and not game_state.has_contribution(id)
		"lysa": return game_state.has_physical_evidence("tunnel") and not game_state.has_contribution("lysa")
		"mara": return game_state.all_foundations_present() and _first_five_ready() and not game_state.has_contribution("mara")
	return false


func _refresh_world_state() -> void:
	if not ui:
		return
	var stage := _stage()
	for id in hotspots:
		var hotspot := hotspots[id] as EvidenceHotspot
		hotspot.available = (
			(id == "powder" and stage in ["baseline_find_granary", "one_fuse", "return_two", "return_three", "wrong_hero_report", "mara_ready"])
			or (id in ["signal", "gate"] and stage in ["return_two", "return_three", "wrong_hero_report", "mara_ready"])
			or (id == "tunnel" and stage in ["return_three", "mara_ready"])
		)
		hotspot.set_discovered(game_state.has_physical_evidence(id))
	for id in npcs:
		(npcs[id] as NpcActor).set_contribution_ready(game_state.has_contribution(id))
	var discovered := {}
	var resolved := {}
	for id in AshGameState.FOUNDATION_IDS:
		discovered[id] = game_state.knows(id)
	resolved["powder"] = game_state.has_contribution("nessa") and game_state.has_contribution("lysa")
	resolved["signal"] = game_state.has_contribution("piri")
	resolved["gate"] = game_state.has_contribution("brann") and game_state.has_contribution("kesh")
	ui.set_threads(discovered, resolved)
	_set_objective_for_stage()


func _begin_finale_defense() -> void:
	_set_stage("finale_defense")
	_finale_remaining = 38.0
	game_state.current_line["finale_time"] = _finale_remaining
	_finale_events.clear()
	_activate_finale_agents()
	ui.notify("The counterfeit alarm begins. Hold the granary.", Color("e5b15a"), 3.2)


func _activate_finale_agents() -> void:
	for agent in agents:
		if agent.state != EnemyAgent.State.SURRENDERED:
			agent.last_known_position = player.global_position
			agent.suspicion = 1.0
			agent.state = EnemyAgent.State.CHASE


func _tick_finale(delta: float) -> void:
	_finale_remaining = maxf(0.0, _finale_remaining - delta)
	game_state.current_line["finale_time"] = _finale_remaining
	ui.set_clock("%02d BREATHS" % int(ceil(_finale_remaining)), "FINAL OPERATION")
	_finale_event_at(31.0, "piri", "Piri answers the false horn with the true cadence.")
	_finale_event_at(25.0, "brann", "Brann tears the forged withdrawal order in front of the gate company.")
	_finale_event_at(18.0, "nessa", "Nessa's clinic is already empty. Kesh brings Refuge Row inside the wall.")
	_finale_event_at(11.0, "lysa", "Lysa names the tunnel buyer. Soldiers turn on the surviving agents.")
	_finale_event_at(5.0, "mara", "Mara opens the water gate herself. The jammed mechanism gives way.")
	if _finale_remaining <= 0.0:
		_finish_finale()


func _finale_event_at(threshold: float, id: String, text: String) -> void:
	if _finale_remaining <= threshold and not _finale_events.has(id):
		_finale_events[id] = true
		ui.notify(text, Color("85c2b2"), 3.2)
		if id == "lysa":
			for agent in agents:
				agent.suspicion = maxf(0.0, agent.suspicion - 0.4)


func _finish_finale() -> void:
	if _stage() != "finale_defense":
		return
	game_state.current_line["stage"] = "finale_resolved"
	for agent in agents:
		agent.state = EnemyAgent.State.SURRENDERED
		agent.velocity = Vector2.ZERO
	ui.set_clock("THE TRUE HORN", "GREYFEN HOLDS")
	_show_story("corvin_lens")
	_autosave()


func _on_player_shove(origin: Vector2, direction: Vector2) -> void:
	var contacted := false
	for agent in agents:
		if agent.receive_shove(origin, direction):
			contacted = true
	if contacted:
		ui.notify("Non-lethal opening—move before they recover.", Color("d7b56e"), 1.2)


func _on_agent_surrendered(_agent: EnemyAgent) -> void:
	ui.notify("An agent drops their weapon and withdraws.", Color("85c2b2"), 2.0)


func _on_player_defeated(_cause: String) -> void:
	ui.notify("Tamsin drags Evan clear. This is injury, not a Return.", Color("d17a64"), 3.5)
	await get_tree().create_timer(1.1).timeout
	var rescue_position := world_map.get_landmark("nessa") + Vector2(0, 45)
	if _stage() in ["arrival", "reach_mara", "baseline_find_granary"]:
		rescue_position = world_map.get_landmark("west_gate")
	player.reset_body(rescue_position, int(game_state.retained.get("soul_scars", 0)))
	if _stage() == "finale_defense":
		_finale_remaining = maxf(8.0, _finale_remaining - 5.0)


func _on_health_changed(value: float, maximum: float) -> void:
	if ui:
		ui.set_health(value, maximum)


func _on_stamina_changed(value: float, maximum: float) -> void:
	if ui:
		ui.set_stamina(value, maximum)


func _on_focus_changed(active: bool) -> void:
	if active:
		ui.notify("Focus: noticed routes and contradictions are highlighted.", Color("76bec1"), 1.8)


func _open_folio() -> void:
	player.controls_enabled = false
	var retained_entries: Array = []
	for id in game_state.retained.get("knowledge", []):
		var retained_text: String = _folio_entry_text(str(id))
		if not retained_text.is_empty():
			retained_entries.append(retained_text)
	for echo in game_state.retained.get("echo_log", []):
		if not str(echo).is_empty() and not retained_entries.has(str(echo)):
			retained_entries.append(str(echo))
	var present_entries: Array = []
	for id in game_state.current_line.get("physical_evidence", []):
		var present_text: String = str(FOUNDATION_NAMES.get(id, _folio_entry_text(str(id))))
		if not present_text.is_empty():
			present_entries.append(present_text)
	var people_entries: Array = []
	for id in game_state.current_line.get("contributions", []):
		people_entries.append(_contribution_text(str(id)))
	ui.show_folio(retained_entries, present_entries, people_entries, int(game_state.retained.get("soul_scars", 0)))


func _on_folio_closed() -> void:
	player.controls_enabled = true


func _folio_entry_text(id: String) -> String:
	if not Content.FOLIO_ENTRIES.has(id):
		return ""
	var value = Content.FOLIO_ENTRIES[id]
	if value is Dictionary:
		return "%s — %s" % [str(value.get("title", id.capitalize())), str(value.get("text", ""))]
	return str(value)


func _contribution_text(id: String) -> String:
	var texts := {
		"nessa": "Nessa accepted the risk of moving the clinic early.",
		"piri": "Piri accepted responsibility for the true cadence.",
		"brann": "Brann accepted the cost of public disobedience.",
		"kesh": "Kesh accepted the risk of sheltering inside a hostile wall.",
		"lysa": "Lysa chose her own tunnel route and target.",
		"mara": "Mara staked her claim on shared testimony.",
	}
	return str(texts.get(id, id.capitalize()))


func _on_pause_requested() -> void:
	ui.notify("Progress autosaved. Press Escape again from the title menu to quit.", Color("d7b56e"), 2.5)
	_autosave()


func _autosave() -> void:
	if player:
		game_state.current_line["player_position"] = [player.global_position.x, player.global_position.y]
	autosave_requested.emit(game_state.to_save_data())
	if ui:
		ui.show_saved()


func _saved_or_anchor_position() -> Vector2:
	var saved = game_state.current_line.get("player_position", [180.0, 875.0])
	if saved is Array and saved.size() >= 2:
		return Vector2(float(saved[0]), float(saved[1]))
	return Vector2(180, 875)
