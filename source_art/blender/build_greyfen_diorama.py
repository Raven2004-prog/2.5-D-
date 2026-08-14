"""Build the original Ashen Diorama Greyfen environment and export it as glTF.

Run with the pinned Blender LTS binary:
  blender.exe --background --factory-startup --python build_greyfen_diorama.py

The file intentionally uses only Blender's bundled Python API.  Every mesh,
material and embedded texture is generated for this project; no marketplace or
third-party game asset is consumed.
"""

from __future__ import annotations

import math
import os
import random
from pathlib import Path

import bpy
from mathutils import Vector


SEED = 472013
ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "ashen" / "environment" / "greyfen_diorama.glb"
BLEND_OUTPUT = ROOT / "source_art" / "blender" / "greyfen_diorama.blend"
random.seed(SEED)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.images):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def create_collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(collection)
    return collection


def activate_collection(collection: bpy.types.Collection) -> None:
    layer = bpy.context.view_layer.layer_collection

    def find(node):
        if node.collection == collection:
            return node
        for child in node.children:
            found = find(child)
            if found:
                return found
        return None

    target = find(layer)
    if target:
        bpy.context.view_layer.active_layer_collection = target


def patterned_rgba(base, accent, pattern: str, size: int = 192):
    pixels = [0.0] * (size * size * 4)
    heights = [0.0] * (size * size)
    for y in range(size):
        for x in range(size):
            nx = x / size
            ny = y / size
            grain = (
                math.sin((x * 0.173) + (y * 0.071)) * 0.05
                + math.sin((x * 0.037) - (y * 0.191)) * 0.035
                + math.sin((x + y) * 0.411) * 0.018
            )
            mask = 0.0
            if pattern == "stone":
                row = int(ny * 8)
                offset = 0.5 / 9.0 if row % 2 else 0.0
                mortar_x = ((nx + offset) * 9.0) % 1.0
                mortar_y = (ny * 8.0) % 1.0
                if mortar_x < 0.055 or mortar_y < 0.065:
                    mask = -0.42
                grain += math.sin((row * 7 + int((nx + offset) * 9)) * 1.7) * 0.035
            elif pattern == "timber":
                grain += math.sin(nx * 54.0 + math.sin(ny * 15.0) * 2.0) * 0.08
                if (x % 48) < 2:
                    mask = -0.25
            elif pattern == "canvas":
                grain += (math.sin(x * 1.7) + math.sin(y * 1.9)) * 0.018
                if (x + y) % 67 == 0:
                    mask = -0.1
            elif pattern == "mud":
                grain += math.sin(nx * 23.0 + math.sin(ny * 31.0)) * 0.08
                grain += math.sin(ny * 41.0) * 0.035
            elif pattern == "water":
                grain += math.sin(nx * 36.0 + math.sin(ny * 11.0) * 3.0) * 0.06
                grain += math.sin(ny * 52.0 + nx * 8.0) * 0.025
            elif pattern == "roof":
                tile_x = (nx * 12.0) % 1.0
                tile_y = (ny * 14.0) % 1.0
                if tile_x < 0.05 or tile_y < 0.06:
                    mask = -0.2
                grain += math.sin((int(nx * 12) + int(ny * 14)) * 2.2) * 0.03
            elif pattern == "metal":
                grain += math.sin(nx * 80.0 + ny * 13.0) * 0.025
                if (x % 64 < 2) or (y % 64 < 2):
                    mask = -0.12

            t = max(-0.35, min(0.35, grain + mask))
            blend = 0.34 + t
            color = [base[i] * (1.0 - blend) + accent[i] * blend for i in range(3)]
            idx = (y * size + x) * 4
            pixels[idx : idx + 4] = [max(0.0, min(1.0, c)) for c in color] + [1.0]
            heights[y * size + x] = max(0.0, min(1.0, 0.5 + t))
    return pixels, heights


def normal_pixels(heights, size: int):
    result = [0.0] * (size * size * 4)
    for y in range(size):
        for x in range(size):
            left = heights[y * size + ((x - 1) % size)]
            right = heights[y * size + ((x + 1) % size)]
            down = heights[((y - 1) % size) * size + x]
            up = heights[((y + 1) % size) * size + x]
            normal = Vector((-(right - left) * 2.2, -(up - down) * 2.2, 1.0)).normalized()
            idx = (y * size + x) * 4
            result[idx : idx + 4] = [normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0]
    return result


def textured_material(name, base, accent, pattern, roughness=0.75, metallic=0.0):
    size = 192
    rgba, heights = patterned_rgba(base, accent, pattern, size)
    image = bpy.data.images.new(f"{name}_albedo", width=size, height=size, alpha=True)
    image.pixels.foreach_set(rgba)
    image.pack()
    normal = bpy.data.images.new(f"{name}_normal", width=size, height=size, alpha=True)
    normal.pixels.foreach_set(normal_pixels(heights, size))
    normal.colorspace_settings.name = "Non-Color"
    normal.pack()

    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.image = image
    albedo_node.interpolation = "Closest"
    links.new(albedo_node.outputs["Color"], principled.inputs["Base Color"])
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.image = normal
    normal_node.interpolation = "Closest"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.42
    links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])
    return material


def flat_material(name, color, roughness=0.7, metallic=0.0, emission=None, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, alpha)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Roughness"].default_value = roughness
    principled.inputs["Metallic"].default_value = metallic
    if emission:
        principled.inputs["Emission Color"].default_value = (*emission, 1.0)
        principled.inputs["Emission Strength"].default_value = 4.0
    if alpha < 1.0:
        principled.inputs["Alpha"].default_value = alpha
        material.surface_render_method = "DITHERED"
    return material


def assign(obj, material):
    if obj.data and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)


def box(name, location, scale, material, collection, bevel=0.0, rotation=(0.0, 0.0, 0.0), uv=True):
    activate_collection(collection)
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (scale[0] / 2.0, scale[1] / 2.0, scale[2] / 2.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = obj.modifiers.new("Rain-softened edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if uv:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=2.5)
        bpy.ops.object.mode_set(mode="OBJECT")
    assign(obj, material)
    return obj


def cylinder(name, location, radius, depth, material, collection, vertices=10, rotation=(0.0, 0.0, 0.0)):
    activate_collection(collection)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign(obj, material)
    return obj


def empty_anchor(name, location, collection):
    obj = bpy.data.objects.new(f"anchor__{name}", None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = 1.2
    obj.location = location
    collection.objects.link(obj)
    return obj


def collision_box(name, location, scale, collection, rotation=(0.0, 0.0, 0.0)):
    # Godot's importer turns *-colonly mesh nodes into StaticBody3D collision.
    return box(f"{name}-colonly", location, scale, COLLISION, collection, rotation=rotation, uv=False)


def lantern(name, location, collection, height=3.0):
    cylinder(f"{name}_post", (location[0], height / 2, location[2]), 0.085, height, IRON, collection, vertices=8)
    box(f"{name}_hood", (location[0], height + 0.28, location[2]), (0.7, 0.12, 0.7), IRON, collection, bevel=0.05)
    cylinder(f"{name}_ward", (location[0], height + 0.05, location[2]), 0.18, 0.42, WARD, collection, vertices=8)


def wall_run(name, start, end, height, collection, gap=None):
    sx, sz = start
    ex, ez = end
    dx, dz = ex - sx, ez - sz
    length = math.sqrt(dx * dx + dz * dz)
    angle = -math.atan2(dz, dx)
    midpoint = ((sx + ex) / 2, height / 2, (sz + ez) / 2)
    if gap:
        # Two wall pieces around a centred opening.
        half = (length - gap) / 2
        ux, uz = dx / length, dz / length
        for index, offset in enumerate((-(gap + half) / 2, (gap + half) / 2)):
            loc = (midpoint[0] + ux * offset, midpoint[1], midpoint[2] + uz * offset)
            box(f"{name}_{index}", loc, (half, height, 1.6), STONE, collection, 0.12, (0, angle, 0))
            collision_box(f"{name}_{index}", loc, (half, height, 1.6), collection, (0, angle, 0))
        return
    box(name, midpoint, (length, height, 1.6), STONE, collection, 0.12, (0, angle, 0))
    collision_box(name, midpoint, (length, height, 1.6), collection, (0, angle, 0))


def battlements(name, start, end, y, collection, count):
    sx, sz = start
    ex, ez = end
    for i in range(count):
        t = (i + 0.5) / count
        x = sx + (ex - sx) * t
        z = sz + (ez - sz) * t
        box(f"{name}_merlon_{i:02d}", (x, y, z), (1.1, 1.0, 1.2), DARK_STONE, collection, 0.08)


def pitched_roof(name, location, size, collection, material=None):
    material = material or ROOF
    width, depth, rise = size
    for side, angle in ((-1, math.radians(-27)), (1, math.radians(27))):
        zoff = side * depth * 0.22
        box(
            f"{name}_{'north' if side < 0 else 'south'}",
            (location[0], location[1], location[2] + zoff),
            (width + 0.8, 0.28, depth * 0.58),
            material,
            collection,
            0.04,
            (angle * side, 0, 0),
        )


def building(name, location, size, collection, wall_material=None, roof_material=None, door_side="south"):
    wall_material = wall_material or TIMBER
    x, y, z = location
    width, height, depth = size
    box(f"{name}_walls", (x, y + height / 2, z), (width, height, depth), wall_material, collection, 0.14)
    collision_box(name, (x, y + height / 2, z), (width, height, depth), collection)
    pitched_roof(f"{name}_roof", (x, y + height + 1.0, z), (width, depth, 2.0), collection, roof_material)
    # Amber windows and a dark framed door visually explain non-walkable walls.
    for offset in (-width * 0.25, width * 0.25):
        box(f"{name}_window_{offset}", (x + offset, y + 2.1, z - depth / 2 - 0.03), (1.0, 1.25, 0.08), WARD_GLASS, collection, 0.03)
    box(f"{name}_door", (x, y + 1.4, z - depth / 2 - 0.06), (1.4, 2.8, 0.12), DARK_TIMBER, collection, 0.04)


def round_tower(name, location, radius, height, collection):
    x, y, z = location
    cylinder(f"{name}_mass", (x, y + height / 2, z), radius, height, STONE, collection, vertices=16)
    cylinder(f"{name}-convcolonly", (x, y + height / 2, z), radius * 0.93, height, COLLISION, collection, vertices=12)
    cylinder(f"{name}_cap", (x, y + height + 0.4, z), radius + 0.45, 0.8, DARK_STONE, collection, vertices=16)
    for index in range(10):
        angle = math.tau * index / 10
        box(
            f"{name}_merlon_{index:02d}",
            (x + math.cos(angle) * (radius - 0.25), y + height + 1.0, z + math.sin(angle) * (radius - 0.25)),
            (0.9, 1.1, 0.9),
            DARK_STONE,
            collection,
            0.07,
            (0, -angle, 0),
        )


def tent(name, location, size, collection, material):
    x, y, z = location
    width, height, depth = size
    for side in (-1, 1):
        angle = math.radians(48 * side)
        box(
            f"{name}_canvas_{side}",
            (x + side * width * 0.18, y + height * 0.5, z),
            (width * 0.58, 0.16, depth),
            material,
            collection,
            0.03,
            (0, 0, angle),
        )
    collision_box(name, (x, y + height * 0.35, z), (width * 0.75, height * 0.7, depth), collection)
    cylinder(f"{name}_ridge", (x, y + height, z), 0.06, depth + 0.5, IRON, collection, vertices=8, rotation=(math.pi / 2, 0, 0))


def scatter_reeds(collection, ranges, count):
    # Reuse one mesh datablock for economical GLB output.
    base = cylinder("reed_master", (0, -20, 0), 0.035, 1.5, REED, collection, vertices=5)
    mesh = base.data
    bpy.data.objects.remove(base, do_unlink=True)
    for i in range(count):
        rx, rz, rw, rd = random.choice(ranges)
        x = random.uniform(rx, rx + rw)
        z = random.uniform(rz, rz + rd)
        if -26 < x < 90 and -15 < z < 35 and random.random() < 0.45:
            continue
        obj = bpy.data.objects.new(f"reed_{i:03d}", mesh)
        obj.location = (x, random.uniform(0.15, 0.32), z)
        obj.scale = (random.uniform(0.8, 1.35), random.uniform(0.8, 1.4), random.uniform(0.8, 1.35))
        obj.rotation_euler[1] = random.uniform(-0.18, 0.18)
        collection.objects.link(obj)


def scatter_stones(collection, ranges, count):
    for i in range(count):
        rx, rz, rw, rd = random.choice(ranges)
        x = random.uniform(rx, rx + rw)
        z = random.uniform(rz, rz + rd)
        scale = random.uniform(0.18, 0.65)
        box(
            f"fen_stone_{i:03d}",
            (x, scale * 0.22, z),
            (scale * random.uniform(1.0, 2.0), scale * 0.45, scale),
            DARK_STONE,
            collection,
            scale * 0.18,
            (random.uniform(-0.2, 0.2), random.random() * math.tau, random.uniform(-0.2, 0.2)),
        )


def configure_world():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.resolution_percentage = 100
    scene.world.color = (0.015, 0.025, 0.035)
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["ashen_diorama_seed"] = SEED
    scene["coordinate_contract"] = "X east-west, Y up, Z north-south; one unit = one metre"


reset_scene()
configure_world()

WORLD = create_collection("Greyfen_Ashen_Diorama")
ANCHOR = create_collection("01_Anchor_Hollow", WORLD)
WEST = create_collection("02_West_Gate", WORLD)
KEEP = create_collection("03_Inner_Bailey", WORLD)
GRANARY = create_collection("04_Granary_Refuge", WORLD)
WATER = create_collection("05_Water_Gate", WORLD)
MARSH = create_collection("Marsh_Dressing", WORLD)

STONE = textured_material("M_WetBasalt", (0.095, 0.125, 0.145), (0.23, 0.30, 0.31), "stone", 0.62)
DARK_STONE = textured_material("M_DarkBasalt", (0.035, 0.052, 0.064), (0.14, 0.19, 0.20), "stone", 0.72)
TIMBER = textured_material("M_RainTimber", (0.11, 0.075, 0.045), (0.34, 0.22, 0.12), "timber", 0.75)
DARK_TIMBER = textured_material("M_CharTimber", (0.04, 0.025, 0.018), (0.16, 0.09, 0.045), "timber", 0.8)
ROOF = textured_material("M_SlateRoof", (0.045, 0.065, 0.085), (0.17, 0.22, 0.25), "roof", 0.5)
MUD = textured_material("M_FenMud", (0.065, 0.055, 0.045), (0.18, 0.145, 0.09), "mud", 0.48)
WATER_MAT = textured_material("M_FenWater", (0.018, 0.075, 0.085), (0.055, 0.20, 0.20), "water", 0.18, 0.08)
CANVAS = textured_material("M_RefugeCanvas", (0.15, 0.13, 0.105), (0.39, 0.29, 0.16), "canvas", 0.82)
CANVAS_RED = textured_material("M_ClinicCanvas", (0.17, 0.07, 0.055), (0.48, 0.19, 0.11), "canvas", 0.8)
IRON = textured_material("M_RainIron", (0.03, 0.04, 0.045), (0.18, 0.21, 0.22), "metal", 0.38, 0.74)
MOSS = flat_material("M_FenMoss", (0.13, 0.22, 0.16), 0.9)
REED = flat_material("M_Reeds", (0.18, 0.25, 0.15), 0.9)
WARD = flat_material("M_WardFlame", (0.95, 0.45, 0.08), 0.25, emission=(1.0, 0.23, 0.02))
WARD_GLASS = flat_material("M_WardGlass", (0.38, 0.19, 0.055), 0.28, emission=(0.8, 0.2, 0.04))
ASH = flat_material("M_AshWhite", (0.55, 0.72, 0.74), 0.55, emission=(0.12, 0.38, 0.42))
COLLISION = flat_material("M_CollisionProxy", (1.0, 0.0, 1.0), 1.0)

# The continuous land mass and deep fen visually establish the playable boundary.
box("FenWater", (0, -0.65, 0), (270, 0.8, 190), WATER_MAT, MARSH, 0.2)
box("GreyfenGround", (0, -0.1, 0), (225, 0.3, 125), MUD, MARSH, 0.25)
collision_box("GreyfenGround", (0, -0.32, 0), (225, 0.5, 125), MARSH)

# Causeway and branch roads form three readable alternate routes.
for index, (loc, scale, angle) in enumerate([
    ((-96, 0.16, 16), (58, 0.28, 8), -0.08),
    ((-51, 0.18, 11), (38, 0.3, 10), 0.04),
    ((-18, 0.2, 4), (36, 0.32, 12), 0.12),
    ((17, 0.22, 8), (42, 0.32, 11), -0.08),
    ((53, 0.22, 17), (38, 0.32, 12), -0.18),
    ((84, 0.18, 27), (32, 0.3, 9), -0.12),
    ((20, 0.18, -25), (78, 0.3, 7), 0.0),
    ((53, 0.18, -3), (8, 0.3, 48), 0.02),
]):
    box(f"Causeway_{index:02d}", loc, scale, DARK_STONE, MARSH, 0.1, (0, angle, 0))

# District 1: exposed Fen Road, split ash, memorial stones and first refuge.
empty_anchor("arrival", (-111, 0.35, 18), ANCHOR)
empty_anchor("split_ash", (-91, 0.35, 14), ANCHOR)
empty_anchor("lysa", (-102, 0.35, 19), ANCHOR)
cylinder("SplitAshTrunk", (-91, 2.8, 14), 0.65, 5.6, DARK_TIMBER, ANCHOR, vertices=9, rotation=(0.04, 0, 0.13))
for branch in range(7):
    angle = -0.85 + branch * 0.28
    cylinder(
        f"SplitAshBranch_{branch}",
        (-91 + math.sin(angle) * 1.3, 5.4 + branch * 0.12, 14 + math.cos(angle) * 0.7),
        0.16,
        3.2,
        DARK_TIMBER,
        ANCHOR,
        vertices=7,
        rotation=(math.radians(62), angle, 0),
    )
for i in range(9):
    box(f"Memorial_{i}", (-107 + i * 2.0, 0.55, 8.5 + (i % 2) * 0.8), (0.7, 1.1 + (i % 3) * 0.25, 0.4), STONE, ANCHOR, 0.13)
lantern("FenRoadWard", (-80, 0, 12), ANCHOR, 3.2)

# District 2: monumental gate and barracks.
empty_anchor("west_gate_entry", (-70, 0.35, 11), WEST)
empty_anchor("brann", (-61, 0.35, 8), WEST)
empty_anchor("west_patrol_a", (-73, 0.35, 20), WEST)
empty_anchor("west_patrol_b", (-48, 0.35, 21), WEST)
round_tower("WestTowerNorth", (-63, 0, -3), 5.5, 12.5, WEST)
round_tower("WestTowerSouth", (-63, 0, 20), 5.5, 12.5, WEST)
wall_run("WestCurtainNorth", (-63, -3), (-40, -3), 9.0, WEST)
wall_run("WestCurtainSouth", (-63, 20), (-40, 20), 9.0, WEST)
wall_run("WestGateCrosswall", (-63, -3), (-63, 20), 9.0, WEST, gap=8.0)
battlements("WestNorth", (-60, -3), (-41, -3), 9.5, WEST, 10)
battlements("WestSouth", (-60, 20), (-41, 20), 9.5, WEST, 10)
building("Barracks", (-43, 0, 12), (17, 7, 10), WEST, STONE, ROOF)
for x in (-68, -58, -49):
    lantern(f"WestWard_{x}", (x, 0, 11), WEST, 3.7)

# District 3: keep, oathstone and signal yard.
empty_anchor("mara_keep", (-4, 0.35, -5), KEEP)
empty_anchor("tamsin", (-12, 0.35, 4), KEEP)
empty_anchor("piri_signal", (10, 0.35, -18), KEEP)
empty_anchor("signal_horn", (12, 2.2, -21), KEEP)
building("GreatKeep", (-5, 0, -5), (28, 13, 20), KEEP, STONE, ROOF)
round_tower("KeepTowerA", (-19, 0, -14), 4.2, 15.5, KEEP)
round_tower("KeepTowerB", (9, 0, -14), 4.2, 15.5, KEEP)
cylinder("Oathstone", (-19, 1.8, 8), 1.7, 3.6, ASH, KEEP, vertices=9)
round_tower("SignalTower", (13, 0, -23), 4.4, 18.0, KEEP)
cylinder("SignalHorn", (13, 18.7, -23), 0.55, 3.1, IRON, KEEP, vertices=12, rotation=(math.pi / 2, 0, math.radians(18)))
for pos in [(-24, 7), (-14, 13), (1, 12), (14, 6)]:
    lantern(f"BaileyWard_{pos[0]}_{pos[1]}", (pos[0], 0, pos[1]), KEEP, 3.4)

# District 4: granary danger, clinic warmth and the refugee row.
empty_anchor("granary_powder", (35, 0.35, 9), GRANARY)
empty_anchor("nessa_clinic", (41, 0.35, 29), GRANARY)
empty_anchor("kesh", (56, 0.35, 23), GRANARY)
empty_anchor("tomas", (28, 0.35, 8), GRANARY)
empty_anchor("granary_watch_a", (23, 0.35, 18), GRANARY)
empty_anchor("granary_watch_b", (55, 0.35, 10), GRANARY)
building("Granary", (34, 0, 4), (23, 9, 16), GRANARY, TIMBER, ROOF)
# Undercroft entrance is visibly open; collision boxes leave the approach clear.
box("GranaryUndercroftLintel", (34, 2.8, -4.1), (7.0, 1.0, 0.9), STONE, GRANARY, 0.1)
box("PowderEvidence", (35, 0.22, -5.1), (2.1, 0.22, 1.1), ASH, GRANARY, 0.05)
building("Clinic", (42, 0, 32), (18, 6, 11), GRANARY, CANVAS_RED, ROOF)
for row in range(2):
    for col in range(4):
        x = 54 + col * 7.0
        z = 7 + row * 10.0
        tent(f"RefugeTent_{row}_{col}", (x, 0, z), (5.5, 3.8, 7.0), GRANARY, CANVAS if (row + col) % 3 else CANVAS_RED)
for pos in [(20, 15), (30, 20), (42, 21), (56, 30), (70, 27)]:
    lantern(f"GranaryWard_{pos[0]}_{pos[1]}", (pos[0], 0, pos[1]), GRANARY, 3.2)

# District 5: water machinery, drains, a tunnel and exposed fen edge.
empty_anchor("water_gate_wheel", (91, 0.35, 27), WATER)
empty_anchor("tunnel_tracks", (75, 0.35, -2), WATER)
empty_anchor("water_patrol_a", (67, 0.35, 25), WATER)
empty_anchor("water_patrol_b", (96, 0.35, 18), WATER)
wall_run("EastFenWallNorth", (68, -10), (105, -10), 8.0, WATER)
wall_run("EastFenWallSouth", (68, 37), (105, 37), 8.0, WATER)
round_tower("WaterTowerA", (101, 0, 1), 5.0, 12.0, WATER)
round_tower("WaterTowerB", (101, 0, 31), 5.0, 12.0, WATER)
box("WaterGateHouse", (95, 5.0, 16), (12, 10, 20), STONE, WATER, 0.18)
collision_box("WaterGateHouse", (95, 5.0, 16), (12, 10, 20), WATER)
cylinder("WaterWheel", (88.8, 4.0, 17), 4.0, 0.65, TIMBER, WATER, vertices=16, rotation=(0, math.pi / 2, 0))
for spoke in range(8):
    angle = math.tau * spoke / 8
    box(
        f"WaterWheelSpoke_{spoke}",
        (88.4, 4.0 + math.sin(angle) * 1.9, 17 + math.cos(angle) * 1.9),
        (0.7, 0.2, 4.1),
        DARK_TIMBER,
        WATER,
        0.04,
        (angle, 0, 0),
    )
box("DrainChannel", (74, -0.05, -2), (38, 0.22, 5.0), WATER_MAT, WATER, 0.04)
box("TunnelMouth", (74, 2.4, -7.0), (8, 4.8, 1.2), DARK_STONE, WATER, 0.15)
for x in (70, 82, 94):
    lantern(f"WaterWard_{x}", (x, 0, 27), WATER, 3.5)

# Boundary walls wrap the stronghold but leave the causeway and water approaches readable.
wall_run("NorthCurtainA", (-40, -38), (26, -38), 8.0, MARSH)
wall_run("NorthCurtainB", (26, -38), (68, -10), 8.0, MARSH)
wall_run("SouthCurtainA", (-40, 52), (34, 52), 8.0, MARSH)
wall_run("SouthCurtainB", (34, 52), (68, 37), 8.0, MARSH)
wall_run("WestReturnNorth", (-40, -38), (-40, -3), 8.0, MARSH)
wall_run("WestReturnSouth", (-40, 20), (-40, 52), 8.0, MARSH)

scatter_reeds(MARSH, [(-132, -74, 264, 20), (-132, 52, 264, 20), (-132, -54, 22, 110), (112, -54, 20, 110)], 420)
scatter_stones(MARSH, [(-124, -32, 52, 70), (102, -20, 18, 70), (-60, 40, 130, 12)], 90)

# Player-facing stage anchors and optional shortcut nodes.
for name, loc in {
    "stage_arrival": (-111, 0.35, 18),
    "stage_reach_mara": (-16, 0.35, 2),
    "stage_granary": (25, 0.35, 9),
    "stage_return_two": (0, 0.35, 10),
    "stage_return_three": (2, 0.35, 8),
    "stage_finale": (34, 0.35, 18),
    "stage_tribunal": (-6, 0.35, 4),
    "shortcut_drain": (65, 0.35, -3),
    "shortcut_barracks": (-34, 0.35, 10),
    "shortcut_granary": (23, 0.35, -4),
    "shortcut_refuge": (61, 0.35, 34),
}.items():
    empty_anchor(name, loc, WORLD)

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
BLEND_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUTPUT))
bpy.ops.export_scene.gltf(
    filepath=str(OUTPUT),
    export_format="GLB",
    export_apply=True,
    export_yup=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_extras=True,
)
print(f"ASHEN_DIORAMA_EXPORTED={OUTPUT}")
