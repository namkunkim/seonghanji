extends SceneTree

## 글리프 검산 — 화면이 그리는 모든 문자를 서체가 담는가 (FNT-001·002)
##
## 실행: godot --headless --path . --script tests/verify_glyphs.gd
## 종료 코드: 누락이 있으면 1
##
## **왜 이 검사가 필요한가.** 헤드리스 검증 4종(import·run_tests·quit-after·
## validate_data)은 「오류가 없는가」를 본다. 두부(□)는 오류가 아니라 정상
## 렌더링이라 넷 다 통과시킨다. 2026-08-30 조사에서 실제로 확인됐다 —
## 코어가 SystemFont(맑은 고딕)를 빌리고 있었고 PC 에서는 멀쩡했으나
## 실기(안드로이드)에는 그 이름이 없어 폴백이 두부까지 흐를 수 있었다.
##
## `verify_power`·`verify_budget`·`verify_chibi` 가 「문서와 코드가 갈라지는
## 순간」을 잡는 장치라면, 이건 「서체와 화면이 갈라지는 순간」을 잡는다.
##
## 규칙:
##   - 한글 음절 11,172 자 → **임베드 폰트가 직접** 담아야 한다 (폴백 불가).
##     한글이 폴백(시스템 서체)에 기대면 실기에서 깨진다. 하나라도 없으면 경성 실패.
##   - app/ 가 실제로 쓰는 그 밖의 문자 → 폴백 포함 전체 사슬에서 담기면 통과.
##     임베드 폰트엔 없고 폴백에만 있으면 경고(기기 의존).

const SCAN_DIRS: Array[String] = ["res://app"]
const HANGUL_FIRST := 0xAC00
const HANGUL_LAST := 0xD7A3


func _init() -> void:
	print("")
	print("글리프 검산 — FNT-001·002 · app/ 코퍼스 대조")

	var theme := UiPalette.make_theme()
	var body: Font = theme.default_font
	var title: Font = theme.get_font("font", "Title")
	print("  본문 : %s  (폴백 %d)" % [body.get_font_name(), body.fallbacks.size()])
	print("  제목 : %s  (폴백 %d)" % [title.get_font_name(), title.fallbacks.size()])
	print("")

	var fail := 0
	var warn := 0
	if not _has_weight(body, 400) or not _has_weight(title, 700):
		fail += 1
		print("  ✗ FNT 굵기 설정 오류 — 본문 400 · 제목 700이어야 한다")


	# ── 1. 한글 음절 — 임베드 폰트가 직접 담아야 한다 ────────────────────
	var embed := _embedded_font(body)
	var syl_miss_embed := 0
	var syl_miss_title := 0
	var cp := HANGUL_FIRST
	while cp <= HANGUL_LAST:
		if not embed.has_char(cp):
			syl_miss_embed += 1
		if not _embedded_font(title).has_char(cp):
			syl_miss_title += 1
		cp += 1
	print("한글 음절 11,172 자")
	print("  본문 임베드 누락 : %d" % syl_miss_embed)
	print("  제목 임베드 누락 : %d" % syl_miss_title)
	if syl_miss_embed > 0 or syl_miss_title > 0:
		fail += 1
		print("  ✗ 한글이 임베드 폰트에 없다 — 실기에서 두부가 된다")
	print("")

	# ── 2. app/ 가 실제로 쓰는 비 ASCII 문자 ───────────────────────────
	var used := _scan_used_chars()
	print("app/ 스캔 — 비 ASCII 문자 %d 종" % used.size())
	var miss_all := ""       # 사슬 전체에서 없음 → 경성 실패
	var miss_embed_only := ""  # 임베드엔 없고 폴백엔 있음 → 경고
	for c: String in used:
		var u: int = c.unicode_at(0)
		if HANGUL_FIRST <= u and u <= HANGUL_LAST:
			continue  # 1번에서 전수 검사함
		var in_embed := embed.has_char(u)
		var in_chain := _chain_has(body, u)
		if not in_chain:
			miss_all += c
		elif not in_embed:
			miss_embed_only += c
	if miss_all != "":
		fail += 1
		print("  ✗ 어느 폰트에도 없음 : %s" % miss_all)
		for c in miss_all:
			print("      U+%04X  %s" % [c.unicode_at(0), _where(c)])
	if miss_embed_only != "":
		warn += 1
		print("  ⚠ 임베드엔 없고 시스템 폴백에만 있음 (기기 의존) : %s" % miss_embed_only)
		print("      Noto Sans KR 이 안 담는 장식 기호. 실기에서 시스템 서체가")
		print("      대신 그린다. screens.md §8(실측 레이아웃)에서 대체 문자 검토.")
	if miss_all == "" and miss_embed_only == "":
		print("  ✓ 전부 임베드 폰트가 담는다")
	print("")

	# ── 3. 대표 문자열 눈으로 확인용 덤프 ──────────────────────────────
	for s in ["건안 십삼년 시월", "형주 성역 · 중부권", "제3함대  편성",
			"어린진 학익진 봉시진 조운진 언월진 장사진 방원진"]:
		var bad := ""
		for i in s.length():
			if s.unicode_at(i) != 0x20 and not _chain_has(body, s.unicode_at(i)):
				bad += s[i]
		print("  %s %s%s" % ["OK  " if bad == "" else "MISS", s,
			"   ← " + bad if bad else ""])
	print("")

	print("결과 : 실패 %d · 경고 %d" % [fail, warn])
	if fail == 0:
		print("한글 전수 임베드 · app/ 코퍼스 전부 렌더 가능")
	quit(1 if fail > 0 else 0)


## FontVariation 이면 base_font(임베드 .ttf)를, 아니면 자신을 돌려준다.
## 폴백을 타지 않은 「그 폰트 자체」의 커버리지를 보려는 것.
static func _embedded_font(f: Font) -> Font:
	if f is FontVariation and (f as FontVariation).base_font != null:
		return (f as FontVariation).base_font
	return f


static func _has_weight(f: Font, expected: int) -> bool:
	return f is FontVariation and int((f as FontVariation).variation_opentype.get("wght", -1)) == expected


## 폰트 + 폴백 사슬을 재귀로 훑는다. Godot 4.7 의 Font.has_char() 는
## fallbacks 를 안 탄다 — 셰이핑은 타므로 여기서 손으로 맞춰 본다.
static func _chain_has(f: Font, cp: int) -> bool:
	if f == null:
		return false
	if f.has_char(cp):
		return true
	for fb in f.fallbacks:
		if _chain_has(fb, cp):
			return true
	return false


var _used_cache: Dictionary = {}

func _scan_used_chars() -> Array:
	var seen := {}
	for root in SCAN_DIRS:
		_scan_dir(root, seen)
	var out := seen.keys()
	out.sort()
	return out


func _scan_dir(path: String, seen: Dictionary) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full, seen)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			var txt := FileAccess.get_file_as_string(full)
			for i in txt.length():
				var u := txt.unicode_at(i)
				if u > 0x7F:
					var ch := txt[i]
					seen[ch] = true
					if not _used_cache.has(ch):
						_used_cache[ch] = name
		name = d.get_next()
	d.list_dir_end()


func _where(c: String) -> String:
	return _used_cache.get(c, "?")
