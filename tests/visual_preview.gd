extends Node


func _ready() -> void:
	var state := AshGameState.new()
	state.current_line["stage"] = "return_three"
	state.current_line["player_position"] = [1010.0, 660.0]
	for foundation in AshGameState.FOUNDATION_IDS:
		state.remember(foundation)
	for npc_id in ["mara", "tamsin", "lysa", "nessa", "brann", "kesh", "piri", "tomas"]:
		state.remember("%s_name" % npc_id)
	state.add_physical_evidence("powder")
	state.add_physical_evidence("signal")
	var world := GreyfenGameWorld.new()
	world.configure(state)
	add_child(world)
	await get_tree().process_frame
	await get_tree().process_frame
	world.ui.hide_dialogue()
	world.player.controls_enabled = true
	world.player.focus_active = true
	world.player.focus_changed.emit(true)
	world.ui.set_chapter("Chapter 10", "No One Owes Him Yesterday")
	world.ui.notify("Present-line fact: the horn cadence is counterfeit.", Color("85c2b2"), 8.0)
