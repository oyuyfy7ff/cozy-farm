extends Node3D
## ฟาร์มสุขใจ — ฟาร์ม 3D สไตล์การ์ตูนลอวโพล (โมเดลทุกชิ้นสร้างจากโค้ด ไม่มีไฟล์โมเดล)

const MAXN := 9
const CENTER := 4.0
const FONT_PATH := "res://fonts/Sarabun-Bold.ttf"
const CIDX := {"": 0, "wheat": 1, "carrot": 2, "strawberry": 3, "corn": 4, "pumpkin": 5}

var CROP_COL := {
	"wheat": Color("e8c547"), "carrot": Color("ff8c1a"), "strawberry": Color("e8334a"),
	"corn": Color("ffd93d"), "pumpkin": Color("ff7a1a"),
}
var KIND_COL := {
	"kid": Color("ffd23f"), "chef": Color("f4f4f4"), "merchant": Color("a0663a"), "rich": Color("8e5bd6"),
}

var font: Font
var tiles: Array = []
var tile_nodes: Array = []
var tool_mode := "plant"
var seed_kind := "wheat"
var hover := Vector2i(-1, -1)
var dragging := false
var last_tile := Vector2i(-1, -1)
var t := 0.0
var floats: Array = []
var _sync_t := 0.0
var _mats := {}
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var hover_mesh: MeshInstance3D
var buyer_nodes := {}
var chickens: Array = []

# UI refs
var root_ui: Control
var money_label: Label
var day_label: Label
var day_bar: ProgressBar
var inv_label: Label
var buyers_box: VBoxContainer
var bar_refs: Array = []
var toast_panel: PanelContainer
var toast_label: Label
var toast_tween: Tween
var popup: PanelContainer
var popup_vbox: VBoxContainer
var popup_mode := ""
var tool_btns := {}
var seed_btns := {}
var reset_armed := false

func _ready() -> void:
	font = ThemeDB.fallback_font
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH) as Font
	_init_tiles()
	_build_world()
	_build_ui()
	Eco.changed.connect(_on_eco_changed)
	Eco.buyers_changed.connect(_rebuild_buyers)
	Eco.buyers_changed.connect(_rebuild_buyers3d)
	Eco.message.connect(_toast)
	_on_eco_changed()
	_rebuild_buyers()
	_rebuild_buyers3d()

# =====================================================================
#  ข้อมูลแปลง
# =====================================================================
func _init_tiles() -> void:
	tiles.clear()
	for y in MAXN:
		var row: Array = []
		for x in MAXN:
			row.append({"s": 0, "c": "", "g": 0.0, "w": 0.0})
		tiles.append(row)
	var lt: Array = Eco.loaded_tiles
	if lt.size() == MAXN * MAXN:
		var i := 0
		for y in MAXN:
			for x in MAXN:
				var e = lt[i]
				i += 1
				if typeof(e) == TYPE_ARRAY and e.size() == 4:
					tiles[y][x] = {"s": int(e[0]), "c": str(e[1]), "g": float(e[2]), "w": float(e[3])}

func _sync_tiles() -> void:
	var flat: Array = []
	for y in MAXN:
		for x in MAXN:
			var tl: Dictionary = tiles[y][x]
			flat.append([tl["s"], tl["c"], snappedf(tl["g"], 0.001), snappedf(tl["w"], 0.1)])
	Eco.set_tiles_for_save(flat)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_sync_tiles()
		Eco.save_game()

func tile_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - CENTER, 0.0, c.y - CENTER)

func _in_land(c: Vector2i) -> bool:
	var n := Eco.land_size()
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n

func _ground(sp: Vector2) -> Vector2i:
	var from := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return Vector2i(-1, -1)
	var p: Vector3 = hit
	return Vector2i(floori(p.x + CENTER + 0.5), floori(p.z + CENTER + 0.5))

# =====================================================================
#  อินพุต + ลอจิก
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		dragging = e.pressed
		if e.pressed:
			last_tile = Vector2i(-1, -1)
			_act_at(e.position)
	elif e is InputEventMouseMotion:
		hover = _ground(e.position)
		if dragging:
			_act_at(e.position)

func _act_at(sp: Vector2) -> void:
	if sp.y > 604.0 or sp.x > 880.0:
		return
	var c := _ground(sp)
	if not _in_land(c) or c == last_tile:
		return
	last_tile = c
	var tl: Dictionary = tiles[c.y][c.x]
	var pos := tile_world(c)
	match tool_mode:
		"till":
			if tl["s"] == 0:
				tl["s"] = 1
				_float(pos, "ไถแล้ว", Color("f2d6a8"))
		"plant":
			if tl["s"] == 2:
				return
			var cost: int = Eco.CROPS[seed_kind]["seed"]
			if not Eco.spend(cost):
				_toast("เงินไม่พอซื้อเมล็ด")
				return
			tl["s"] = 2
			tl["c"] = seed_kind
			tl["g"] = 0.0
			tl["w"] = 0.0
			_float(pos, "-฿%d" % cost, Color("ffb3b3"))
		"water":
			var r: int = Eco.water_lvl
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var q := Vector2i(c.x + dx, c.y + dy)
					if _in_land(q):
						var tq: Dictionary = tiles[q.y][q.x]
						if tq["s"] >= 1:
							tq["w"] = 30.0
			_float(pos, "รดน้ำ", Color("9fdcff"))
		"harvest":
			if tl["s"] == 2 and tl["g"] >= 1.0:
				var amount := 1
				if randf() < 0.2 + 0.05 * Eco.grow_lvl:
					amount = 2
				var k: String = tl["c"]
				Eco.add_crop(k, amount)
				tl["s"] = 1
				tl["c"] = ""
				tl["g"] = 0.0
				_float(pos, "+%d %s" % [amount, Eco.CROPS[k]["name"]], Color("fff7a8"))

func _float(p: Vector3, txt: String, col: Color) -> void:
	var l := label3d(self, txt, p + Vector3(0, 0.9, 0), 44, col, 0.012)
	floats.append({"n": l, "t": 0.0, "col": col, "p": l.position})

func _process(delta: float) -> void:
	t += delta
	# การเติบโตของพืช
	for y in MAXN:
		for x in MAXN:
			var tl: Dictionary = tiles[y][x]
			if tl["w"] > 0.0:
				tl["w"] -= delta
			if tl["s"] == 2 and tl["g"] < 1.0:
				var rate: float = Eco.grow_speed() / Eco.CROPS[tl["c"]]["grow"]
				if tl["w"] <= 0.0:
					rate *= 0.25
				tl["g"] = minf(1.0, tl["g"] + rate * delta)
	_update_tiles()
	# ตัวเลขลอย
	var keep: Array = []
	for f in floats:
		f["t"] += delta
		var l: Label3D = f["n"]
		if f["t"] >= 1.3:
			l.queue_free()
			continue
		var a: float = 1.0 - float(f["t"]) / 1.3
		var fp: Vector3 = f["p"]
		l.position = fp + Vector3(0, float(f["t"]) * 0.9, 0)
		var c: Color = f["col"]
		c.a = a
		l.modulate = c
		l.outline_modulate = Color(0.2, 0.1, 0.05, a)
		keep.append(f)
	floats = keep
	# ไฮไลต์แปลง
	if _in_land(hover):
		hover_mesh.visible = true
		hover_mesh.position = Vector3(hover.x - CENTER, 0.17, hover.y - CENTER)
	else:
		hover_mesh.visible = false
	# ผู้ซื้อ
	for id in buyer_nodes:
		var e: Dictionary = buyer_nodes[id]
		var n: Node3D = e["node"]
		var b: Dictionary = e["b"]
		var tp: Vector3 = e["target"]
		n.position.x = move_toward(n.position.x, tp.x, 4.0 * delta)
		n.position.z = tp.z
		n.position.y = absf(sin(t * 3.0 + float(id))) * 0.03
		var urgent: bool = b["patience"] < 10.0
		n.rotation.z = sin(t * 28.0) * 0.06 if urgent else 0.0
	for e in bar_refs:
		var bb: Dictionary = e[1]
		e[0].value = bb["patience"]
	day_bar.value = Eco.day_time
	# ไก่เดินเล่น
	for c in chickens:
		var cn: Node3D = c["n"]
		c["wait"] -= delta
		if c["wait"] > 0.0:
			continue
		var tg: Vector3 = c["target"]
		var d := tg - cn.position
		d.y = 0.0
		if d.length() < 0.08:
			c["wait"] = randf_range(1.0, 3.5)
			c["target"] = Vector3(randf_range(-9.0, -5.4), 0.0, randf_range(-3.0, -0.4))
		else:
			var dn := d.normalized()
			cn.position += dn * 0.6 * delta
			cn.rotation.y = atan2(dn.x, dn.z)
			cn.position.y = absf(sin(t * 14.0)) * 0.04
	# กลางวัน-กลางคืน
	var p: float = Eco.day_time / Eco.DAY_LENGTH
	var night := 0.0
	if p > 0.8:
		night = (p - 0.8) / 0.2
	elif p < 0.06:
		night = (0.06 - p) / 0.06
	night = clampf(night, 0.0, 1.0)
	var dusk := clampf((p - 0.62) / 0.18, 0.0, 1.0) * (1.0 - night)
	sun.light_energy = lerpf(1.1, 0.35, night)
	sun.light_color = Color("fff1d6").lerp(Color("ffb070"), dusk).lerp(Color("8fa6ff"), night)
	env.ambient_light_energy = lerpf(0.6, 0.45, night)
	env.ambient_light_color = Color("dfe9ff").lerp(Color("ffd9b0"), dusk).lerp(Color("5a6ab0"), night)
	env.background_color = Color("9fdcff").lerp(Color("1a2250"), night)
	_sync_t += delta
	if _sync_t > 3.0:
		_sync_t = 0.0
		_sync_tiles()

# =====================================================================
#  ตัวช่วยสร้างโมเดล
# =====================================================================
func M(col: Color) -> StandardMaterial3D:
	var k := col.to_html()
	if not _mats.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.85
		_mats[k] = m
	return _mats[k]

func _mi(parent: Node, mesh: Mesh, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = M(col)
	mi.position = pos
	parent.add_child(mi)
	return mi

func box(parent: Node, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mi(parent, m, pos, col)

func ball(parent: Node, r: float, pos: Vector3, col: Color, squash: float = 1.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0 * squash
	m.radial_segments = 14
	m.rings = 7
	return _mi(parent, m, pos, col)

func cyl(parent: Node, rt: float, rb: float, h: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	return _mi(parent, m, pos, col)

func prism(parent: Node, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return _mi(parent, m, pos, col)

func capsule(parent: Node, r: float, h: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = 10
	m.rings = 4
	return _mi(parent, m, pos, col)

func label3d(parent: Node, txt: String, pos: Vector3, size: int, col: Color, px: float = 0.01) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.outline_size = 14
	l.outline_modulate = Color(0.2, 0.1, 0.05, 1.0)
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	parent.add_child(l)
	return l

func _h(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663)) % 1000

# =====================================================================
#  สร้างโลก 3D
# =====================================================================
func _build_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9fdcff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("dfe9ff")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.5
	cam.far = 220.0
	var pitch := deg_to_rad(48.0)
	cam.position = Vector3(0.0, sin(pitch), cos(pitch)) * 23.0 + Vector3(4.9, 0.0, 0.0) + Vector3(0.0, -cos(pitch), sin(pitch)) * 0.47
	cam.rotation_degrees = Vector3(-48.0, 0.0, 0.0)
	add_child(cam)
	cam.current = true

	var gm := PlaneMesh.new()
	gm.size = Vector2(180.0, 180.0)
	var ground := _mi(self, gm, Vector3.ZERO, Color("7ec850"))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# หญ้าและดอกไม้กระจาย
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.09
	tuft.height = 0.32
	tuft.radial_segments = 5
	tuft.rings = 1
	_scatter(tuft, Color("5fb040"), 260, 11, 0.14, 1.0)
	var fl := SphereMesh.new()
	fl.radius = 0.07
	fl.height = 0.14
	fl.radial_segments = 6
	fl.rings = 3
	_scatter(fl, Color("fff3a0"), 40, 21, 0.1, 1.0)
	_scatter(fl, Color("ffb3d9"), 40, 22, 0.1, 1.0)
	_scatter(fl, Color("ffffff"), 30, 23, 0.1, 1.0)

	hover_mesh = box(self, Vector3(0.98, 0.03, 0.98), Vector3.ZERO, Color.WHITE)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1, 1, 1, 0.38)
	hover_mesh.material_override = hm
	hover_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hover_mesh.visible = false

	_build_tiles()
	_build_fence()
	_build_barn(Vector3(-6.6, 0.0, -4.9))
	_build_pond(Vector3(-6.9, 0.0, 1.9))
	_build_stall(Vector3(7.2, 0.0, 0.8))
	_build_path()
	for tp in [Vector3(-9.5, 0, -1.0), Vector3(-9.2, 0, 4.2), Vector3(-3.5, 0, 6.8), Vector3(3.0, 0, 7.4),
			Vector3(9.4, 0, 5.4), Vector3(10.5, 0, -2.5), Vector3(-1.5, 0, -7.4), Vector3(4.5, 0, -7.2),
			Vector3(9.0, 0, -6.5), Vector3(-10.4, 0, -6.0)]:
		_make_tree(self, tp, 1.0 + float(int(absf(tp.x * 3.0 + tp.z)) % 4) * 0.07)
	for bp in [Vector3(-4.6, 0, 6.0), Vector3(6.0, 0, 6.6), Vector3(-8.4, 0, -2.3), Vector3(10.0, 0, 2.6)]:
		_make_bush(self, bp)
	for i in 3:
		var ch := _make_chicken(Vector3(-8.0 + i * 0.8, 0.0, -1.8))
		chickens.append({"n": ch, "wait": randf_range(0.5, 2.5), "target": ch.position})

func _scatter(mesh: Mesh, col: Color, n: int, seed_v: int, y: float, sc: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	for i in n:
		var p := Vector3(rng.randf_range(-18.0, 18.0), y, rng.randf_range(-13.0, 16.0))
		if absf(p.x) < 5.4 and absf(p.z) < 5.4:
			p.x = (1.0 if p.x >= 0.0 else -1.0) * rng.randf_range(5.6, 18.0)
		var b := Basis().scaled(Vector3.ONE * sc * rng.randf_range(0.7, 1.3))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = M(col)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _build_tiles() -> void:
	tile_nodes.clear()
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color("ffe35a")
	for y in MAXN:
		var row: Array = []
		for x in MAXN:
			var root := Node3D.new()
			root.position = Vector3(x - CENTER, 0.0, y - CENTER)
			add_child(root)
			var gcol := Color("90da62") if (x + y) % 2 == 0 else Color("86d058")
			var base := box(root, Vector3(0.97, 0.08, 0.97), Vector3(0, 0.04, 0), gcol)
			var soil := Node3D.new()
			root.add_child(soil)
			var soil_box := box(soil, Vector3(0.97, 0.15, 0.97), Vector3(0, 0.075, 0), Color("9a6532"))
			var furrows: Array = []
			for fx in [-0.28, 0.0, 0.28]:
				furrows.append(box(soil, Vector3(0.14, 0.03, 0.84), Vector3(fx, 0.15, 0), Color("7b4d25")))
			var cropn := Node3D.new()
			root.add_child(cropn)
			var ready := ball(root, 0.11, Vector3(0, 1.5, 0), Color("ffe35a"))
			ready.material_override = gold
			ready.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var decor := Node3D.new()
			root.add_child(decor)
			_build_decor(decor, _h(x, y))
			row.append({"root": root, "base": base, "soil": soil, "soil_box": soil_box, "furrows": furrows,
				"crop": cropn, "ready": ready, "decor": decor, "sig": -1})
		tile_nodes.append(row)

func _build_decor(parent: Node3D, hv: int) -> void:
	match hv % 5:
		0:
			_make_tree(parent, Vector3.ZERO, 0.8 + float(hv % 7) * 0.05)
		1:
			_make_bush(parent, Vector3.ZERO)
		2:
			for i in 4:
				var ox := float((hv * 7 + i * 31) % 60) / 100.0 - 0.3
				var oz := float((hv * 11 + i * 17) % 60) / 100.0 - 0.3
				var fc: Color = [Color("fff3a0"), Color("ffb3d9"), Color("ffffff"), Color("c9a0ff")][(hv + i) % 4]
				cyl(parent, 0.012, 0.012, 0.2, Vector3(ox, 0.1, oz), Color("3fae4a"))
				ball(parent, 0.065, Vector3(ox, 0.22, oz), fc)
		3:
			if hv % 2 == 0:
				var r := ball(parent, 0.3, Vector3(0, 0.15, 0), Color("8d9096"), 0.7)
				r.rotation_degrees = Vector3(0, hv % 90, 0)
				ball(parent, 0.18, Vector3(0.28, 0.1, 0.1), Color("a3a7ad"), 0.7)

func _make_tree(parent: Node, pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	cyl(n, 0.14, 0.2, 1.1, Vector3(0, 0.55, 0), Color("8a5a2b"))
	ball(n, 0.85, Vector3(0, 1.6, 0), Color("2f9d3a"), 0.9)
	ball(n, 0.65, Vector3(-0.35, 2.05, 0.1), Color("3fae4a"))
	ball(n, 0.55, Vector3(0.35, 2.2, -0.1), Color("55c85a"))
	for a in [Vector3(0.5, 1.6, 0.7), Vector3(-0.6, 1.9, 0.5), Vector3(0.1, 2.45, 0.45)]:
		ball(n, 0.08, a, Color("e8334a"))
	parent.add_child(n)

func _make_bush(parent: Node, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	ball(n, 0.36, Vector3(0, 0.26, 0), Color("2f9d3a"), 0.85)
	ball(n, 0.28, Vector3(0.28, 0.22, 0.1), Color("3fae4a"), 0.85)
	ball(n, 0.26, Vector3(-0.26, 0.2, -0.05), Color("55c85a"), 0.85)
	ball(n, 0.05, Vector3(0.1, 0.4, 0.3), Color("e8334a"))
	ball(n, 0.05, Vector3(-0.3, 0.32, 0.15), Color("e8334a"))
	parent.add_child(n)

func _build_fence() -> void:
	var e := 4.75
	var wood := Color("c9904f")
	var dark := Color("8a5a2b")
	var steps := 10
	for i in range(steps + 1):
		var v := -e + float(i) * (2.0 * e / float(steps))
		box(self, Vector3(0.12, 0.5, 0.12), Vector3(v, 0.25, -e), dark)
		box(self, Vector3(0.12, 0.5, 0.12), Vector3(-e, 0.25, v), dark)
		box(self, Vector3(0.12, 0.5, 0.12), Vector3(e, 0.25, v), dark)
	for yy in [0.2, 0.38]:
		box(self, Vector3(2.0 * e, 0.07, 0.05), Vector3(0, yy, -e), wood)
		box(self, Vector3(0.05, 0.07, 2.0 * e), Vector3(-e, yy, 0), wood)
		box(self, Vector3(0.05, 0.07, 2.0 * e), Vector3(e, yy, 0), wood)

func _build_path() -> void:
	var sand := Color("d8b878")
	var pm := box(self, Vector3(3.2, 0.03, 1.6), Vector3(5.2, 0.015, 1.9), sand)
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm2 := box(self, Vector3(1.6, 0.03, 3.4), Vector3(-6.6, 0.015, -2.0), sand)
	pm2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_barn(pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var red := Color("c4382c")
	var white := Color("f3ead2")
	box(n, Vector3(3.2, 2.0, 2.6), Vector3(0, 1.0, 0), red)
	box(n, Vector3(3.24, 0.12, 2.64), Vector3(0, 0.06, 0), Color("8b8478"))
	for sx in [-1.6, 1.6]:
		box(n, Vector3(0.1, 2.0, 2.66), Vector3(sx, 1.0, 0), white)
	var roof := prism(n, Vector3(3.7, 1.5, 2.9), Vector3(0, 2.75, 0), Color("8f2a21"))
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	prism(n, Vector3(3.2, 1.1, 2.62), Vector3(0, 2.5, 0), red)
	box(n, Vector3(1.1, 1.35, 0.08), Vector3(0, 0.68, 1.32), Color("7c2019"))
	for rz in [45.0, -45.0]:
		var xb := box(n, Vector3(1.55, 0.08, 0.06), Vector3(0, 0.68, 1.38), white)
		xb.rotation_degrees = Vector3(0, 0, rz)
	box(n, Vector3(1.2, 0.08, 0.06), Vector3(0, 1.36, 1.38), white)
	box(n, Vector3(0.08, 1.35, 0.06), Vector3(-0.58, 0.68, 1.38), white)
	box(n, Vector3(0.08, 1.35, 0.06), Vector3(0.58, 0.68, 1.38), white)
	box(n, Vector3(0.5, 0.5, 0.06), Vector3(0, 2.2, 1.33), Color("3a1a14"))
	box(n, Vector3(0.6, 0.06, 0.08), Vector3(0, 2.2, 1.37), white)
	box(n, Vector3(0.06, 0.6, 0.08), Vector3(0, 2.2, 1.37), white)
	# ไซโล
	var sp := Vector3(-2.3, 0.0, 0.1)
	cyl(n, 0.62, 0.62, 3.4, sp + Vector3(0, 1.7, 0), Color("c9ced6"))
	for hy in [0.7, 1.5, 2.3]:
		cyl(n, 0.64, 0.64, 0.06, sp + Vector3(0, hy, 0), Color("8e97a4"))
	cyl(n, 0.0, 0.76, 0.8, sp + Vector3(0, 3.8, 0), Color("8e97a4"))
	# กองฟาง
	for i in 2:
		var hb := cyl(n, 0.4, 0.4, 0.55, Vector3(2.3 + i * 0.5, 0.28, 1.5 - i * 0.25), Color("e4c15a"))
		hb.rotation_degrees = Vector3(0, 0, 90.0)

func _build_pond(pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var sand := cyl(n, 2.2, 2.2, 0.06, Vector3(0, 0.03, 0), Color("d8c28a"))
	sand.scale = Vector3(1.0, 1.0, 0.72)
	var w := cyl(n, 1.95, 1.95, 0.08, Vector3(0, 0.05, 0), Color("3f9ad8"))
	w.scale = Vector3(1.0, 1.0, 0.72)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("48a6e6")
	wm.roughness = 0.12
	wm.metallic = 0.25
	w.material_override = wm
	for lp in [Vector3(0.6, 0.1, 0.2), Vector3(-0.8, 0.1, -0.2), Vector3(0.1, 0.1, 0.6)]:
		cyl(n, 0.3, 0.3, 0.02, lp, Color("3fae4a"))
		ball(n, 0.05, lp + Vector3(0.05, 0.05, 0), Color("f7a8c8"))
	for cp in [Vector3(-2.0, 0, 0.5), Vector3(1.9, 0, -0.4), Vector3(-1.2, 0, 1.2)]:
		cyl(n, 0.02, 0.02, 0.8, cp + Vector3(0, 0.4, 0), Color("4aa63f"))
		cyl(n, 0.05, 0.05, 0.22, cp + Vector3(0, 0.85, 0), Color("6b4423"))
	for rp in [Vector3(1.8, 0.1, 1.0), Vector3(-1.9, 0.1, -0.9)]:
		ball(n, 0.22, rp, Color("8d9096"), 0.7)

func _build_stall(pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	var wood := Color("c28a4b")
	var dark := Color("8a5a2b")
	box(n, Vector3(2.4, 0.75, 0.95), Vector3(0, 0.38, 0), wood)
	box(n, Vector3(2.5, 0.08, 1.05), Vector3(0, 0.78, 0), Color("e0b070"))
	for i in 5:
		box(n, Vector3(0.04, 0.7, 0.02), Vector3(-0.9 + i * 0.45, 0.38, 0.49), dark)
	for sx in [-1.15, 1.15]:
		box(n, Vector3(0.1, 2.0, 0.1), Vector3(sx, 1.0, -0.4), dark)
		box(n, Vector3(0.1, 1.7, 0.1), Vector3(sx, 0.85, 0.45), dark)
	for i in 6:
		var col := Color("d9263f") if i % 2 == 0 else Color("f7efdc")
		var aw := box(n, Vector3(0.43, 0.07, 1.6), Vector3(-1.08 + i * 0.43, 1.85, 0.05), col)
		aw.rotation_degrees = Vector3(14, 0, 0)
	for fi in 5:
		var fc: Color = [Color("d9263f"), Color("f2831f"), Color("f5d63a"), Color("7fae3a"), Color("f08a1c")][fi]
		ball(n, 0.17, Vector3(-0.95 + fi * 0.48, 0.99, 0.05), fc)
	var crate := box(n, Vector3(0.5, 0.35, 0.5), Vector3(-1.7, 0.18, 0.5), Color("b07a3e"))
	crate.rotation_degrees = Vector3(0, 15, 0)
	ball(n, 0.15, Vector3(-1.7, 0.45, 0.5), Color("e8334a"))
	label3d(n, "ตลาด", Vector3(0, 2.6, 0.2), 52, Color("fff3d6"), 0.012)

func _make_chicken(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	ball(n, 0.16, Vector3(0, 0.2, 0), Color("fafafa"), 0.85)
	ball(n, 0.1, Vector3(0, 0.38, 0.12), Color("fafafa"))
	box(n, Vector3(0.03, 0.07, 0.06), Vector3(0, 0.48, 0.12), Color("e8334a"))
	box(n, Vector3(0.04, 0.03, 0.07), Vector3(0, 0.37, 0.2), Color("f2a31f"))
	ball(n, 0.1, Vector3(0, 0.27, -0.15), Color("e6e6e6"), 0.8)
	box(n, Vector3(0.02, 0.1, 0.02), Vector3(-0.05, 0.05, 0), Color("f2a31f"))
	box(n, Vector3(0.02, 0.1, 0.02), Vector3(0.05, 0.05, 0), Color("f2a31f"))
	add_child(n)
	return n

# =====================================================================
#  อัปเดตแปลง / พืช
# =====================================================================
func _update_tiles() -> void:
	var land := Eco.land_size()
	for y in MAXN:
		for x in MAXN:
			var tl: Dictionary = tiles[y][x]
			var n: Dictionary = tile_nodes[y][x]
			var unlocked := x < land and y < land
			var st := -1
			if tl["s"] == 2:
				st = 4 if tl["g"] >= 1.0 else mini(int(float(tl["g"]) * 4.0), 3)
			var wet: bool = tl["w"] > 0.0
			var sig: int = (1 if unlocked else 0) + int(tl["s"]) * 2 + (st + 1) * 8 + (128 if wet else 0) + int(CIDX.get(tl["c"], 0)) * 256
			if sig != n["sig"]:
				n["sig"] = sig
				(n["decor"] as Node3D).visible = not unlocked
				(n["base"] as Node3D).visible = unlocked and tl["s"] == 0
				var soil: Node3D = n["soil"]
				soil.visible = unlocked and tl["s"] >= 1
				var sb: MeshInstance3D = n["soil_box"]
				sb.material_override = M(Color("62401f") if wet else Color("9a6532"))
				for f in n["furrows"]:
					(f as MeshInstance3D).material_override = M(Color("4a2f16") if wet else Color("7b4d25"))
				var cropn: Node3D = n["crop"]
				for ch in cropn.get_children():
					cropn.remove_child(ch)
					ch.queue_free()
				if st >= 0:
					_build_crop(cropn, tl["c"], st)
			var rd: MeshInstance3D = n["ready"]
			rd.visible = st == 4
			if st == 4:
				rd.position.y = 1.55 + sin(t * 5.0 + float(x + y)) * 0.1

func _build_crop(parent: Node3D, k: String, st: int) -> void:
	var spots := [Vector3(-0.22, 0, -0.22), Vector3(0.22, 0, -0.22), Vector3(-0.22, 0, 0.22), Vector3(0.22, 0, 0.22)]
	var yb := 0.15
	match k:
		"wheat":
			var h: float = [0.12, 0.3, 0.5, 0.65, 0.78][st]
			var cols := [Color("6cc04a"), Color("6cc04a"), Color("a2c64a"), Color("cbb844"), Color("e8c547")]
			for s in spots:
				cyl(parent, 0.03, 0.08, h, s + Vector3(0, yb + h * 0.5, 0), cols[st])
				if st >= 3:
					ball(parent, 0.07, s + Vector3(0, yb + h + 0.03, 0), Color("f0c93c"), 1.9)
		"carrot":
			var lh: float = [0.06, 0.16, 0.24, 0.32, 0.38][st]
			for s in spots:
				cyl(parent, 0.0, 0.11, lh, s + Vector3(0, yb + lh * 0.5, 0), Color("4aa63f"))
				if st >= 2:
					var lf := cyl(parent, 0.0, 0.08, lh * 0.8, s + Vector3(0.07, yb + lh * 0.4, 0.03), Color("78d05a"))
					lf.rotation_degrees = Vector3(0, 0, -20)
				if st == 4:
					cyl(parent, 0.09, 0.0, 0.2, s + Vector3(0, yb - 0.01, 0), Color("f2831f"))
		"strawberry":
			var r: float = [0.05, 0.09, 0.12, 0.14, 0.15][st]
			for s in spots:
				ball(parent, r, s + Vector3(0, yb + r * 0.5, 0), Color("2f9d3a"), 0.75)
				ball(parent, r * 0.7, s + Vector3(r * 0.5, yb + r * 0.9, 0), Color("55c85a"), 0.75)
				if st == 3:
					ball(parent, 0.03, s + Vector3(0, yb + r * 1.1, r * 0.4), Color.WHITE)
				if st == 4:
					ball(parent, 0.055, s + Vector3(r * 0.9, yb + r * 0.3, r * 0.6), Color("e8334a"))
					ball(parent, 0.055, s + Vector3(-r * 0.8, yb + r * 0.35, r * 0.5), Color("e8334a"))
					ball(parent, 0.05, s + Vector3(0.02, yb + r * 1.0, -r * 0.7), Color("ff5a6e"))
		"corn":
			var h: float = [0.12, 0.4, 0.75, 1.1, 1.35][st]
			for s in spots:
				cyl(parent, 0.03, 0.05, h, s + Vector3(0, yb + h * 0.5, 0), Color("4aa63f"))
				if st >= 2:
					var l1 := box(parent, Vector3(0.3, 0.02, 0.07), s + Vector3(0.13, yb + h * 0.55, 0), Color("5cc050"))
					l1.rotation_degrees = Vector3(0, 0, 30)
					var l2 := box(parent, Vector3(0.3, 0.02, 0.07), s + Vector3(-0.13, yb + h * 0.4, 0), Color("4aa63f"))
					l2.rotation_degrees = Vector3(0, 0, -30)
				if st == 4:
					capsule(parent, 0.05, 0.22, s + Vector3(0.07, yb + h * 0.62, 0), Color("f5d63a"))
					box(parent, Vector3(0.18, 0.04, 0.04), s + Vector3(0, yb + h + 0.02, 0), Color("d6b844"))
		"pumpkin":
			var r: float = [0.05, 0.1, 0.14, 0.2, 0.27][st]
			var pc: Color = [Color("5fb04a"), Color("5fb04a"), Color("86b83e"), Color("e0a62e"), Color("f08a1c")][st]
			if st >= 1:
				for lf in [Vector3(-0.3, 0, -0.2), Vector3(0.3, 0, 0.25), Vector3(0.25, 0, -0.3)]:
					cyl(parent, 0.14, 0.14, 0.02, lf + Vector3(0, yb + 0.02, 0), Color("3fae4a"))
			ball(parent, r, Vector3(0, yb + r * 0.7, 0), pc, 0.8)
			if st >= 2:
				cyl(parent, 0.03, 0.045, 0.1, Vector3(0, yb + r * 1.4, 0), Color("2f7a33"))

# =====================================================================
#  ผู้ซื้อ 3D
# =====================================================================
func _make_buyer(b: Dictionary) -> Node3D:
	var n := Node3D.new()
	var col: Color = KIND_COL[b["kind"]]
	var skin := Color("ffd1a1")
	cyl(n, 0.17, 0.26, 0.78, Vector3(0, 0.42, 0), col)
	cyl(n, 0.2, 0.2, 0.06, Vector3(0, 0.07, 0), Color("3a2418"))
	ball(n, 0.2, Vector3(0, 1.02, 0), skin)
	ball(n, 0.03, Vector3(-0.07, 1.05, 0.18), Color("2a1a12"))
	ball(n, 0.03, Vector3(0.07, 1.05, 0.18), Color("2a1a12"))
	box(n, Vector3(0.08, 0.02, 0.02), Vector3(0, 0.97, 0.2), Color("c0504d"))
	ball(n, 0.07, Vector3(-0.27, 0.62, 0), skin)
	ball(n, 0.07, Vector3(0.27, 0.62, 0), skin)
	match b["kind"]:
		"kid":
			ball(n, 0.21, Vector3(0, 1.12, -0.01), Color("d9263f"), 0.6)
			box(n, Vector3(0.24, 0.03, 0.14), Vector3(0, 1.12, 0.2), Color("b01c30"))
		"chef":
			cyl(n, 0.17, 0.17, 0.3, Vector3(0, 1.3, 0), Color("ffffff"))
			ball(n, 0.2, Vector3(0, 1.5, 0), Color("ffffff"), 0.8)
		"merchant":
			cyl(n, 0.34, 0.34, 0.04, Vector3(0, 1.17, 0), Color("6b4423"))
			cyl(n, 0.18, 0.18, 0.2, Vector3(0, 1.27, 0), Color("8a5a2b"))
			box(n, Vector3(0.24, 0.22, 0.12), Vector3(0, 0.55, 0.22), Color("a8733a"))
		"rich":
			cyl(n, 0.3, 0.3, 0.03, Vector3(0, 1.17, 0), Color("1a1a1a"))
			cyl(n, 0.17, 0.17, 0.3, Vector3(0, 1.33, 0), Color("1a1a1a"))
			cyl(n, 0.175, 0.175, 0.05, Vector3(0, 1.24, 0), Color("f5d63a"))
			ball(n, 0.05, Vector3(0, 0.75, 0.22), Color("f5d63a"))
	var cd: Dictionary = Eco.CROPS[b["crop"]]
	ball(n, 0.13, Vector3(0, 1.82, 0), CROP_COL[b["crop"]])
	label3d(n, "%s x%d" % [cd["name"], b["qty"]], Vector3(0, 2.15, 0), 40, Color("fff7a8"), 0.008)
	return n

func _rebuild_buyers3d() -> void:
	var alive := {}
	for b in Eco.buyers:
		alive[b["id"]] = true
	for id in buyer_nodes.keys():
		if not alive.has(id):
			(buyer_nodes[id]["node"] as Node3D).queue_free()
			buyer_nodes.erase(id)
	var i := 0
	for b in Eco.buyers:
		var id: int = b["id"]
		var target := Vector3(5.8 + i * 0.95, 0.0, 2.3)
		if not buyer_nodes.has(id):
			var n := _make_buyer(b)
			n.position = target + Vector3(3.5, 0.0, 0.0)
			add_child(n)
			buyer_nodes[id] = {"node": n, "b": b, "target": target}
		else:
			buyer_nodes[id]["target"] = target
		i += 1

# =====================================================================
#  UI
# =====================================================================
func _style(col: Color, border: Color = Color(0, 0, 0, 0.35)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	return sb

func _btn(text: String, col: Color, toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _style(col))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _style(col.lightened(0.28), Color.WHITE))
	b.add_theme_stylebox_override("hover_pressed", _style(col.lightened(0.28), Color.WHITE))
	b.add_theme_stylebox_override("disabled", _style(Color(0.62, 0.62, 0.62, 0.85)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color("3b2410"))
	b.add_theme_color_override("font_disabled_color", Color("e8e8e8"))
	return b

func _panel(col: Color = Color("fff4d6"), border: Color = Color("c98f4b")) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(col, border))
	return p

func _lbl(text: String, size: int = 22, col: Color = Color("3b2410")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	root_ui = Control.new()
	root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 22
	root_ui.theme = th
	layer.add_child(root_ui)

	# --- แถบบน ---
	var top := _panel()
	top.position = Vector2(10, 8)
	top.custom_minimum_size = Vector2(870, 0)
	root_ui.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 24)
	tv.add_child(r1)
	money_label = _lbl("฿ 0", 32, Color("b36b00"))
	money_label.custom_minimum_size = Vector2(230, 0)
	r1.add_child(money_label)
	day_label = _lbl("วันที่ 1", 26)
	day_label.custom_minimum_size = Vector2(130, 0)
	r1.add_child(day_label)
	day_bar = ProgressBar.new()
	day_bar.max_value = Eco.DAY_LENGTH
	day_bar.show_percentage = false
	day_bar.custom_minimum_size = Vector2(300, 22)
	day_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(day_bar)
	inv_label = _lbl("", 20, Color("6b4423"))
	tv.add_child(inv_label)

	# --- แถบผู้ซื้อ ---
	var rp := _panel(Color("fff9e6"))
	rp.position = Vector2(895, 8)
	rp.custom_minimum_size = Vector2(375, 590)
	root_ui.add_child(rp)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rp.add_child(rv)
	rv.add_child(_lbl("ผู้ซื้อในตลาด", 26, Color("b36b00")))
	buyers_box = VBoxContainer.new()
	buyers_box.add_theme_constant_override("separation", 8)
	rv.add_child(buyers_box)

	# --- แถบล่าง ---
	var bp := _panel(Color("fbe3a6"), Color("b9803a"))
	bp.position = Vector2(0, 606)
	bp.custom_minimum_size = Vector2(1280, 114)
	root_ui.add_child(bp)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bp.add_child(bv)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	bv.add_child(row1)
	var tgroup := ButtonGroup.new()
	var tools := [["till", "ไถดิน", Color("d9a066")], ["plant", "ปลูก", Color("8fd44f")], ["water", "รดน้ำ", Color("7fd6ff")], ["harvest", "เก็บเกี่ยว", Color("ffd23f")]]
	for e in tools:
		var b := _btn(e[1], e[2], true)
		b.button_group = tgroup
		b.custom_minimum_size = Vector2(150, 44)
		b.pressed.connect(_on_tool.bind(e[0]))
		row1.add_child(b)
		tool_btns[e[0]] = b
	tool_btns["plant"].button_pressed = true
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(sp)
	var mb := _btn("ตลาดกลาง", Color("ffb347"))
	mb.custom_minimum_size = Vector2(170, 44)
	mb.pressed.connect(_open_popup.bind("market"))
	row1.add_child(mb)
	var sb := _btn("ร้านอัปเกรด", Color("c9a0ff"))
	sb.custom_minimum_size = Vector2(170, 44)
	sb.pressed.connect(_open_popup.bind("shop"))
	row1.add_child(sb)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	bv.add_child(row2)
	var sgroup := ButtonGroup.new()
	for k in Eco.CROPS:
		var d: Dictionary = Eco.CROPS[k]
		var b := _btn("%s ฿%d" % [d["name"], d["seed"]], CROP_COL[k].lightened(0.25), true)
		b.button_group = sgroup
		b.custom_minimum_size = Vector2(190, 44)
		b.pressed.connect(_on_seed.bind(k))
		row2.add_child(b)
		seed_btns[k] = b
	seed_btns["wheat"].button_pressed = true

	# --- ข้อความลอย ---
	toast_panel = _panel(Color("fff9e6"))
	toast_panel.position = Vector2(300, 96)
	toast_panel.visible = false
	root_ui.add_child(toast_panel)
	toast_label = _lbl("", 22)
	toast_panel.add_child(toast_label)

	# --- ป๊อปอัป ---
	popup = _panel(Color("fff4d6"), Color("b9803a"))
	popup.position = Vector2(300, 100)
	popup.custom_minimum_size = Vector2(560, 0)
	popup.visible = false
	root_ui.add_child(popup)
	popup_vbox = VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 10)
	popup.add_child(popup_vbox)

func _on_tool(k: String) -> void:
	tool_mode = k

func _on_seed(k: String) -> void:
	seed_kind = k
	tool_mode = "plant"
	tool_btns["plant"].button_pressed = true

func _on_eco_changed() -> void:
	money_label.text = "฿ %d" % Eco.money
	day_label.text = "วันที่ %d" % Eco.day
	var parts: Array = []
	for k in Eco.CROPS:
		parts.append("%s %d" % [Eco.CROPS[k]["name"], Eco.inv[k]])
	inv_label.text = "ผลผลิต: " + "  |  ".join(parts)
	if popup.visible:
		_refresh_popup()
	_rebuild_buyers()

func _toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(1.8)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.5)
	toast_tween.tween_callback(func(): toast_panel.visible = false)

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

func _rebuild_buyers() -> void:
	if buyers_box == null:
		return
	_clear(buyers_box)
	bar_refs.clear()
	if Eco.buyers.is_empty():
		buyers_box.add_child(_lbl("กำลังรอผู้ซื้อมาถึง...", 20, Color("8a6b4a")))
		return
	for b in Eco.buyers:
		var cd: Dictionary = Eco.CROPS[b["crop"]]
		var card := _panel(KIND_COL[b["kind"]].lightened(0.6), Color("c98f4b"))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		card.add_child(v)
		v.add_child(_lbl(b["name"], 22, Color("8a4b00")))
		v.add_child(_lbl("ต้องการ %s x%d (มี %d)" % [cd["name"], b["qty"], Eco.inv[b["crop"]]], 19))
		v.add_child(_lbl("จ่าย ฿%d  (ราคา x%.2f)" % [Eco.offer(b), b["mult"]], 19, Color("b36b00")))
		var pb := ProgressBar.new()
		pb.max_value = b["max"]
		pb.value = b["patience"]
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 12)
		v.add_child(pb)
		bar_refs.append([pb, b])
		var sell := _btn("ขายให้เลย", Color("8fd44f"))
		sell.disabled = not Eco.can_sell_to(b)
		sell.pressed.connect(Eco.sell_to.bind(b["id"]))
		v.add_child(sell)
		buyers_box.add_child(card)

# ---------- ป๊อปอัป ----------
func _open_popup(mode: String) -> void:
	if popup.visible and popup_mode == mode:
		popup.visible = false
		return
	popup_mode = mode
	popup.visible = true
	reset_armed = false
	_refresh_popup()

func _refresh_popup() -> void:
	_clear(popup_vbox)
	var head := HBoxContainer.new()
	popup_vbox.add_child(head)
	var title := _lbl("ตลาดกลาง" if popup_mode == "market" else "ร้านอัปเกรด", 28, Color("b36b00"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _btn("ปิด", Color("ff8a80"))
	close.pressed.connect(func(): popup.visible = false)
	head.add_child(close)
	if popup_mode == "market":
		_fill_market()
	else:
		_fill_shop()

func _fill_market() -> void:
	popup_vbox.add_child(_lbl("ราคาเปลี่ยนทุกวัน — ผู้ซื้อตัวจริงทางขวาให้ราคาดีกว่าตลาดกลาง", 18, Color("8a6b4a")))
	for k in Eco.CROPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var n := _lbl(Eco.CROPS[k]["name"], 22)
		n.custom_minimum_size = Vector2(190, 0)
		row.add_child(n)
		var have := _lbl("มี %d" % Eco.inv[k], 22)
		have.custom_minimum_size = Vector2(100, 0)
		row.add_child(have)
		var tr: String = Eco.trend(k)
		var col := Color("2f9d3a") if tr == "▲" else (Color("d6382c") if tr == "▼" else Color("3b2410"))
		row.add_child(_lbl("฿%d %s" % [Eco.price(k), tr], 22, col))
		popup_vbox.add_child(row)
	var sell := _btn("ขายทั้งหมดที่ตลาดกลาง (ได้ 70%)", Color("ffb347"))
	sell.pressed.connect(Eco.sell_all_market)
	popup_vbox.add_child(sell)

func _fill_shop() -> void:
	_shop_row("ขยายที่ดิน", "ที่ดิน %dx%d → %dx%d" % [Eco.land_size(), Eco.land_size(), Eco.land_size() + 1, Eco.land_size() + 1], Eco.land_cost(), Eco.land_lvl >= Eco.MAX_LAND_LVL, Eco.buy_land)
	_shop_row("ปุ๋ยเร่งโต", "พืชโตเร็ว +20%% (ตอนนี้ x%.1f)" % Eco.grow_speed(), Eco.grow_cost(), Eco.grow_lvl >= 5, Eco.buy_grow)
	var wd := ["รดทีละ 1 แปลง", "รดทีละ 3x3", "รดทีละ 5x5"]
	_shop_row("บัวรดน้ำใหญ่", wd[Eco.water_lvl] + ("" if Eco.water_lvl >= 2 else " → " + wd[Eco.water_lvl + 1]), Eco.water_cost(), Eco.water_lvl >= 2, Eco.buy_water)
	popup_vbox.add_child(_lbl("รายได้สะสมทั้งหมด ฿%d" % Eco.total_earned, 18, Color("8a6b4a")))
	var rb := _btn("กดอีกครั้งเพื่อยืนยันเริ่มใหม่" if reset_armed else "เริ่มเกมใหม่", Color("ff8a80"))
	rb.pressed.connect(_on_reset)
	popup_vbox.add_child(rb)

func _shop_row(name: String, desc: String, cost: int, maxed: bool, fn: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_lbl(name, 24))
	v.add_child(_lbl(desc, 18, Color("8a6b4a")))
	row.add_child(v)
	var b := _btn("สูงสุดแล้ว" if maxed else "฿%d" % cost, Color("8fd44f"))
	b.custom_minimum_size = Vector2(140, 44)
	b.disabled = maxed or Eco.money < cost
	b.pressed.connect(fn)
	row.add_child(b)
	popup_vbox.add_child(row)

func _on_reset() -> void:
	if not reset_armed:
		reset_armed = true
		_refresh_popup()
		return
	reset_armed = false
	Eco.reset_game()
	_init_tiles()
	_sync_tiles()
	popup.visible = false
	_toast("เริ่มเกมใหม่แล้ว")
