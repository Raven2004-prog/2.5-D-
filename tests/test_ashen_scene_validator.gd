extends SceneTree

const HOST_PATH := "res://scripts/ashen_3d/world_host_3d.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host_script := load(HOST_PATH) as Script
	if host_script == null or not host_script.can_instantiate():
		printerr("[ashen-scene-validator-diagnostic] host script unavailable")
		quit(1)
		return
	var host: Node = host_script.new()
	host.bake_navigation_on_ready = false
	root.add_child(host)
	await process_frame
	await process_frame
	print("[ashen-scene-validator-diagnostic] raw=%d registry=%d bodies=%d shapes=%d" % [
		host.get_raw_anchor_count(),
		host.landmark_registry.get_landmark_ids().size(),
		host.get_imported_collision_body_count(),
		host.get_imported_collision_shape_count(),
	])
	print("[ashen-scene-validator-diagnostic] host errors=%s warnings=%s" % [host.validation_errors, host.validation_warnings])
	var visuals: Array[MeshInstance3D] = []
	_collect_visuals(host.environment_root, visuals)
	for body: StaticBody3D in host.get_imported_collision_bodies():
		var shape_descriptions: Array[String] = []
		for child in body.get_children():
			if child is CollisionShape3D:
				var shape_node := child as CollisionShape3D
				shape_descriptions.append("%s:%s" % [shape_node.name, shape_node.shape.get_class() if shape_node.shape else "null"])
		var nearest: Array = []
		for visual in visuals:
			var distance := body.global_position.distance_to(visual.global_position)
			nearest.append([distance, str(visual.name), str(visual.get_path()), visual.get_aabb().size])
		nearest.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		print("COLLIDER path=%s pos=%s meta=%s shapes=%s nearest=%s" % [body.get_path(), body.global_position, body.get_meta_list(), shape_descriptions, nearest.slice(0, 3)])
	for id: StringName in host.landmark_registry.get_landmark_ids():
		var marker: Marker3D = host.landmark_registry.get_landmark(id)
		print("ANCHOR id=%s zone=%s pos=%s source=%s physical=%s" % [id, host.landmark_registry.get_zone_id(id), marker.global_position, marker.get_meta(&"source_node_name", ""), marker.get_meta(&"physical_zone_id", "")])
	host.queue_free()
	await process_frame
	quit(0)


func _collect_visuals(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_visuals(child, output)
