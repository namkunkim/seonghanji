class_name PortraitFrame
extends PanelContainer

## P0-04 V-50 승인 공용 초상의 실제 UI 프레임.
## 마스터를 복사·보정하지 않고 승인 PNG만 Texture2D로 읽는다.

const FINAL_DIR := "res://assets/preproduction/p0-04/production-v1/final/flux/"
const FRAME_SIZE := Vector2(256, 320) # 4:5 · P0-04 UI 검수 기준
const CHIP_SIZE := Vector2(64, 64)    # SC-F3 후보/담당관 칩 — 정사각 상단 크롭

var _image: TextureRect
var _art_id := ""


func _ready() -> void:
	clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_HI
	style.border_color = UiPalette.ACCENT
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)


static func all_art_ids() -> Array[String]:
	return ["ART-C901", "ART-C902", "ART-C903", "ART-C904", "ART-C905",
		"ART-C906", "ART-C907", "ART-C908", "ART-C909", "ART-C910", "ART-C911"]


static func asset_path(art_id: String) -> String:
	return FINAL_DIR + art_id + ".png"


## V-43 공용표를 런타임에서 재현한다. C901/C902는 고정적인 id 홀짝으로 분리한다.
static func art_id_for(character: Dictionary) -> String:
	var classes = character.get("class", [])
	var class0 := String(classes[0]) if classes is Array and not classes.is_empty() else "관"
	var disposition := String(character.get("disposition", "실무"))
	match class0:
		"제":
			if disposition == "무뢰": return "ART-C903"
			if disposition == "절의": return "ART-C904"
			if disposition != "실무": return "ART-C905"
			var id := String(character.get("id", "CHR-0000"))
			var suffix := id.trim_prefix("CHR-").to_int()
			return "ART-C901" if suffix % 2 == 0 else "ART-C902"
		"관": return "ART-C906" if disposition == "실무" else "ART-C907"
		"참": return "ART-C908" if disposition == "실무" else "ART-C909"
		"강": return "ART-C910"
		"파": return "ART-C911"
	return "ART-C907"


func set_character(character: Dictionary, chip: bool = false) -> void:
	set_art_id(art_id_for(character), chip)


func set_art_id(art_id: String, chip: bool = false) -> void:
	_art_id = art_id
	custom_minimum_size = CHIP_SIZE if chip else FRAME_SIZE
	if _image == null:
		await ready
	var texture := load(asset_path(_art_id)) as Texture2D
	_image.texture = texture
	tooltip_text = "%s · 승인 공용 초상" % _art_id


func art_id() -> String:
	return _art_id
