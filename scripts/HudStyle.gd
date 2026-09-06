extends RefCounted
class_name HudStyle

static func panel_style(alpha: float = 0.82) -> StyleBoxFlat:
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = Color(0.008,0.028,0.050,alpha)
    s.border_color = Color(0.19,0.66,0.94,0.78)
    s.set_border_width_all(1)
    s.corner_radius_top_left = 5
    s.corner_radius_top_right = 5
    s.corner_radius_bottom_left = 5
    s.corner_radius_bottom_right = 5
    s.shadow_color = Color(0.0,0.55,0.95,0.16)
    s.shadow_size = 8
    return s

static func button_style(active: bool = false) -> StyleBoxFlat:
    var s: StyleBoxFlat = StyleBoxFlat.new()
    s.bg_color = Color(0.025,0.14,0.23,0.96) if active else Color(0.012,0.042,0.068,0.78)
    s.border_color = Color(0.48,0.88,1.0,1.0) if active else Color(0.36,0.80,1.0,0.28)
    s.set_border_width_all(2 if active else 1)
    s.corner_radius_top_left = 4
    s.corner_radius_top_right = 4
    s.corner_radius_bottom_left = 4
    s.corner_radius_bottom_right = 4
    s.content_margin_left = 14
    s.content_margin_right = 10
    s.shadow_color = Color(0.0,0.58,1.0,0.30 if active else 0.08)
    s.shadow_size = 7 if active else 2
    return s

static func button_hover_style() -> StyleBoxFlat:
    var s := button_style(false)
    s.bg_color = Color(0.020,0.090,0.140,0.92)
    s.border_color = Color(0.42,0.82,1.0,0.72)
    s.shadow_color = Color(0.0,0.55,1.0,0.18)
    s.shadow_size = 4
    return s

static func button_selected_style() -> StyleBoxFlat:
    return button_style(true)

static func button_pressed_style() -> StyleBoxFlat:
    var s := button_style(false)
    s.bg_color = Color(0.008,0.060,0.095,0.98)
    s.border_color = Color(0.40,0.78,0.96,0.88)
    s.set_border_width_all(1)
    s.content_margin_top = 1
    s.content_margin_bottom = -1
    s.shadow_color = Color(0.0,0.40,0.72,0.10)
    s.shadow_size = 1
    return s

static func button_disabled_style() -> StyleBoxFlat:
    var s := button_style(false)
    s.bg_color = Color(0.018,0.028,0.036,0.78)
    s.border_color = Color(0.28,0.34,0.38,0.34)
    s.shadow_color = Color(0,0,0,0)
    s.shadow_size = 0
    return s


static func resource_style() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.012,0.045,0.074,0.96)
    s.border_color = Color(0.30,0.70,0.92,0.72)
    s.border_width_top = 1
    s.border_width_left = 1
    s.border_width_right = 1
    s.border_width_bottom = 1
    s.corner_radius_top_left = 5
    s.corner_radius_top_right = 5
    s.corner_radius_bottom_left = 5
    s.corner_radius_bottom_right = 5
    s.content_margin_left = 9
    s.content_margin_right = 9
    return s

static func resource_hover_style() -> StyleBoxFlat:
    var s := resource_style()
    s.bg_color = Color(0.035,0.13,0.20,0.98)
    s.border_color = Color(0.44,0.84,1.0,0.90)
    s.shadow_color = Color(0.0,0.55,1.0,0.16)
    s.shadow_size = 4
    return s

static func resource_pressed_style() -> StyleBoxFlat:
    var s := resource_style()
    s.bg_color = Color(0.008,0.055,0.086,0.99)
    s.border_color = Color(0.38,0.76,0.94,0.90)
    s.content_margin_top = 1
    s.content_margin_bottom = -1
    s.shadow_color = Color(0.0,0.40,0.72,0.10)
    s.shadow_size = 1
    return s

static func resource_selected_style() -> StyleBoxFlat:
    var s := resource_style()
    s.bg_color = Color(0.030,0.145,0.220,0.99)
    s.border_color = Color(0.54,0.90,1.0,1.0)
    s.set_border_width_all(2)
    s.shadow_color = Color(0.0,0.62,1.0,0.30)
    s.shadow_size = 7
    return s

static func resource_disabled_style() -> StyleBoxFlat:
    var s := resource_style()
    s.bg_color = Color(0.018,0.028,0.036,0.78)
    s.border_color = Color(0.28,0.34,0.38,0.34)
    s.shadow_color = Color(0,0,0,0)
    s.shadow_size = 0
    return s

static func card_style(active: bool = false, hover: bool = false,
        pressed: bool = false, disabled: bool = false) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    if disabled:
        s.bg_color = Color(0.016,0.024,0.030,0.86)
        s.border_color = Color(0.28,0.34,0.38,0.34)
    elif pressed:
        s.bg_color = Color(0.004,0.050,0.080,0.99)
        s.border_color = Color(0.38,0.76,0.94,0.90)
    elif active:
        s.bg_color = Color(0.012,0.075,0.120,0.99)
        s.border_color = Color(0.52,0.90,1.0,1.0)
    elif hover:
        s.bg_color = Color(0.010,0.045,0.072,0.99)
        s.border_color = Color(0.38,0.80,1.0,0.82)
    else:
        s.bg_color = Color(0.006,0.026,0.046,0.98)
        s.border_color = Color(0.32,0.78,1.0,0.66)
    s.set_border_width_all(1)
    if active:
        s.set_border_width_all(2)
    s.corner_radius_top_left = 5
    s.corner_radius_top_right = 5
    s.corner_radius_bottom_left = 5
    s.corner_radius_bottom_right = 5
    if disabled:
        s.shadow_color = Color(0,0,0,0)
        s.shadow_size = 0
    elif pressed:
        s.shadow_color = Color(0.0,0.40,0.72,0.10)
        s.shadow_size = 1
        s.content_margin_top = 5
        s.content_margin_bottom = 3
    elif active:
        s.shadow_color = Color(0.0,0.62,1.0,0.30)
        s.shadow_size = 9
    elif hover:
        s.shadow_color = Color(0.0,0.55,1.0,0.18)
        s.shadow_size = 5
    else:
        s.shadow_color = Color(0.0,0.55,1.0,0.10)
        s.shadow_size = 3
    s.content_margin_left = 5
    s.content_margin_right = 5
    if not pressed:
        s.content_margin_top = 4
        s.content_margin_bottom = 4
    return s

static func card_pressed_style() -> StyleBoxFlat:
    return card_style(false,false,true,false)

static func card_selected_style() -> StyleBoxFlat:
    return card_style(true,false,false,false)

static func card_hover_style() -> StyleBoxFlat:
    return card_style(false,true,false,false)

static func card_disabled_style() -> StyleBoxFlat:
    return card_style(false,false,false,true)

static func focus_style(radius: int = 5) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0,0,0,0)
    s.border_color = Color(0.72,0.94,1.0,0.98)
    s.set_border_width_all(2)
    s.corner_radius_top_left = radius
    s.corner_radius_top_right = radius
    s.corner_radius_bottom_left = radius
    s.corner_radius_bottom_right = radius
    s.expand_margin_left = 2
    s.expand_margin_top = 2
    s.expand_margin_right = 2
    s.expand_margin_bottom = 2
    return s

static func button_focus_style() -> StyleBoxFlat:
    return focus_style(4)

static func resource_focus_style() -> StyleBoxFlat:
    return focus_style(5)

static func card_focus_style() -> StyleBoxFlat:
    return focus_style(5)

static func badge_style(active: bool = false) -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.025,0.28,0.48,1.0) if active else Color(0.015,0.12,0.20,0.98)
    s.border_color = Color(0.56,0.88,1.0,1.0)
    s.set_border_width_all(1)
    s.corner_radius_top_left = 4
    s.corner_radius_top_right = 4
    s.corner_radius_bottom_left = 4
    s.corner_radius_bottom_right = 4
    s.shadow_color = Color(0.0,0.55,1.0,0.32)
    s.shadow_size = 4
    return s

static func caption_style() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.004,0.022,0.038,0.97)
    s.border_color = Color(0.22,0.58,0.78,0.45)
    s.border_width_top = 1
    s.content_margin_left = 7
    s.content_margin_right = 7
    s.content_margin_top = 4
    s.content_margin_bottom = 4
    return s

static func news_style() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.018,0.060,0.092,0.86)
    s.border_color = Color(0.28,0.62,0.80,0.42)
    s.border_width_left = 2
    s.border_width_bottom = 1
    s.content_margin_left = 9
    s.content_margin_right = 7
    s.content_margin_top = 4
    s.content_margin_bottom = 4
    return s

static func section_style() -> StyleBoxFlat:
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.020,0.075,0.115,0.86)
    s.border_color = Color(0.34,0.72,0.92,0.55)
    s.border_width_bottom = 1
    s.content_margin_left = 8
    s.content_margin_right = 8
    return s
