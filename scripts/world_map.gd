extends Node2D
class_name GreyfenMap

const WORLD_SIZE := Vector2(1960, 1160)

var landmarks := {
	"anchor": Vector2(180, 875),
	"split_ash": Vector2(245, 820),
	"west_gate": Vector2(472, 675),
	"brann": Vector2(535, 635),
	"mara": Vector2(730, 455),
	"tamsin": Vector2(790, 500),
	"piri": Vector2(1015, 365),
	"lysa": Vector2(960, 680),
	"granary": Vector2(1370, 590),
	"tomas": Vector2(1425, 630),
	"nessa": Vector2(1200, 885),
	"kesh": Vector2(1535, 765),
	"water_gate": Vector2(1730, 925),
	"tunnel": Vector2(1070, 1030),
	"refuge_center": Vector2(1510, 680),
	"oathstone": Vector2(715, 345),
}

var _lanterns := [
	Vector2(480, 600), Vector2(625, 565), Vector2(846, 570),
	Vector2(1080, 610), Vector2(1270, 700), Vector2(1510, 830), Vector2(1705, 835)
]
var _puddles := [
	[Vector2(320, 780), Vector2(62, 18)], [Vector2(565, 755), Vector2(44, 13)],
	[Vector2(885, 705), Vector2(67, 16)], [Vector2(1125, 690), Vector2(38, 12)],
	[Vector2(1460, 905), Vector2(76, 20)], [Vector2(760, 1005), Vector2(55, 14)]
]


func _ready() -> void:
	z_index = -10
	_create_collisions()
	_create_lights()
	queue_redraw()


func get_landmark(id: String) -> Vector2:
	return landmarks.get(id, Vector2.ZERO)


func _create_collisions() -> void:
	# World limits.
	_add_collision(Rect2(-40, -40, WORLD_SIZE.x + 80, 40))
	_add_collision(Rect2(-40, WORLD_SIZE.y, WORLD_SIZE.x + 80, 40))
	_add_collision(Rect2(-40, 0, 40, WORLD_SIZE.y))
	_add_collision(Rect2(WORLD_SIZE.x, 0, 40, WORLD_SIZE.y))

	# Buildings and heavy walls; all important routes retain generous openings.
	_add_collision(Rect2(610, 245, 250, 155)) # Grey Keep
	_add_collision(Rect2(935, 170, 155, 150)) # signal tower base
	_add_collision(Rect2(1235, 390, 275, 150)) # granary
	_add_collision(Rect2(1080, 770, 220, 105)) # clinic
	_add_collision(Rect2(610, 620, 195, 105)) # barracks
	_add_collision(Rect2(1515, 500, 185, 105)) # refugee shelter
	_add_collision(Rect2(1480, 975, 255, 45)) # water channel wall
	# Outer wall segments, broken at west and south gates.
	_add_collision(Rect2(425, 160, 40, 420))
	_add_collision(Rect2(425, 765, 40, 225))
	_add_collision(Rect2(425, 160, 1410, 35))
	_add_collision(Rect2(1810, 160, 35, 650))
	_add_collision(Rect2(1810, 1000, 35, 80))


func _add_collision(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	collision.position = rect.position + rect.size * 0.5
	body.add_child(collision)
	add_child(body)


func _create_lights() -> void:
	for lantern_position in _lanterns:
		var light := PointLight2D.new()
		light.position = lantern_position
		light.energy = 0.72
		light.texture_scale = 2.15
		light.color = Color("efb85b")
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
		gradient.colors = PackedColorArray([Color(1, 0.76, 0.35, 0.75), Color(1, 0.56, 0.22, 0.24), Color(0.15, 0.2, 0.22, 0.0)])
		var texture := GradientTexture2D.new()
		texture.width = 96
		texture.height = 96
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.gradient = gradient
		light.texture = texture
		add_child(light)


func _draw() -> void:
	# Fen water and a cold, rain-dark ground plane.
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("15262a"), true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, 570), Vector2(425, 520), Vector2(425, 1160), Vector2(0, 1160)
	]), Color("17353a"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(1220, 955), Vector2(1960, 890), Vector2(1960, 1160), Vector2(1110, 1160)
	]), Color("102f35"))

	# Mud roads converge at Greyfen.
	var road := Color("4a4a43")
	draw_colored_polygon(PackedVector2Array([Vector2(110, 950), Vector2(90, 820), Vector2(510, 630), Vector2(560, 720)]), road)
	draw_colored_polygon(PackedVector2Array([Vector2(480, 610), Vector2(1760, 580), Vector2(1780, 725), Vector2(480, 750)]), road.darkened(0.05))
	draw_colored_polygon(PackedVector2Array([Vector2(950, 610), Vector2(1085, 610), Vector2(1125, 1160), Vector2(920, 1160)]), road.darkened(0.08))
	draw_polyline(PackedVector2Array([Vector2(150, 885), Vector2(470, 680), Vector2(1030, 675), Vector2(1680, 660)]), Color(0.75, 0.68, 0.52, 0.12), 3.0, true)

	# Reed beds, enough individual strokes to create depth without texture assets.
	for index in range(118):
		var x := fmod(float(index * 83), WORLD_SIZE.x)
		var bank := 760.0 + sin(float(index) * 2.17) * 160.0
		if x > 440.0 and x < 1210.0:
			bank += 310.0
		var height := 13.0 + float(index % 7) * 3.2
		var base := Vector2(x, clampf(bank + float((index * 37) % 130), 600.0, 1140.0))
		draw_line(base, base + Vector2(sin(float(index)) * 3.0, -height), Color(0.33, 0.36, 0.22, 0.55), 1.4, true)
		if index % 3 == 0:
			draw_circle(base + Vector2(1, -height), 2.0, Color("756848"))

	# Puddles catch the bronze sky.
	for puddle in _puddles:
		_draw_ellipse_shape(puddle[0], puddle[1], Color(0.36, 0.49, 0.49, 0.24))
		draw_arc(puddle[0] - Vector2(5, 1), puddle[1].x * 0.66, PI * 1.05, PI * 1.83, 18, Color(0.83, 0.61, 0.31, 0.14), 1.2, true)

	_draw_fortress()
	_draw_split_ash()
	_draw_refuge_row()
	_draw_water_gate()


func _draw_fortress() -> void:
	var basalt := Color("252b2d")
	var mortar := Color("485052")
	# Outer wall silhouettes.
	draw_rect(Rect2(425, 160, 40, 420), basalt, true)
	draw_rect(Rect2(425, 765, 40, 225), basalt, true)
	draw_rect(Rect2(425, 160, 1410, 35), basalt, true)
	draw_rect(Rect2(1810, 160, 35, 650), basalt, true)
	draw_rect(Rect2(1810, 1000, 35, 80), basalt, true)
	for x in range(430, 1820, 36):
		draw_line(Vector2(x, 166), Vector2(x + 15, 189), mortar, 1.0)
	# West gate towers.
	_draw_tower(Rect2(405, 548, 78, 105), "WEST GATE")
	_draw_tower(Rect2(405, 718, 78, 86), "")
	# Main buildings.
	_draw_building(Rect2(610, 245, 250, 155), Color("303538"), Color("171c1f"), "GREY KEEP")
	_draw_tower(Rect2(935, 170, 155, 150), "SIGNAL TOWER")
	_draw_building(Rect2(610, 620, 195, 105), Color("34383a"), Color("1b2022"), "OLD WALL")
	_draw_building(Rect2(1235, 390, 275, 150), Color("4a3c31"), Color("201c1a"), "GRANARY")
	_draw_building(Rect2(1080, 770, 220, 105), Color("394341"), Color("202624"), "NESSA'S CLINIC")


func _draw_building(rect: Rect2, wall: Color, roof: Color, label_text: String) -> void:
	draw_rect(rect, wall, true)
	draw_colored_polygon(PackedVector2Array([
		rect.position + Vector2(-12, 8), rect.position + Vector2(rect.size.x * 0.5, -30),
		rect.position + Vector2(rect.size.x + 12, 8), rect.position + Vector2(rect.size.x, 30), rect.position + Vector2(0, 30)
	]), roof)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.46, rect.size.y - 42), Vector2(25, 42)), Color("15191a"), true)
	for x in range(int(rect.position.x + 28), int(rect.end.x - 12), 58):
		draw_rect(Rect2(x, rect.position.y + 48, 21, 25), Color("d49b4d") * Color(1, 1, 1, 0.45), true)
	if not label_text.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(14, rect.size.y - 14), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.82, 0.83, 0.77, 0.62))


func _draw_tower(rect: Rect2, label_text: String) -> void:
	draw_rect(rect, Color("292f31"), true)
	for y in range(int(rect.position.y + 12), int(rect.end.y), 18):
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("454d4f"), 1.0)
	for x in range(int(rect.position.x + 18), int(rect.end.x), 28):
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color("1d2224"), 1.0)
	draw_colored_polygon(PackedVector2Array([
		rect.position + Vector2(-12, 5), rect.position + Vector2(rect.size.x * 0.5, -26), rect.position + Vector2(rect.size.x + 12, 5)
	]), Color("131719"))
	if not label_text.is_empty():
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, rect.size.y - 10), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.77, 0.78, 0.72, 0.62))


func _draw_split_ash() -> void:
	var base := landmarks["split_ash"] as Vector2
	_draw_ellipse_shape(base + Vector2(4, 22), Vector2(48, 13), Color(0.01, 0.02, 0.02, 0.34))
	draw_line(base + Vector2(0, 25), base + Vector2(-6, -82), Color("302a26"), 18.0, true)
	draw_line(base + Vector2(-5, -50), base + Vector2(-42, -116), Color("302a26"), 11.0, true)
	draw_line(base + Vector2(-7, -55), base + Vector2(37, -126), Color("282420"), 10.0, true)
	draw_line(base + Vector2(-35, -103), base + Vector2(-64, -122), Color("292622"), 5.0, true)
	draw_line(base + Vector2(30, -116), base + Vector2(65, -135), Color("24211e"), 4.0, true)
	for index in range(18):
		var leaf := base + Vector2(-57 + (index * 19) % 126, -128 + sin(float(index) * 2.0) * 22)
		draw_circle(leaf, 4.0 + float(index % 3), Color(0.47, 0.31, 0.16, 0.52))


func _draw_refuge_row() -> void:
	# Canvas shelters intentionally read as homes, not an enemy camp.
	for index in range(5):
		var origin := Vector2(1450 + (index % 3) * 105, 675 + (index / 3) * 94)
		draw_colored_polygon(PackedVector2Array([
			origin + Vector2(-42, 30), origin + Vector2(0, -22), origin + Vector2(44, 30)
		]), Color("67584a") if index % 2 == 0 else Color("4e5a58"))
		draw_line(origin + Vector2(0, -22), origin + Vector2(0, 34), Color("2c2824"), 2.0)
		draw_circle(origin + Vector2(0, 18), 5.0, Color(0.94, 0.55, 0.22, 0.45))
	draw_string(ThemeDB.fallback_font, Vector2(1480, 665), "REFUGE ROW", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.83, 0.78, 0.67, 0.62))


func _draw_water_gate() -> void:
	var gate := landmarks["water_gate"] as Vector2
	draw_rect(Rect2(gate - Vector2(94, 35), Vector2(188, 70)), Color("222a2c"), true)
	draw_rect(Rect2(gate - Vector2(75, 29), Vector2(150, 58)), Color("31525a"), true)
	for x in range(-65, 70, 22):
		draw_line(gate + Vector2(x, -28), gate + Vector2(x, 28), Color("151b1d"), 5.0)
	draw_circle(gate + Vector2(-98, 0), 21, Color("6e6049"))
	draw_arc(gate + Vector2(-98, 0), 14, 0, TAU, 16, Color("b08b4f"), 3.0)
	draw_string(ThemeDB.fallback_font, gate + Vector2(-65, 55), "WATER GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.8, 0.79, 0.6))


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
