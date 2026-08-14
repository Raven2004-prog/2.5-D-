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
var camera: Camera2D
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
var _outside_defense_zone := false
var _rescue_in_progress := false


func configure(state: AshGameState) -> void:
	game_state = state


func _ready() -> void:
	y_sort_enabled = true
	if game_state == null:
		game_state = AshGameState.new()
	var saved_return: Variant = game_state.current_line.get("pending_return", {})
	if saved_return is Dictionary:
		_pending_return = (saved_return as Dictionary).duplicate(true)
	_build_world()
	call_deferred("_begin_current_stage")


func _process(delta: float) -> void:
	if not _started:
		return
	_interaction_tick -= delta
	if _interaction_tick <= 0.0:
		_interaction_tick = 0.08
		_update_nearest_interactable()
	if _stage() == "finale_defense" and not ui.dialogue_open and not ui.folio_open and not _rescue_in_progress:
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

	camera = Camera2D.new()
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
	ui.resume_requested.connect(_resume_game)
	ui.title_requested.connect(_return_to_title)
	ui.setting_changed.connect(_on_setting_changed)
	add_child(ui)
	ui.sync_settings(game_state.settings)
	camera.position_smoothing_enabled = not bool(game_state.settings.get("reduce_motion", false))
	ui.set_condition(player.health, PlayerActor.MAX_HEALTH, player.stamina, PlayerActor.MAX_STAMINA)
	_refresh_world_state()


func _build_npcs() -> void:
	_add_npc("mara", _known_name("mara", "Mara", "Armored warden"), "Warden of Greyfen", Color("58636a"), Color("d49a45"), world_map.get_landmark("mara"))
	_add_npc("tamsin", _known_name("tamsin", "Tamsin", "Greyfen captain"), "Captain", Color("394950"), Color("91aeb5"), world_map.get_landmark("tamsin"))
	var lysa_name := "Lysa" if game_state.knows("lysa_name") else "Fleeing courier"
	_add_npc("lysa", lysa_name, "Courier", Color("5c4e66"), Color("c77955"), world_map.get_landmark("lysa"))
	_add_npc("nessa", _known_name("nessa", "Nessa", "Field surgeon"), "Surgeon", Color("45625f"), Color("87b8a2"), world_map.get_landmark("nessa"))
	_add_npc("brann", _known_name("brann", "Brann", "Gate commander"), "Gate commander", Color("5a5147"), Color("c3a15e"), world_map.get_landmark("brann"))
	_add_npc("kesh", _known_name("kesh", "Kesh", "Horned envoy"), "Aruun envoy", Color("514b61"), Color("db7045"), world_map.get_landmark("kesh"), true)
	# Piri's mixed heritage remains visually ambiguous while she is living under false papers.
	_add_npc("piri", _known_name("piri", "Piri", "Signal apprentice"), "Signal apprentice", Color("4b5c68"), Color("dfa750"), world_map.get_landmark("piri"), false)
	_add_npc("tomas", _known_name("tomas", "Tomas", "Quartermaster"), "Quartermaster", Color("675b4a"), Color("c7834d"), world_map.get_landmark("tomas"))


func _known_name(id: String, known: String, unknown: String) -> String:
	return known if game_state.knows("%s_name" % id) else unknown


func _reveal_npc_identity(id: String) -> void:
	if not npcs.has(id):
		return
	var identities := {
		"mara": ["Mara", "Warden of Greyfen"],
		"tamsin": ["Tamsin", "Captain"],
		"lysa": ["Lysa", "Courier"],
		"nessa": ["Nessa", "Surgeon"],
		"brann": ["Brann", "Gate commander"],
		"kesh": ["Kesh", "Aruun envoy"],
		"piri": ["Piri", "Signal apprentice"],
		"tomas": ["Tomas", "Quartermaster"],
	}
	var identity: Array = identities.get(id, [id.capitalize(), "Greyfen"])
	var npc := npcs[id] as NpcActor
	game_state.remember("%s_name" % id)
	npc.configure(id, str(identity[0]), str(identity[1]), npc.body_color, npc.accent_color, npc.is_daevar)


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
	_add_agent("Granary watch", PackedVector2Array([Vector2(1160, 610), Vector2(1440, 660), Vector2(1600, 650), Vector2(1280, 690)]))
	_add_agent("Tunnel buyer", PackedVector2Array([Vector2(980, 970), Vector2(1180, 1000), Vector2(1270, 900), Vector2(1040, 850)]))
	_add_agent("Signal runner", PackedVector2Array([Vector2(875, 420), Vector2(1120, 375), Vector2(1160, 560), Vector2(920, 575)]))


func _add_agent(name_text: String, points: PackedVector2Array) -> void:
	var agent := EnemyScene.new()
	agent.configure(player, points, name_text)
	agent.surrendered.connect(_on_agent_surrendered)
	agents.append(agent)
	add_child(agent)
	var saved_states: Dictionary = game_state.current_line.get("agent_states", {})
	if saved_states.get(name_text) is Dictionary:
		agent.restore_save_state(saved_states[name_text])


func _begin_current_stage() -> void:
	_started = true
	var stage := _stage()
	var pending_story := str(game_state.current_line.get("pending_story", ""))
	if not pending_story.is_empty():
		_apply_resume_header(stage)
		var pending_choices: Array = game_state.current_line.get("pending_choices", [])
		_show_story(pending_story, pending_choices.duplicate(true))
		_refresh_world_state()
		return
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
				_finale_events.clear()
				for event_id in game_state.current_line.get("finale_events", []):
					_finale_events[str(event_id)] = true
				_activate_finale_agents()
			elif game_state.has_flag("tomas_surrendered"):
				_show_story("tomas_accepts")
			else:
				_set_objective_for_stage()
		"finale_resolved":
			ui.set_chapter("Chapter 12", "The Laughing Saint")
			ui.set_clock("AFTER THE HORN", "GREYFEN HOLDS")
			_show_story("corvin_lens")
		"tribunal":
			ui.set_chapter("Chapter 13", "One Surviving Account")
			ui.set_clock("DAWN", "GREYFEN TRIBUNAL")
			_show_story("tribunal")
		"complete":
			_show_story("ending")
		_:
			_set_objective_for_stage()
	_refresh_world_state()


func _apply_resume_header(stage: String) -> void:
	match stage:
		"arrival", "reach_mara", "baseline_find_granary":
			ui.set_chapter("Chapter 1", "The Blink")
			ui.set_clock("4:20 PM", "THE FIRST RAIN")
		"return_one", "one_fuse", "one_fuse_report":
			ui.set_chapter("Chapter 4", "The Same Rain")
			ui.set_clock("4:20 PM", "PASS TWO")
		"return_two", "wrong_hero_report":
			ui.set_chapter("Chapter 6", "Three Hands on the Knife")
			ui.set_clock("4:20 PM", "PASS THREE")
		"return_three", "mara_ready", "compact_offer":
			ui.set_chapter("Chapter 10", "No One Owes Him Yesterday")
			ui.set_clock("4:20 PM", "THE SURVIVING LINE")
		"finale_to_tomas", "finale_defense", "finale_resolved":
			ui.set_chapter("Chapter 12", "Six People Break the Pattern")
			ui.set_clock("BEFORE THE HORN", "FINAL OPERATION")
		"tribunal", "complete":
			ui.set_chapter("Chapter 13", "One Surviving Account")
			ui.set_clock("DAWN", "GREYFEN TRIBUNAL")


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
			ui.set_objective("Bring the bloodied token to Greyfen", "Find the armored warden below the Grey Keep. Follow the amber ward-lights.")
		"baseline_find_granary":
			ui.set_objective("Reach Refuge Row", "Mara's guards are moving you toward the crowded refugee enclosure.")
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
			if game_state.all_foundations_present() and ready == 4 and not game_state.has_physical_evidence("tunnel"):
				ui.set_objective("Trace the tunnel buyer for Lysa", "Focus reveals drainage prints south of Nessa's clinic.")
			else:
				ui.set_objective("Build a plan people choose", "%d/3 present facts · %d/5 allies ready before Mara." % [game_state.present_foundation_count(), mini(ready, 5)])
		"mara_ready":
			ui.set_objective("Tell Mara what is fact—and what is fear", "No one owes you a relationship from an erased line.")
		"compact_offer":
			ui.set_objective("Choose whether to enter the Compact", "Mara has risked her claim. Evan is still free to walk away.")
		"finale_to_tomas":
			ui.set_objective("Reach Tomas beneath the granary", "The coerced sapper can still choose to stop.")
		"finale_defense":
			ui.set_objective("Hold the granary line", "Stay near the ward-lights and occupy the attackers while six independent choices take effect.")
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
	if not npc.available:
		return
	if not (npc.npc_id == "lysa" and _stage() == "arrival"):
		_reveal_npc_identity(npc.npc_id)
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
			"If you need a route, ask. If you already know one you should not, explain before you follow me."
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
			_show_story("third_plan", [
				{"id": "assign_ghost_route", "text": "Send Lysa down the erased route; keep Brann at the gate."},
				{"id": "hide_risk", "text": "Hide Lysa's worst risk; deny Brann's requested withdrawal."}
			])
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
		"compact_offer":
			_show_compact_choice()
		_:
			_say("mara_bark", "Mara", "Warden of Greyfen", ["Greyfen is under restricted command. State your name, your evidence, and what you need—in that order."])


func _show_compact_choice() -> void:
	_show_story("evan_compact", [
		{"id": "accept_witness", "text": "Accept truthful service and shared protection."},
		{"id": "ask_time", "text": "Step away. Keep the right to refuse."}
	])


func _talk_brann() -> void:
	if _stage() == "return_one" and not game_state.has_flag("brann_prediction"):
		_show_story("brann_prediction")
	elif _stage() == "return_three" and game_state.has_physical_evidence("gate") and not game_state.has_contribution("brann"):
		_show_story("brann_contribution")
	else:
		_say("brann_bark", "Brann", "Gate commander", ["West gate is restricted. If you have business inside, find a witness with a name the guard recognizes."])


func _talk_piri() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("signal") and not game_state.has_contribution("piri"):
		_show_story("piri_contribution")
	else:
		_say("piri_bark", "Piri", "Signal apprentice", ["Signal manual, page forty-two: do not improvise cadence during rain. Stars and cinders, no one reads page forty-two."])


func _talk_nessa() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("powder") and not game_state.has_contribution("nessa"):
		_show_story("nessa_contribution")
	else:
		_say("nessa_bark", "Nessa", "Border surgeon", ["You are shaking and you have no shoes. Sit if you need treatment; leave if you only need an audience."])


func _talk_kesh() -> void:
	if _stage() == "return_three" and game_state.has_physical_evidence("gate") and not game_state.has_contribution("kesh"):
		_show_story("kesh_contribution")
	else:
		_say("kesh_bark", "Kesh", "Aruun envoy", ["Daevar is the word. If someone intends an insult, they should at least have the courage to choose it themselves."])


func _talk_tamsin() -> void:
	_say("tamsin_bark", "Tamsin", "Mara's captain", [
		"Stop there. Name and business.",
		"One useful answer earns attention. Trust costs more."
	])


func _talk_tomas() -> void:
	if _stage() == "finale_to_tomas":
		if game_state.has_flag("tomas_surrendered"):
			_show_story("tomas_accepts")
		else:
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
	game_state.current_line["pending_story"] = ""
	game_state.current_line["pending_choices"] = []
	if not _pending_return.is_empty() and _pending_return.get("dialogue_id", "") == id:
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
			game_state.remember("token", "The fleeing courier pressed a bloodied token into my hand.")
			_set_stage("reach_mara")
		"mara_arrest":
			game_state.remember("lysa_name", "Mara named the fleeing courier: Lysa.")
			_reveal_npc_identity("lysa")
			_reveal_npc_identity("nessa")
			_show_story("nessa_treatment")
		"nessa_treatment":
			_reveal_npc_identity("tamsin")
			_show_story("tamsin_interrogation")
		"tamsin_interrogation":
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
			_show_compact_choice()
		"transfer_order":
			_show_story("ash_compact")
		"tomas_accepts":
			_begin_finale_defense()
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
	game_state.current_line["pending_story"] = ""
	game_state.current_line["pending_choices"] = []
	if id == "third_plan":
		game_state.add_flag("third_plan_%s" % choice_id)
		if choice_id == "assign_ghost_route":
			ui.notify("A remembered survival is not present consent.", Color("d17a64"), 3.2)
		else:
			ui.notify("Withholding danger makes the choice Evan's, not Lysa's.", Color("d17a64"), 3.2)
		_show_story("wrong_hero")
	elif id == "evan_compact":
		if choice_id == "accept_witness":
			game_state.accept_contribution("mara")
			game_state.set_npc_tag("mara", "accepted_legal_risk")
			game_state.add_flag("evan_accepted_compact")
			game_state.remember("ash_witness", "Mara staked her claim and Evan freely accepted truthful service under shared protection.")
			_set_stage("finale_to_tomas")
		else:
			_set_stage("compact_offer")
			ui.notify("Mara leaves the choice open. The operation waits for Evan's answer.", Color("d7b56e"), 3.6)
	elif id == "mara_disclosure":
		if choice_id == "separate_fact":
			game_state.set_npc_tag("mara", "accepted_disclosure")
			_show_story("transfer_order")
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
			_show_story("tomas_accepts")
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
	data["portrait"] = "lysa" if id == "lysa_token" else _portrait_id(str(data.get("speaker", "narrator")))
	_stage_before_dialogue = _stage()
	game_state.current_line["pending_story"] = id
	game_state.current_line["pending_choices"] = choices.duplicate(true)
	player.controls_enabled = false
	_play_audio("warning" if id.begins_with("catastrophe") else "focus")
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
	game_state.current_line["pending_return"] = _pending_return.duplicate(true)
	_show_story(dialogue_id)


func _perform_return() -> void:
	player.controls_enabled = false
	_play_audio("warning", -0.12)
	rain.begin_return(bool(game_state.settings.get("reduce_flash", false)))
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
	if _stage() not in ["return_three", "mara_ready", "compact_offer"]:
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
		var npc := npcs[id] as NpcActor
		npc.available = true
		if stage == "arrival":
			npc.available = id == "lysa"
		elif stage == "reach_mara":
			npc.available = id == "mara"
		npc.set_contribution_ready(game_state.has_contribution(id))
	var retained := {}
	var present := {}
	var resolved := {}
	for id in AshGameState.FOUNDATION_IDS:
		retained[id] = game_state.knows(id)
		present[id] = game_state.has_physical_evidence(id)
	# A proposed contribution is not marked resolved until it actually happens.
	resolved["powder"] = game_state.has_flag("executed_powder")
	resolved["signal"] = game_state.has_flag("executed_signal")
	resolved["gate"] = game_state.has_flag("executed_gate")
	ui.set_threads(retained, present, resolved)
	_set_objective_for_stage()


func _begin_finale_defense() -> void:
	game_state.current_line["stage"] = "finale_defense"
	game_state.add_flag("executed_powder")
	_finale_remaining = 38.0
	_outside_defense_zone = false
	game_state.current_line["finale_time"] = _finale_remaining
	_finale_events.clear()
	game_state.current_line["finale_events"] = []
	_refresh_world_state()
	_activate_finale_agents()
	ui.notify("The counterfeit alarm begins. Hold the granary.", Color("e5b15a"), 3.2)
	_autosave()


func _activate_finale_agents() -> void:
	for agent in agents:
		if agent.state != EnemyAgent.State.SURRENDERED:
			agent.last_known_position = player.global_position
			agent.suspicion = 1.0
			agent.state = EnemyAgent.State.CHASE


func _tick_finale(delta: float) -> void:
	var in_defense_zone := player.global_position.distance_to(world_map.get_landmark("granary")) <= 470.0
	if not in_defense_zone:
		if not _outside_defense_zone:
			ui.notify("The attackers are leaving the granary line. Return to the amber ward-lights.", Color("d17a64"), 3.4)
		_outside_defense_zone = true
		ui.set_clock("%02d BREATHS" % int(ceil(_finale_remaining)), "LINE UNHELD")
		return
	if _outside_defense_zone:
		ui.notify("The granary line holds again.", Color("85c2b2"), 2.0)
	_outside_defense_zone = false
	_finale_remaining = maxf(0.0, _finale_remaining - delta)
	game_state.current_line["finale_time"] = _finale_remaining
	ui.set_clock("%02d BREATHS" % int(ceil(_finale_remaining)), "FINAL OPERATION")
	_finale_event_at(31.0, "piri", "Piri answers the false horn with the true cadence.")
	_finale_event_at(26.0, "brann", "Brann tears the forged withdrawal order in front of the gate company.")
	_finale_event_at(21.0, "nessa", "Nessa's clinic is already empty when the second charge is found.")
	_finale_event_at(16.0, "kesh", "Kesh brings Refuge Row inside the wall under its own wardens.")
	_finale_event_at(10.0, "lysa", "Lysa names the tunnel buyer. Soldiers turn on the surviving agents.")
	_finale_event_at(5.0, "mara", "Mara opens the water gate herself. The jammed mechanism gives way.")
	if _finale_remaining <= 0.0:
		_finish_finale()


func _finale_event_at(threshold: float, id: String, text: String) -> void:
	if _finale_remaining <= threshold and not _finale_events.has(id):
		_finale_events[id] = true
		var saved_events: Array = game_state.current_line.get("finale_events", [])
		if not saved_events.has(id):
			saved_events.append(id)
		game_state.current_line["finale_events"] = saved_events
		if id == "brann":
			game_state.add_flag("executed_signal")
		elif id == "mara":
			game_state.add_flag("executed_gate")
		ui.notify(text, Color("85c2b2"), 3.2)
		if id == "lysa":
			for agent in agents:
				agent.suspicion = maxf(0.0, agent.suspicion - 0.4)
		_refresh_world_state()
		_autosave()


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
	_autosave()


func _on_player_defeated(_cause: String) -> void:
	if _rescue_in_progress:
		return
	_rescue_in_progress = true
	var defeat_stage := _stage()
	var rescue_text := "Nessa's orderlies pull Evan from the road. This is injury, not a Return."
	if defeat_stage in ["arrival", "reach_mara", "baseline_find_granary"]:
		rescue_text = "A Greyfen patrol hauls the shoeless stranger clear. This is injury, not a Return."
	elif defeat_stage == "finale_defense":
		rescue_text = "Tamsin drags Evan behind the granary wall. This is injury, not a Return."
	ui.notify(rescue_text, Color("d17a64"), 3.5)
	await get_tree().create_timer(1.1).timeout
	var rescue_position := world_map.get_landmark("nessa") + Vector2(0, 45)
	if defeat_stage in ["arrival", "reach_mara", "baseline_find_granary"]:
		rescue_position = world_map.get_landmark("west_gate")
	elif defeat_stage == "finale_defense":
		rescue_position = world_map.get_landmark("granary") + Vector2(0, 90)
	player.reset_body(rescue_position, int(game_state.retained.get("soul_scars", 0)))
	if defeat_stage == "finale_defense":
		_finale_remaining = minf(45.0, _finale_remaining + 6.0)
		game_state.current_line["finale_time"] = _finale_remaining
		ui.notify("The rescue costs the operation six breaths.", Color("d17a64"), 2.8)
	_rescue_in_progress = false
	_autosave()


func _on_health_changed(value: float, maximum: float) -> void:
	if ui:
		ui.set_health(value, maximum)


func _on_stamina_changed(value: float, maximum: float) -> void:
	if ui:
		ui.set_stamina(value, maximum)


func _on_focus_changed(active: bool) -> void:
	if active:
		_play_audio("focus")
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
	var mapped_id := str({"signal": "false_horn", "gate": "water_gate"}.get(id, id))
	if not Content.FOLIO_ENTRIES.has(mapped_id):
		return ""
	var value = Content.FOLIO_ENTRIES[mapped_id]
	if value is Dictionary:
		return "%s — %s" % [str(value.get("title", mapped_id.capitalize())), str(value.get("body", value.get("text", "")))]
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
	_autosave()
	ui.sync_settings(game_state.settings)
	ui.show_pause()
	get_tree().paused = true


func _on_setting_changed(key: String, enabled: bool) -> void:
	game_state.settings[key] = enabled
	if key == "reduce_motion":
		rain.reduced_motion = enabled
		camera.position_smoothing_enabled = not enabled
	elif key == "master_audio":
		var audio_manager := get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("set_master_enabled"):
			audio_manager.call("set_master_enabled", enabled)
	ui.sync_settings(game_state.settings)
	_autosave()


func _resume_game() -> void:
	get_tree().paused = false
	if ui:
		ui.hide_pause()


func _return_to_title() -> void:
	_autosave()
	get_tree().paused = false
	return_to_title_requested.emit()


func _autosave() -> void:
	if player:
		game_state.current_line["player_position"] = [player.global_position.x, player.global_position.y]
	_capture_agent_states()
	autosave_requested.emit(game_state.to_save_data())


func snapshot_data() -> Dictionary:
	if player:
		game_state.current_line["player_position"] = [player.global_position.x, player.global_position.y]
	_capture_agent_states()
	return game_state.to_save_data()


func _capture_agent_states() -> void:
	var saved_states := {}
	for agent in agents:
		saved_states[agent.agent_name] = agent.to_save_state()
	game_state.current_line["agent_states"] = saved_states


func _saved_or_anchor_position() -> Vector2:
	var saved = game_state.current_line.get("player_position", [180.0, 875.0])
	if saved is Array and saved.size() >= 2:
		return Vector2(float(saved[0]), float(saved[1]))
	return Vector2(180, 875)


func _play_audio(cue: StringName, pitch_offset: float = 0.0) -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_ui"):
		audio_manager.call("play_ui", cue, pitch_offset)
