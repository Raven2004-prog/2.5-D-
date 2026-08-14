extends SceneTree

const BILLBOARD_SCRIPT_PATH := "res://scripts/ashen_3d/billboard_actor_3d.gd"
const PORTRAIT_SCRIPT_PATH := "res://scripts/portrait.gd"
const EVAN_ATLAS_PATH := "res://assets/ashen/characters/evan/evan_8dir_idle_atlas.png"
const CHOIR_AGENT_ATLAS_PATH := "res://assets/ashen/characters/enemies/choir_agent_8dir_idle_atlas.png"
const NPC_ATLAS_PATH := "res://assets/ashen/characters/npcs/greyfen_npc_front_atlas.png"

var BillboardActor: Script
var Portrait: Script

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[ashen-billboards] %s" % message)


func _run() -> void:
	BillboardActor = load(BILLBOARD_SCRIPT_PATH) as Script
	Portrait = load(PORTRAIT_SCRIPT_PATH) as Script
	if BillboardActor == null or not BillboardActor.can_instantiate():
		_check(false, "Billboard actor script compiles and can be instantiated.")
	if Portrait == null or not Portrait.can_instantiate():
		_check(false, "Portrait script compiles and can be instantiated.")
	if not failures.is_empty():
		print("[ashen-billboards] FAIL (%d)" % failures.size())
		quit(1)
		return
	await _test_evan_directional_atlas()
	await _test_agent_and_npc_atlases()
	await _test_portrait_atlas_and_fallback()
	await process_frame
	if failures.is_empty():
		print("[ashen-billboards] PASS")
		quit(0)
	else:
		print("[ashen-billboards] FAIL (%d)" % failures.size())
		quit(1)


func _test_evan_directional_atlas() -> void:
	var actor: Variant = BillboardActor.new()
	actor.name = "EvanBillboardFixture"
	root.add_child(actor)
	await process_frame
	_check(actor.has_valid_atlas(), "Evan billboard loads its production atlas.")
	_check(actor.get_atlas_path() == EVAN_ATLAS_PATH, "Evan billboard reports the stable manifest path.")
	var sprite := actor.get_sprite_node() as Sprite3D
	_check(sprite.texture is AtlasTexture, "Directional actor selects cells through AtlasTexture.")
	_check(sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, "Actor sprite is a fixed-Y billboard.")
	_check(sprite.shaded, "Actor sprite receives 3D scene lighting.")
	_check(not sprite.no_depth_test, "Actor sprite participates in depth testing.")
	_check(sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS, "Actor sprite uses an opaque alpha prepass for stable depth.")
	_check(sprite.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST, "Actor sprite preserves crisp atlas edges.")
	_check(sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Sprite shadow maps are disabled in favor of a stable contact shadow.")

	actor.set_facing(Vector3.FORWARD)
	_check(actor.get_direction_index() == 0, "World forward selects the north/back cell.")
	_check(actor.get_current_cell() == Vector2i(0, 0), "North is atlas cell 0,0.")
	actor.set_facing(Vector3(1.0, 0.0, -1.0))
	_check(actor.get_current_cell() == Vector2i(1, 0), "North-east is atlas cell 1,0.")
	actor.set_facing(Vector3.RIGHT)
	_check(actor.get_current_cell() == Vector2i(2, 0), "East is atlas cell 2,0.")
	actor.set_facing(Vector3.BACK)
	_check(actor.get_current_cell() == Vector2i(0, 1), "South/front is atlas cell 0,1.")
	actor.set_facing(Vector3.LEFT)
	_check(actor.get_current_cell() == Vector2i(2, 1), "West is atlas cell 2,1.")
	var region: Rect2 = actor.get_current_region()
	_check(region.position.is_equal_approx(Vector2(768.0, 512.0)), "West region begins at the expected 4x2 atlas offset.")
	_check(region.size.is_equal_approx(Vector2(384.0, 512.0)), "Directional atlas cell dimensions are exact.")
	_check(is_equal_approx(sprite.pixel_size * region.size.y, actor.visual_height_m), "Atlas cell scales to the requested world height.")

	var shadow := actor.get_shadow_node() as MeshInstance3D
	_check(shadow.mesh is QuadMesh, "Actor owns a dedicated contact-shadow quad.")
	if shadow.mesh is QuadMesh:
		var quad := shadow.mesh as QuadMesh
		_check(quad.size.is_equal_approx(actor.contact_shadow_size), "Contact-shadow footprint follows actor configuration.")
		var material := quad.material as StandardMaterial3D
		_check(material != null and material.albedo_texture is GradientTexture2D, "Contact shadow uses a soft radial alpha texture.")
		_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Contact shadow remains stable under scene lighting.")
	actor.queue_free()
	await process_frame


func _test_agent_and_npc_atlases() -> void:
	var agent: Variant = BillboardActor.new()
	agent.configure(1)
	root.add_child(agent)
	await process_frame
	_check(agent.has_valid_atlas(), "Choir-agent billboard loads its production atlas.")
	_check(agent.get_atlas_path() == CHOIR_AGENT_ATLAS_PATH, "Choir-agent billboard uses the dedicated directional atlas.")
	agent.set_direction_index(7)
	_check(agent.get_current_cell() == Vector2i(3, 1), "North-west maps to the final 4x2 directional cell.")

	var npc: Variant = BillboardActor.new()
	npc.configure(2, &"kesh")
	root.add_child(npc)
	await process_frame
	_check(npc.has_valid_atlas(), "Named-NPC billboard loads its production atlas.")
	_check(npc.get_atlas_path() == NPC_ATLAS_PATH, "Named NPCs share the stable front-view atlas.")
	_check(npc.get_current_cell() == Vector2i(1, 1), "Kesh maps to supplied NPC slot 5.")
	npc.set_facing(Vector3.LEFT)
	_check(npc.get_current_cell() == Vector2i(1, 1), "Front-view NPC slot is stable when world facing changes.")
	_check(npc.set_npc_id(&"piri"), "Known NPC IDs can switch atlas slots.")
	_check(npc.get_current_cell() == Vector2i(2, 1), "Piri maps to supplied NPC slot 6.")
	_check(not npc.set_npc_id(&"unknown"), "Unknown NPC IDs are rejected without corrupting atlas selection.")
	_check(npc.get_current_cell() == Vector2i(2, 1), "Rejected NPC ID preserves the previous valid cell.")
	agent.queue_free()
	npc.queue_free()
	await process_frame


func _test_portrait_atlas_and_fallback() -> void:
	var portrait: Variant = Portrait.new()
	portrait.name = "PortraitFixture"
	portrait.size = Vector2(118.0, 118.0)
	root.add_child(portrait)
	await process_frame
	portrait.set_character("evan")
	_check(portrait.is_using_atlas_portrait(), "Evan dialogue portrait uses the generated atlas.")
	_check(portrait.get_portrait_atlas() != null, "Portrait atlas is available as an imported Texture2D.")
	var evan_region: Rect2 = portrait.get_portrait_source_region()
	_check(evan_region.position.is_equal_approx(Vector2.ONE), "Evan uses the first portrait cell with a one-pixel bleed inset.")
	_check(evan_region.size.x > 300.0 and is_equal_approx(evan_region.size.x, evan_region.size.y), "Dialogue portrait uses a square head-and-shoulders crop.")
	portrait.set_character("corvin")
	_check(portrait.is_using_atlas_portrait(), "Corvin dialogue portrait uses the generated atlas.")
	var corvin_region: Rect2 = portrait.get_portrait_source_region()
	_check(corvin_region.position.x > 1200.0 and corvin_region.position.y > 512.0, "Corvin maps to the final 5x2 portrait cell.")
	portrait.set_character("narrator")
	_check(not portrait.is_using_atlas_portrait(), "Narrator safely retains the code-drawn fallback because no atlas cell exists.")
	_check(portrait.get_portrait_source_region().size == Vector2.ZERO, "Missing portrait IDs expose no invalid atlas region.")
	portrait.queue_free()
	await process_frame
