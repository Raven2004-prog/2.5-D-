extends Node3D
class_name AshenBillboardActor3D

enum AtlasKind { EVAN, CHOIR_AGENT, NPC }
enum Direction8 { NORTH, NORTH_EAST, EAST, SOUTH_EAST, SOUTH, SOUTH_WEST, WEST, NORTH_WEST }

const EVAN_ATLAS_PATH := "res://assets/ashen/characters/evan/evan_8dir_idle_atlas.png"
const CHOIR_AGENT_ATLAS_PATH := "res://assets/ashen/characters/enemies/choir_agent_8dir_idle_atlas.png"
const NPC_ATLAS_PATH := "res://assets/ashen/characters/npcs/greyfen_npc_front_atlas.png"

const ATLAS_PATHS := {
	AtlasKind.EVAN: EVAN_ATLAS_PATH,
	AtlasKind.CHOIR_AGENT: CHOIR_AGENT_ATLAS_PATH,
	AtlasKind.NPC: NPC_ATLAS_PATH,
}

const DIRECTION_CELLS := [
	Vector2i(0, 0), # north
	Vector2i(1, 0), # north-east
	Vector2i(2, 0), # east
	Vector2i(3, 0), # south-east
	Vector2i(0, 1), # south
	Vector2i(1, 1), # south-west
	Vector2i(2, 1), # west
	Vector2i(3, 1), # north-west
]

const NPC_ORDER := [
	&"mara", &"tamsin", &"lysa", &"nessa",
	&"brann", &"kesh", &"piri", &"tomas",
]
const NPC_INDEX := {
	"mara": 0,
	"tamsin": 1,
	"lysa": 2,
	"nessa": 3,
	"brann": 4,
	"kesh": 5,
	"piri": 6,
	"tomas": 7,
}

@export_enum("Evan", "Choir agent", "Named NPC") var atlas_kind: int = AtlasKind.EVAN
@export var npc_id: StringName = &"mara"
@export_range(0.8, 2.6, 0.01) var visual_height_m := 1.75
@export var contact_shadow_size := Vector2(0.82, 0.42)
@export_range(0.0, 0.8, 0.01) var contact_shadow_opacity := 0.34

var _direction_index := Direction8.SOUTH
var _sprite: Sprite3D
var _shadow: MeshInstance3D
var _atlas_texture: AtlasTexture
var _source_texture: Texture2D


func _ready() -> void:
	_ensure_visual_nodes()
	_refresh_atlas()
	_refresh_shadow()


func configure(kind: int, requested_npc_id: StringName = &"mara", height_m: float = 1.75) -> void:
	atlas_kind = clampi(kind, AtlasKind.EVAN, AtlasKind.NPC)
	visual_height_m = clampf(height_m, 0.8, 2.6)
	if atlas_kind == AtlasKind.NPC:
		var normalized_id := str(requested_npc_id).to_lower()
		npc_id = StringName(normalized_id if NPC_INDEX.has(normalized_id) else "mara")
	if is_inside_tree():
		_ensure_visual_nodes()
		_refresh_atlas()
		_refresh_shadow()


func set_facing(direction: Vector3) -> void:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		return
	_direction_index = direction_index_from_vector(horizontal)
	if atlas_kind != AtlasKind.NPC:
		_refresh_region()


func set_direction_index(value: int) -> void:
	_direction_index = (value % DIRECTION_CELLS.size() + DIRECTION_CELLS.size()) % DIRECTION_CELLS.size()
	if atlas_kind != AtlasKind.NPC:
		_refresh_region()


func set_npc_id(value: StringName) -> bool:
	var normalized_id := str(value).to_lower()
	if not NPC_INDEX.has(normalized_id):
		return false
	npc_id = StringName(normalized_id)
	if atlas_kind == AtlasKind.NPC:
		_refresh_region()
	return true


func get_direction_index() -> int:
	return _direction_index


func get_current_cell() -> Vector2i:
	if atlas_kind == AtlasKind.NPC:
		var npc_index := int(NPC_INDEX.get(str(npc_id).to_lower(), 0))
		return Vector2i(npc_index % 4, npc_index / 4)
	return DIRECTION_CELLS[_direction_index]


func get_current_region() -> Rect2:
	return _atlas_texture.region if is_instance_valid(_atlas_texture) else Rect2()


func get_atlas_path() -> String:
	return str(ATLAS_PATHS.get(atlas_kind, ""))


func has_valid_atlas() -> bool:
	return is_instance_valid(_source_texture) and is_instance_valid(_atlas_texture)


func get_sprite_node() -> Sprite3D:
	_ensure_visual_nodes()
	return _sprite


func get_shadow_node() -> MeshInstance3D:
	_ensure_visual_nodes()
	return _shadow


static func direction_index_from_vector(direction: Vector3) -> int:
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.0001:
		return Direction8.SOUTH
	var angle := atan2(horizontal.x, -horizontal.z)
	var rounded_index := roundi(angle / (PI * 0.25))
	return (rounded_index % 8 + 8) % 8


func _ensure_visual_nodes() -> void:
	if not is_instance_valid(_sprite):
		_sprite = get_node_or_null("LitSprite") as Sprite3D
	if _sprite == null:
		_sprite = Sprite3D.new()
		_sprite.name = "LitSprite"
		add_child(_sprite)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.shaded = true
	_sprite.double_sided = true
	_sprite.no_depth_test = false
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.alpha_scissor_threshold = 0.18
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if not is_instance_valid(_shadow):
		_shadow = get_node_or_null("ContactShadow") as MeshInstance3D
	if _shadow == null:
		_shadow = MeshInstance3D.new()
		_shadow.name = "ContactShadow"
		add_child(_shadow)
	_shadow.position = Vector3(0.0, 0.015, 0.0)
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _refresh_atlas() -> void:
	_ensure_visual_nodes()
	_source_texture = null
	_atlas_texture = null
	var atlas_path := get_atlas_path()
	if atlas_path.is_empty() or not ResourceLoader.exists(atlas_path):
		_sprite.texture = null
		return
	_source_texture = load(atlas_path) as Texture2D
	if _source_texture == null:
		_sprite.texture = null
		return
	_atlas_texture = AtlasTexture.new()
	_atlas_texture.atlas = _source_texture
	_sprite.texture = _atlas_texture
	_refresh_region()


func _refresh_region() -> void:
	if not is_instance_valid(_source_texture) or not is_instance_valid(_atlas_texture):
		return
	var columns := 4.0
	var rows := 2.0
	var cell_size := Vector2(float(_source_texture.get_width()) / columns, float(_source_texture.get_height()) / rows)
	var cell := get_current_cell()
	_atlas_texture.region = Rect2(Vector2(cell) * cell_size, cell_size)
	_sprite.pixel_size = visual_height_m / cell_size.y
	_sprite.position = Vector3.UP * (visual_height_m * 0.5)


func _refresh_shadow() -> void:
	_ensure_visual_nodes()
	var quad := QuadMesh.new()
	quad.size = contact_shadow_size
	_shadow.mesh = quad

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.008, 0.012, 0.014, contact_shadow_opacity),
		Color(0.008, 0.012, 0.014, contact_shadow_opacity * 0.42),
		Color(0.008, 0.012, 0.014, 0.0),
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.width = 64
	gradient_texture.height = 64
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.5, 0.5)
	gradient_texture.fill_to = Vector2(1.0, 0.5)
	gradient_texture.gradient = gradient

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = gradient_texture
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = material
