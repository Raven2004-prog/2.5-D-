extends RefCounted
class_name AshenCollisionLayers3D

## Phase-one collision contract for the Ashen 2.5D world.
##
## Layer numbers are part of the save/debugging contract. Keep these values stable;
## future scenes should use these constants instead of hand-authored bit masks.

const WORLD_SOLID_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 3
const NPC_LAYER := 4
const INTERACTABLE_AREA_LAYER := 5
const VISION_OCCLUDER_LAYER := 6
const TRAVERSAL_TRIGGER_LAYER := 7
const TERRAIN_HAZARD_LAYER := 8
const PARTICLE_COLLIDER_LAYER := 9

const WORLD_SOLID := 1 << (WORLD_SOLID_LAYER - 1)
const PLAYER := 1 << (PLAYER_LAYER - 1)
const ENEMY := 1 << (ENEMY_LAYER - 1)
const NPC := 1 << (NPC_LAYER - 1)
const INTERACTABLE_AREA := 1 << (INTERACTABLE_AREA_LAYER - 1)
const VISION_OCCLUDER := 1 << (VISION_OCCLUDER_LAYER - 1)
const TRAVERSAL_TRIGGER := 1 << (TRAVERSAL_TRIGGER_LAYER - 1)
const TERRAIN_HAZARD := 1 << (TERRAIN_HAZARD_LAYER - 1)
const PARTICLE_COLLIDER := 1 << (PARTICLE_COLLIDER_LAYER - 1)

const PLAYER_BODY_MASK := WORLD_SOLID | ENEMY | NPC
const ENEMY_BODY_MASK := WORLD_SOLID | PLAYER
const NPC_BODY_MASK := WORLD_SOLID
const INTERACTABLE_DETECTION_MASK := PLAYER
const VISION_RAY_MASK := WORLD_SOLID | PLAYER | VISION_OCCLUDER
const SHOVE_OCCLUSION_MASK := WORLD_SOLID | VISION_OCCLUDER
const TERRAIN_HAZARD_DETECTION_MASK := PLAYER | ENEMY | NPC

const LAYER_NAMES := {
	WORLD_SOLID_LAYER: "WorldSolid",
	PLAYER_LAYER: "Player",
	ENEMY_LAYER: "Enemy",
	NPC_LAYER: "NPC",
	INTERACTABLE_AREA_LAYER: "InteractableArea",
	VISION_OCCLUDER_LAYER: "VisionOccluder",
	TRAVERSAL_TRIGGER_LAYER: "TraversalTrigger",
	TERRAIN_HAZARD_LAYER: "TerrainHazard",
	PARTICLE_COLLIDER_LAYER: "ParticleCollider",
}


static func configure_player(body: CollisionObject3D) -> void:
	body.collision_layer = PLAYER
	body.collision_mask = PLAYER_BODY_MASK


static func configure_enemy(body: CollisionObject3D) -> void:
	body.collision_layer = ENEMY
	body.collision_mask = ENEMY_BODY_MASK


static func configure_npc(body: CollisionObject3D) -> void:
	body.collision_layer = NPC
	body.collision_mask = NPC_BODY_MASK


static func configure_interactable(area: Area3D) -> void:
	area.collision_layer = INTERACTABLE_AREA
	area.collision_mask = INTERACTABLE_DETECTION_MASK
	area.monitoring = true
	area.monitorable = true


static func configure_traversal_trigger(area: Area3D) -> void:
	area.collision_layer = TRAVERSAL_TRIGGER
	area.collision_mask = PLAYER
	area.monitoring = true
	area.monitorable = true


static func configure_terrain_hazard(area: Area3D) -> void:
	area.collision_layer = TERRAIN_HAZARD
	area.collision_mask = TERRAIN_HAZARD_DETECTION_MASK
	area.monitoring = true
	area.monitorable = true


static func layer_name(layer_number: int) -> String:
	return str(LAYER_NAMES.get(layer_number, "Unassigned"))
