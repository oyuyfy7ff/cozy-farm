extends Node
## ระบบเศรษฐกิจ: เงิน คลังผลผลิต ราคาตลาด ผู้ซื้อ และอัปเกรด

signal changed
signal day_changed(day)
signal buyers_changed
signal message(text)

const SAVE_PATH := "user://save.json"
const DAY_LENGTH := 60.0
const MAX_BUYERS := 4
const MAX_LAND_LVL := 4

# ราคาเมล็ด / ราคากลาง / เวลาโต (วินาที)
const CROPS := {
	"wheat": {"name": "ข้าวสาลี", "seed": 5, "base": 12, "grow": 20.0},
	"carrot": {"name": "แครอท", "seed": 8, "base": 20, "grow": 35.0},
	"strawberry": {"name": "สตรอว์เบอร์รี", "seed": 15, "base": 40, "grow": 60.0},
	"corn": {"name": "ข้าวโพด", "seed": 25, "base": 75, "grow": 100.0},
	"pumpkin": {"name": "ฟักทอง", "seed": 50, "base": 160, "grow": 180.0},
}

const BUYER_KINDS := {
	"kid": {"name": "เด็กน้อย", "qty": [1, 2], "mult": 1.15, "patience": 45.0, "weight": 4},
	"chef": {"name": "แม่ครัว", "qty": [2, 4], "mult": 1.3, "patience": 50.0, "weight": 3},
	"merchant": {"name": "พ่อค้าคนกลาง", "qty": [5, 10], "mult": 0.9, "patience": 70.0, "weight": 3},
	"rich": {"name": "เศรษฐี", "qty": [1, 3], "mult": 2.2, "patience": 25.0, "weight": 1},
}

var money: int = 30
var day: int = 1
var day_time: float = 0.0
var inv: Dictionary = {}
var price_mult: Dictionary = {}
var land_lvl: int = 0
var grow_lvl: int = 0
var water_lvl: int = 0
var total_earned: int = 0
var buyers: Array = []
var _spawn_t: float = 4.0
var _next_id: int = 1
var _save_t: float = 0.0

func _ready() -> void:
	randomize()
	for k in CROPS:
		inv[k] = 0
		price_mult[k] = 1.0
	load_game()

func _process(delta: float) -> void:
	day_time += delta
	if day_time >= DAY_LENGTH:
		day_time = 0.0
		day += 1
		_new_day()
	# ผู้ซื้อ
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(8.0, 16.0)
		if buyers.size() < MAX_BUYERS:
			_spawn_buyer()
	var left := false
	for b in buyers.duplicate():
		b["patience"] -= delta
		if b["patience"] <= 0.0:
			buyers.erase(b)
			left = true
	if left:
		buyers_changed.emit()
	_save_t += delta
	if _save_t > 10.0:
		_save_t = 0.0
		save_game()

func _new_day() -> void:
	for k in CROPS:
		var m: float = price_mult[k] + randf_range(-0.25, 0.25)
		price_mult[k] = clampf(m, 0.6, 1.8)
	message.emit("เริ่มวันที่ %d — ราคาตลาดเปลี่ยนแล้ว!" % day)
	day_changed.emit(day)
	changed.emit()
	save_game()

func price(crop: String) -> int:
	return maxi(1, roundi(CROPS[crop]["base"] * price_mult[crop]))

func trend(crop: String) -> String:
	var m: float = price_mult[crop]
	if m >= 1.2:
		return "▲"
	if m <= 0.8:
		return "▼"
	return "•"

func _spawn_buyer() -> void:
	var total := 0
	for k in BUYER_KINDS:
		total += BUYER_KINDS[k]["weight"]
	var r := randi() % total
	var kind := "kid"
	for k in BUYER_KINDS:
		r -= BUYER_KINDS[k]["weight"]
		if r < 0:
			kind = k
			break
	var def: Dictionary = BUYER_KINDS[kind]
	var crop: String = CROPS.keys()[randi() % CROPS.size()]
	var q: int = randi_range(def["qty"][0], def["qty"][1])
	buyers.append({
		"id": _next_id, "kind": kind, "name": def["name"], "crop": crop,
		"qty": q, "mult": def["mult"], "patience": def["patience"], "max": def["patience"],
	})
	_next_id += 1
	buyers_changed.emit()

func offer(b: Dictionary) -> int:
	return roundi(price(b["crop"]) * b["qty"] * b["mult"])

func can_sell_to(b: Dictionary) -> bool:
	return inv[b["crop"]] >= b["qty"]

func sell_to(id: int) -> bool:
	for b in buyers:
		if b["id"] == id:
			if not can_sell_to(b):
				message.emit("ผลผลิตไม่พอ ต้องการ %s x%d" % [CROPS[b["crop"]]["name"], b["qty"]])
				return false
			var gain := offer(b)
			inv[b["crop"]] -= b["qty"]
			add_money(gain)
			buyers.erase(b)
			message.emit("%s จ่าย %d เหรียญ" % [b["name"], gain])
			buyers_changed.emit()
			return true
	return false

## ขายที่ตลาดกลางทั้งหมด (ราคา 70%)
func sell_all_market() -> int:
	var gain := 0
	for k in CROPS:
		gain += roundi(price(k) * inv[k] * 0.7)
		inv[k] = 0
	if gain > 0:
		add_money(gain)
		message.emit("ขายที่ตลาดกลางได้ %d เหรียญ" % gain)
	else:
		message.emit("ไม่มีผลผลิตให้ขาย")
	return gain

func add_money(n: int) -> void:
	money += n
	if n > 0:
		total_earned += n
	changed.emit()

func spend(n: int) -> bool:
	if money < n:
		return false
	money -= n
	changed.emit()
	return true

func add_crop(k: String, n: int = 1) -> void:
	inv[k] += n
	changed.emit()

# ---------- อัปเกรด ----------
func land_size() -> int:
	return 5 + land_lvl

func land_cost() -> int:
	return 150 * (land_lvl + 1) * (land_lvl + 1)

func grow_cost() -> int:
	return 120 * (grow_lvl + 1)

func water_cost() -> int:
	return 200 * (water_lvl + 1)

func grow_speed() -> float:
	return 1.0 + 0.2 * grow_lvl

func buy_land() -> bool:
	if land_lvl >= MAX_LAND_LVL:
		return false
	if not spend(land_cost()):
		message.emit("เงินไม่พอ")
		return false
	land_lvl += 1
	changed.emit()
	return true

func buy_grow() -> bool:
	if grow_lvl >= 5:
		return false
	if not spend(grow_cost()):
		message.emit("เงินไม่พอ")
		return false
	grow_lvl += 1
	changed.emit()
	return true

func buy_water() -> bool:
	if water_lvl >= 2:
		return false
	if not spend(water_cost()):
		message.emit("เงินไม่พอ")
		return false
	water_lvl += 1
	changed.emit()
	return true

# ---------- เซฟ ----------
func save_game(extra: Dictionary = {}) -> void:
	if not extra.is_empty():
		_extra = extra
	var data := {
		"money": money, "day": day, "inv": inv, "price_mult": price_mult,
		"land_lvl": land_lvl, "grow_lvl": grow_lvl, "water_lvl": water_lvl,
		"total_earned": total_earned, "tiles": _extra.get("tiles", _tiles_cache),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

var _extra: Dictionary = {}
var _tiles_cache: Array = []
var loaded_tiles: Array = []

func set_tiles_for_save(t: Array) -> void:
	_tiles_cache = t

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	money = int(d.get("money", money))
	day = int(d.get("day", day))
	land_lvl = int(d.get("land_lvl", 0))
	grow_lvl = int(d.get("grow_lvl", 0))
	water_lvl = int(d.get("water_lvl", 0))
	total_earned = int(d.get("total_earned", 0))
	for k in CROPS:
		inv[k] = int(d.get("inv", {}).get(k, 0))
		price_mult[k] = float(d.get("price_mult", {}).get(k, 1.0))
	loaded_tiles = d.get("tiles", [])

func reset_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	money = 30
	day = 1
	day_time = 0.0
	land_lvl = 0
	grow_lvl = 0
	water_lvl = 0
	total_earned = 0
	loaded_tiles = []
	buyers.clear()
	for k in CROPS:
		inv[k] = 0
		price_mult[k] = 1.0
	changed.emit()
	buyers_changed.emit()
