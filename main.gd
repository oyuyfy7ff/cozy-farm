extends Node2D
## ฟาร์มสุขใจ — เกมฟาร์มไอโซเมตริกสไตล์การ์ตูน (ภาพทุกอย่างวาดด้วยโค้ด)

const TW := 88.0
const TH := 44.0
const MAXN := 9
const ORIGIN := Vector2(470, 125)
const FONT_PATH := "res://fonts/Sarabun-Bold.ttf"

var CROP_COL := {
	"wheat": Color("e8c547"), "carrot": Color("ff8c1a"), "strawberry": Color("e8334a"),
	"corn": Color("ffd93d"), "pumpkin": Color("ff7a1a"),
}
var KIND_COL := {
	"kid": Color("ffd23f"), "chef": Color("f4f4f4"), "merchant": Color("a0663a"), "rich": Color("8e5bd6"),
}

var font: Font
var tiles: Array = []
var tool_mode := "plant"
var seed_kind := "wheat"
var hover := Vector2i(-1, -1)
var dragging := false
var last_tile := Vector2i(-1, -1)
var t := 0.0
var floats: Array = []
var _sync_t := 0.0

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
	_build_ui()
	Eco.changed.connect(_on_eco_changed)
	Eco.buyers_changed.connect(_rebuild_buyers)
	Eco.message.connect(_toast)
	_on_eco_changed()
	_rebuild_buyers()

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

func tile_center(x: int, y: int) -> Vector2:
	return ORIGIN + Vector2((x - y) * TW / 2.0, (x + y) * TH / 2.0)

func screen_to_tile(p: Vector2) -> Vector2i:
	var d := p - ORIGIN
	var gx := (d.x / (TW / 2.0) + d.y / (TH / 2.0)) / 2.0
	var gy := (d.y / (TH / 2.0) - d.x / (TW / 2.0)) / 2.0
	return Vector2i(roundi(gx), roundi(gy))

func _in_land(c: Vector2i) -> bool:
	var n := Eco.land_size()
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n

# =====================================================================
#  อินพุต + ลอจิก
# =====================================================================
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		dragging = e.pressed
		if e.pressed:
			last_tile = Vector2i(-1, -1)
			_act_at(get_global_mouse_position())
	elif e is InputEventMouseMotion:
		hover = screen_to_tile(get_global_mouse_position())
		if dragging:
			_act_at(get_global_mouse_position())

func _act_at(p: Vector2) -> void:
	if p.y > 604.0 or p.x > 880.0:
		return
	var c := screen_to_tile(p)
	if not _in_land(c) or c == last_tile:
		return
	last_tile = c
	var tl: Dictionary = tiles[c.y][c.x]
	var pos := tile_center(c.x, c.y)
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

func _float(p: Vector2, txt: String, col: Color) -> void:
	floats.append({"p": p + Vector2(0, -20), "txt": txt, "t": 0.0, "col": col})

func _process(delta: float) -> void:
	t += delta
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
	for f in floats:
		f["t"] += delta
	floats = floats.filter(func(f): return f["t"] < 1.3)
	for e in bar_refs:
		var b: Dictionary = e[1]
		e[0].value = b["patience"]
	day_bar.value = Eco.day_time
	_sync_t += delta
	if _sync_t > 3.0:
		_sync_t = 0.0
		_sync_tiles()
	queue_redraw()

# =====================================================================
#  วาดภาพ
# =====================================================================
func _h(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663)) % 1000

func _ell(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _txt(p: Vector2, s: String, size: int, col: Color, w: float = 200.0) -> void:
	draw_string_outline(font, Vector2(p.x - w / 2.0, p.y), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 6, Color(0.2, 0.1, 0.05, 0.9))
	draw_string(font, Vector2(p.x - w / 2.0, p.y), s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)

func _draw() -> void:
	_draw_background()
	_draw_far_things()
	_draw_tiles()
	_draw_stall()
	_draw_buyers()
	for p in [Vector2(330, 585), Vector2(190, 560), Vector2(40, 500), Vector2(850, 560)]:
		_tree(p, 1.1)
	_draw_floats()
	_draw_daylight()

func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("8bd450"))
	draw_rect(Rect2(0, 0, 1280, 100), Color("9fdcff"))
	draw_rect(Rect2(0, 62, 1280, 38), Color("c4ecff"))
	_ell(Vector2(160, 104), 300, 42, Color("6fc03f"))
	_ell(Vector2(720, 108), 380, 46, Color("7acb45"))
	_ell(Vector2(1180, 104), 300, 42, Color("6fc03f"))
	draw_rect(Rect2(0, 104, 1280, 616), Color("8bd450"))
	# ก้อนเมฆลอย
	for k in 4:
		var cx := fmod(t * 12.0 + k * 360.0, 1500.0) - 120.0
		var cy := 28.0 + (k % 2) * 26.0
		_ell(Vector2(cx, cy), 46, 15, Color(1, 1, 1, 0.95))
		_ell(Vector2(cx + 28, cy - 9), 30, 14, Color(1, 1, 1, 0.95))
		_ell(Vector2(cx - 26, cy - 5), 26, 12, Color(1, 1, 1, 0.95))
	# กระจุกหญ้า
	for i in 70:
		var gx := float((i * 197) % 1280)
		var gy := 120.0 + float((i * 331) % 480)
		draw_line(Vector2(gx, gy), Vector2(gx - 3, gy - 7), Color("6bbf3a"), 2)
		draw_line(Vector2(gx, gy), Vector2(gx + 3, gy - 8), Color("6bbf3a"), 2)

func _draw_far_things() -> void:
	# บ่อน้ำ
	var pc := Vector2(150, 430)
	_ell(pc + Vector2(0, 5), 78, 32, Color("5aa83a"))
	_ell(pc, 70, 27, Color("7fd6ff"))
	_ell(pc + Vector2(-8, -3), 52, 18, Color("5cc3f2"))
	draw_arc(pc + Vector2(-20, 2), 10, 0, TAU, 20, Color(1, 1, 1, 0.6), 2)
	_ell(pc + Vector2(30, 6), 9, 4, Color("3fae4a"))
	# โรงนา + ไซโล
	var b := Vector2(170, 172)
	_ell(b + Vector2(20, 44), 100, 14, Color(0, 0, 0, 0.15))
	draw_rect(Rect2(b.x + 62, b.y - 40, 30, 82), Color("c9ced6"))
	draw_rect(Rect2(b.x + 62, b.y - 40, 8, 82), Color("e4e8ee"))
	draw_colored_polygon(PackedVector2Array([Vector2(b.x + 58, b.y - 40), Vector2(b.x + 77, b.y - 62), Vector2(b.x + 96, b.y - 40)]), Color("8e97a4"))
	draw_rect(Rect2(b.x - 55, b.y - 30, 110, 72), Color("d6382c"))
	draw_rect(Rect2(b.x - 55, b.y - 30, 110, 6), Color("f26b5e"))
	draw_colored_polygon(PackedVector2Array([Vector2(b.x - 66, b.y - 28), Vector2(b.x, b.y - 88), Vector2(b.x + 66, b.y - 28)]), Color("9e2a22"))
	draw_colored_polygon(PackedVector2Array([Vector2(b.x - 56, b.y - 30), Vector2(b.x, b.y - 80), Vector2(b.x + 56, b.y - 30)]), Color("d6382c"))
	_ell(Vector2(b.x, b.y - 48), 9, 9, Color("fff3d6"))
	draw_rect(Rect2(b.x - 20, b.y + 2, 40, 40), Color("8a1f19"))
	draw_rect(Rect2(b.x - 20, b.y + 2, 40, 40), Color("fff3d6"), false, 3)
	draw_line(Vector2(b.x - 20, b.y + 2), Vector2(b.x + 20, b.y + 42), Color("fff3d6"), 3)
	draw_line(Vector2(b.x + 20, b.y + 2), Vector2(b.x - 20, b.y + 42), Color("fff3d6"), 3)
	# ต้นไม้ไกลๆ
	for p in [Vector2(45, 200), Vector2(75, 330), Vector2(300, 150), Vector2(860, 190), Vector2(30, 120)]:
		_tree(p, 1.0)

func _tree(base: Vector2, s: float) -> void:
	_ell(base + Vector2(0, 2), 22 * s, 7 * s, Color(0, 0, 0, 0.18))
	draw_rect(Rect2(base.x - 5 * s, base.y - 26 * s, 10 * s, 26 * s), Color("8a5a2b"))
	_ell(base + Vector2(0, -42) * s, 24 * s, 21 * s, Color("2f9d3a"))
	_ell(base + Vector2(-15, -30) * s, 17 * s, 15 * s, Color("2a8f35"))
	_ell(base + Vector2(15, -30) * s, 17 * s, 15 * s, Color("2a8f35"))
	_ell(base + Vector2(-6, -50) * s, 13 * s, 11 * s, Color("55c85a"))
	draw_circle(base + Vector2(8, -38) * s, 3 * s, Color("e8334a"))
	draw_circle(base + Vector2(-12, -28) * s, 3 * s, Color("e8334a"))

func _bush(base: Vector2, s: float) -> void:
	_ell(base + Vector2(0, 2), 16 * s, 5 * s, Color(0, 0, 0, 0.15))
	_ell(base + Vector2(-8, -6) * s, 11 * s, 9 * s, Color("2a8f35"))
	_ell(base + Vector2(8, -6) * s, 11 * s, 9 * s, Color("2a8f35"))
	_ell(base + Vector2(0, -11) * s, 11 * s, 9 * s, Color("48b84f"))

func _draw_tiles() -> void:
	var n := Eco.land_size()
	var hw := TW / 2.0
	var hh := TH / 2.0
	for s in range(2 * MAXN - 1):
		for x in range(maxi(0, s - MAXN + 1), mini(s, MAXN - 1) + 1):
			var y := s - x
			var c := tile_center(x, y)
			var unlocked := x < n and y < n
			var tl: Dictionary = tiles[y][x]
			var top: Color
			if not unlocked:
				top = Color("63b23a") if (x + y) % 2 == 0 else Color("5aa834")
			elif tl["s"] == 0:
				top = Color("9be05a") if (x + y) % 2 == 0 else Color("8fd44f")
			else:
				top = Color("6e4523") if tl["w"] > 0.0 else Color("9a6532")
			var side := top.darkened(0.38)
			if unlocked and tl["s"] >= 1:
				side = Color("5e3b1c")
			# ขอบหนา
			draw_colored_polygon(PackedVector2Array([c + Vector2(-hw, 0), c + Vector2(0, hh), c + Vector2(0, hh + 9), c + Vector2(-hw, 9)]), side)
			draw_colored_polygon(PackedVector2Array([c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(0, hh + 9), c + Vector2(hw, 9)]), side.darkened(0.15))
			var dia := PackedVector2Array([c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0)])
			draw_colored_polygon(dia, top)
			var outline := top.darkened(0.2)
			outline.a = 0.8
			draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), outline, 1.5)
			if not unlocked:
				var hv := _h(x, y)
				if hv % 4 == 0:
					_tree(c + Vector2(0, 8), 0.8)
				elif hv % 4 == 1:
					_bush(c + Vector2(0, 6), 1.0)
				continue
			if tl["s"] == 0:
				var hv2 := _h(x, y)
				if hv2 % 5 == 0:
					var fp := c + Vector2((hv2 % 31) - 15, ((hv2 / 7) % 13) - 6)
					draw_circle(fp, 3, Color("fff3a0") if hv2 % 2 == 0 else Color("ffb3d9"))
					draw_circle(fp, 1.2, Color("e8a21a"))
			else:
				var fc := top.darkened(0.22)
				for k in [-1, 0, 1]:
					var o := Vector2(hw, -hh) * 0.32 * k
					draw_line(c + o + Vector2(-hw, -hh) * 0.5, c + o + Vector2(hw, hh) * 0.5, fc, 3)
			if tl["s"] == 2:
				_draw_plants(c, tl)
			if Vector2i(x, y) == hover:
				var hl := PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]])
				draw_polyline(hl, Color(1, 1, 1, 0.9), 3)

func _draw_plants(c: Vector2, tl: Dictionary) -> void:
	var g: float = tl["g"]
	var k: String = tl["c"]
	var sc := 0.35 + 0.65 * minf(g, 1.0)
	var offs := [Vector2(0, -7), Vector2(-17, 3), Vector2(17, 3), Vector2(0, 10)]
	for o in offs:
		_plant(c + o, k, sc, g)
	if g >= 1.0:
		var bob := sin(t * 5.0) * 3.0
		var sp := c + Vector2(0, -34 + bob)
		draw_circle(sp, 7, Color("fff7a8"))
		draw_circle(sp, 7, Color("e8a21a"), false, 2)
		draw_line(sp + Vector2(0, -3), sp + Vector2(0, 3), Color("e8a21a"), 2)

func _plant(b: Vector2, k: String, s: float, g: float) -> void:
	var green := Color("3fae4a")
	match k:
		"wheat":
			for dx in [-4, 0, 4]:
				var top := b + Vector2(dx * s, -22 * s)
				draw_line(b + Vector2(dx * 0.5, 0), top, Color("a8c64a"), 2)
				if g > 0.55:
					_ell(top, 3 * s + 1, 5 * s + 1, Color("e8c547"))
		"carrot":
			for a in [-0.5, 0.0, 0.5]:
				draw_line(b, b + Vector2(sin(a), -cos(a)) * 17 * s, green, 3)
			if g > 0.7:
				draw_circle(b + Vector2(0, 1), 5 * s, Color("ff8c1a"))
		"strawberry":
			_ell(b + Vector2(0, -6 * s), 10 * s, 8 * s, Color("2f9d3a"))
			_ell(b + Vector2(-3, -9 * s), 6 * s, 5 * s, Color("55c85a"))
			if g > 0.5 and g < 1.0:
				draw_circle(b + Vector2(4, -8 * s), 2, Color.WHITE)
			if g >= 1.0:
				draw_circle(b + Vector2(-5, -4), 3.5, Color("e8334a"))
				draw_circle(b + Vector2(5, -8), 3.5, Color("e8334a"))
				draw_circle(b + Vector2(1, -2), 3.5, Color("e8334a"))
		"corn":
			var top2 := b + Vector2(0, -32 * s)
			draw_line(b, top2, Color("2f9d3a"), 4)
			draw_line(b + Vector2(0, -12 * s), b + Vector2(-9 * s, -22 * s), green, 3)
			draw_line(b + Vector2(0, -16 * s), b + Vector2(9 * s, -26 * s), green, 3)
			if g > 0.7:
				_ell(b + Vector2(5 * s, -18 * s), 3.5, 7, Color("ffd93d"))
		"pumpkin":
			draw_line(b, b + Vector2(-8 * s, -4 * s), green, 2)
			if g > 0.5:
				_ell(b + Vector2(0, -7 * s), 11 * s, 9 * s, Color("ff7a1a"))
				draw_arc(b + Vector2(0, -7 * s), 6 * s, PI * 0.6, PI * 1.4, 8, Color("d85f0a"), 2)
				draw_line(b + Vector2(0, -15 * s), b + Vector2(1, -19 * s), Color("2f9d3a"), 3)
			else:
				_ell(b + Vector2(0, -4 * s), 6 * s, 5 * s, green)

func _draw_stall() -> void:
	var S := Vector2(778, 424)
	_ell(S + Vector2(0, 36), 78, 14, Color(0, 0, 0, 0.16))
	draw_line(S + Vector2(-54, -34), S + Vector2(-54, 28), Color("7a4a1f"), 5)
	draw_line(S + Vector2(54, -34), S + Vector2(54, 28), Color("7a4a1f"), 5)
	draw_rect(Rect2(S.x - 58, S.y - 4, 116, 34), Color("c98a4b"))
	draw_rect(Rect2(S.x - 58, S.y - 4, 116, 8), Color("e0a866"))
	draw_rect(Rect2(S.x - 58, S.y - 4, 116, 34), Color("7a4a1f"), false, 3)
	# ของบนเคาน์เตอร์
	draw_circle(S + Vector2(-34, -10), 9, Color("e8334a"))
	draw_circle(S + Vector2(-18, -9), 8, Color("ff8c1a"))
	draw_circle(S + Vector2(2, -10), 9, Color("ffd93d"))
	draw_circle(S + Vector2(22, -10), 10, Color("ff7a1a"))
	draw_circle(S + Vector2(40, -8), 7, Color("e8c547"))
	# หลังคาลายทาง
	for i in 6:
		var x0 := S.x - 62 + i * 21.0
		var col := Color("e8334a") if i % 2 == 0 else Color("fff3d6")
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + 4, S.y - 62), Vector2(x0 + 25, S.y - 62), Vector2(x0 + 21, S.y - 36), Vector2(x0, S.y - 36)]), col)
		draw_circle(Vector2(x0 + 10.5, S.y - 36), 10.5, col)
	_txt(S + Vector2(0, 21), "ตลาด", 20, Color("fff3d6"), 120)

func _draw_buyers() -> void:
	for i in Eco.buyers.size():
		var b: Dictionary = Eco.buyers[i]
		var p := Vector2(700 + i * 62, 512 + sin(t * 3.0 + i) * 2.0)
		var urgent: bool = b["patience"] < 10.0
		if urgent:
			p.x += sin(t * 30.0) * 1.5
		var col: Color = KIND_COL[b["kind"]]
		_ell(p + Vector2(0, 18), 15, 5, Color(0, 0, 0, 0.18))
		_ell(p + Vector2(0, 4), 13, 16, col)
		_ell(p + Vector2(0, -2), 9, 9, col.lightened(0.2))
		draw_circle(p + Vector2(0, -20), 11, Color("ffd1a1"))
		draw_circle(p + Vector2(-4, -21), 1.8, Color("3b2410"))
		draw_circle(p + Vector2(4, -21), 1.8, Color("3b2410"))
		draw_arc(p + Vector2(0, -17), 4, 0.2, PI - 0.2, 8, Color("c0504d"), 1.5)
		match b["kind"]:
			"chef":
				draw_rect(Rect2(p.x - 9, p.y - 40, 18, 12), Color.WHITE)
				_ell(p + Vector2(0, -42), 11, 7, Color.WHITE)
			"merchant":
				_ell(p + Vector2(0, -29), 15, 4, Color("6b4423"))
				draw_rect(Rect2(p.x - 9, p.y - 38, 18, 9), Color("8a5a2b"))
			"rich":
				draw_rect(Rect2(p.x - 14, p.y - 31, 28, 3), Color("222222"))
				draw_rect(Rect2(p.x - 9, p.y - 46, 18, 16), Color("222222"))
				draw_circle(p + Vector2(8, -19), 5, Color("ffd23f"), false, 1.5)
			"kid":
				draw_circle(p + Vector2(0, -30), 6, Color("e8334a"))
		# ฟองคำขอ
		var bp := p + Vector2(-28, -80)
		draw_rect(Rect2(bp.x, bp.y, 56, 28), Color("fff9e6"))
		draw_rect(Rect2(bp.x, bp.y, 56, 28), Color("e8334a") if urgent else Color("c98f4b"), false, 3)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(22, 28), bp + Vector2(34, 28), bp + Vector2(28, 36)]), Color("fff9e6"))
		draw_circle(bp + Vector2(15, 14), 8, CROP_COL[b["crop"]])
		draw_string(font, bp + Vector2(26, 20), "x%d" % b["qty"], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("3b2410"))

func _draw_floats() -> void:
	for f in floats:
		var a := 1.0 - f["t"] / 1.3
		var col: Color = f["col"]
		col.a = a
		var p: Vector2 = f["p"] + Vector2(0, -f["t"] * 38.0)
		draw_string_outline(font, p - Vector2(80, 0), f["txt"], HORIZONTAL_ALIGNMENT_CENTER, 160, 20, 6, Color(0.2, 0.1, 0.05, a))
		draw_string(font, p - Vector2(80, 0), f["txt"], HORIZONTAL_ALIGNMENT_CENTER, 160, 20, col)

func _draw_daylight() -> void:
	var p: float = Eco.day_time / Eco.DAY_LENGTH
	var a := 0.0
	if p > 0.8:
		a = (p - 0.8) / 0.2 * 0.3
	elif p < 0.06:
		a = (0.06 - p) / 0.06 * 0.3
	if a > 0.0:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.1, 0.12, 0.35, a))

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
