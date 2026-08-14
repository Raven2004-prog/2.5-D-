extends Node3D
class_name AshenLandmarkRegistry3D

## Resolves story-facing semantic IDs to authored Marker3D nodes.
##
## A marker participates by setting `landmark_id` metadata. `zone_id` metadata is
## optional and may be inherited from its closest ancestor. This keeps story and AI
## code independent from scene coordinates while allowing zones to be reorganized.

signal landmark_registered(id: StringName, marker: Marker3D)
signal landmark_unregistered(id: StringName)

const LANDMARK_ID_META := &"landmark_id"
const ZONE_ID_META := &"zone_id"

@export var auto_discover_on_ready := true

var last_error := ""

var _markers: Dictionary = {}
var _zones: Dictionary = {}


func _ready() -> void:
	if auto_discover_on_ready:
		rebuild_from(self)


func rebuild_from(search_root: Node = self) -> int:
	clear_registry()
	_discover_descendants(search_root)
	return _markers.size()


func clear_registry() -> void:
	_markers.clear()
	_zones.clear()
	last_error = ""


func register_landmark(id: StringName, marker: Marker3D, zone_id: StringName = &"") -> bool:
	last_error = ""
	var normalized_id := StringName(str(id).strip_edges())
	if normalized_id == &"":
		last_error = "A landmark requires a non-empty semantic ID."
		return false
	if not is_instance_valid(marker):
		last_error = "Landmark '%s' has no valid Marker3D." % normalized_id
		return false
	if _markers.has(normalized_id):
		var existing: Variant = _markers[normalized_id]
		if is_instance_valid(existing) and existing != marker:
			last_error = "Duplicate landmark ID '%s'." % normalized_id
			return false
		_markers[normalized_id] = marker
		_zones[normalized_id] = zone_id
		return true

	_markers[normalized_id] = marker
	_zones[normalized_id] = zone_id
	marker.set_meta(LANDMARK_ID_META, normalized_id)
	if zone_id != &"":
		marker.set_meta(ZONE_ID_META, zone_id)
	marker.tree_exiting.connect(_on_marker_tree_exiting.bind(normalized_id, marker), CONNECT_ONE_SHOT)
	landmark_registered.emit(normalized_id, marker)
	return true


func unregister_landmark(id: StringName) -> bool:
	if not _markers.has(id):
		return false
	_markers.erase(id)
	_zones.erase(id)
	landmark_unregistered.emit(id)
	return true


func has_landmark(id: StringName) -> bool:
	return get_landmark(id) != null


func get_landmark(id: StringName) -> Marker3D:
	var value: Variant = _markers.get(id)
	if value is Marker3D and is_instance_valid(value):
		return value as Marker3D
	if _markers.has(id):
		_markers.erase(id)
		_zones.erase(id)
	return null


func get_landmark_position(id: StringName, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var marker := get_landmark(id)
	return marker.global_position if marker else fallback


func get_landmark_transform(id: StringName, fallback: Transform3D = Transform3D.IDENTITY) -> Transform3D:
	var marker := get_landmark(id)
	return marker.global_transform if marker else fallback


func get_zone_id(id: StringName) -> StringName:
	if get_landmark(id) == null:
		return &""
	return StringName(_zones.get(id, &""))


func get_landmark_ids() -> Array[StringName]:
	_prune_invalid()
	var result: Array[StringName] = []
	for id: Variant in _markers.keys():
		result.append(StringName(id))
	result.sort()
	return result


func get_landmark_ids_in_zone(zone_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in get_landmark_ids():
		if get_zone_id(id) == zone_id:
			result.append(id)
	return result


func find_closest_landmark(point: Vector3, zone_id: StringName = &"") -> StringName:
	var closest_id := &""
	var closest_distance := INF
	for id in get_landmark_ids():
		if zone_id != &"" and get_zone_id(id) != zone_id:
			continue
		var offset := get_landmark_position(id) - point
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < closest_distance:
			closest_distance = distance
			closest_id = id
	return closest_id


func _discover_descendants(node: Node) -> void:
	for child in node.get_children():
		if child is Marker3D and child.has_meta(LANDMARK_ID_META):
			var marker := child as Marker3D
			var landmark_id := StringName(str(marker.get_meta(LANDMARK_ID_META, "")).strip_edges())
			var zone_id := _find_zone_id(marker)
			register_landmark(landmark_id, marker, zone_id)
		_discover_descendants(child)


func _find_zone_id(marker: Node) -> StringName:
	var cursor: Node = marker
	while cursor != null:
		if cursor.has_meta(ZONE_ID_META):
			return StringName(str(cursor.get_meta(ZONE_ID_META, "")).strip_edges())
		if cursor == self:
			break
		cursor = cursor.get_parent()
	return &""


func _prune_invalid() -> void:
	for id: Variant in _markers.keys():
		if not is_instance_valid(_markers[id]):
			_markers.erase(id)
			_zones.erase(id)


func _on_marker_tree_exiting(id: StringName, marker: Marker3D) -> void:
	if _markers.get(id) == marker:
		unregister_landmark(id)

