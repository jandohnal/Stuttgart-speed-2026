extends RefCounted
## Theme of the main menu, built in code so the accent colour is one value (ACCENT, or any of
## ACCENT_CHOICES) and the icons stay sharp at any scale: they are SVGs in ui/icons rasterized as
## DPITexture, with the red #C8101A mapped to the accent. Font: Saira Condensed from ui/fonts
## (OFL, not in git until downloaded), else the system condensed font (Avenir Next Condensed on macOS).
## Type variations: SetupDropdown, SetupCheckBox, RedButton, FooterButton, SetupLabel, PanelHeader,
## FooterTitle, LogoTop, LogoBottom, ScreenTitle, CaptionLabel, SideText, PlayLabel, CreditsText,
## CreditsValue, CreditsNote and the panels
## SetupPanel, HeaderStrip, CaptionPanel, FooterPanel, Bezel.

const ACCENT := Color("#C8101A")
const ACCENT_CHOICES: Array[Color] = [Color("#C8101A"), Color("#B3001E"), Color("#D4380D"), Color("#1F5AA6")]
const GROUND := Color("#E2D9BB")
const TOP_SHADE := Color("#161512")
const PANEL_BG := Color("#F6F1E0", 0.97)
const PANEL_HEADER := Color("#D6CEB0")
const INK := Color("#1D1B16")
const BORDER := Color("#1E1C18")
const LABEL_INK := Color("#2A2620")
const FIELD_BG := Color("#FFFAF0")
const FIELD_HOVER := Color("#F2E7BF")
const DIVIDER := Color("#BFB594")
const HIGHLIGHT := Color("#F2B705")
const FOOTER_BG := Color("#0E0D0B")
const FOOTER_BORDER := Color("#3A362E")
const FOOTER_MUTED := Color("#8A826C")
const LOGO_LIGHT := Color("#E9E2C8")
const CAPTION_INK := Color("#F4EEDB")
const ICON_RED := Color("#C8101A")  ## the accent as written in the SVGs

const FONT_FILES := {
	600: "res://ui/fonts/SairaCondensed-SemiBold.ttf",
	700: "res://ui/fonts/SairaCondensed-Bold.ttf",
	800: "res://ui/fonts/SairaCondensed-ExtraBold.ttf",
}
const FALLBACK_FONTS := ["Saira Condensed", "Avenir Next Condensed", "Arial Narrow"]
const ITALIC_SLANT := 0.2

static var _fonts := {}  ## weight -> base Font


static func build(accent := ACCENT) -> Theme:
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 21
	t.set_color("font_color", "Label", INK)

	_label(t, "SetupLabel", font(700, 1), 21, LABEL_INK)
	_label(t, "PanelHeader", font(700, 3), 20, INK)
	_label(t, "FooterTitle", font(700, 6), 26, FOOTER_MUTED)
	_label(t, "LogoTop", font(600, 9), 22, LOGO_LIGHT)
	_label(t, "LogoBottom", font(800, 0, true), 50, accent, Color.BLACK, Vector2i(2, 2))
	_label(t, "ScreenTitle", font(800), 64, Color.WHITE, Color(0, 0, 0, 0.6), Vector2i(2, 3))
	_label(t, "CaptionLabel", font(600), 23, CAPTION_INK)
	_label(t, "SideText", font(700, 6), 22, Color(1, 1, 1, 0.55))
	_label(t, "PlayLabel", font(800, 6), 40, Color.WHITE, Color("#3A0000"), Vector2i(2, 2))
	_label(t, "CreditsText", font(600), 21, INK)
	_label(t, "CreditsValue", font(800), 22, accent)
	_label(t, "CreditsNote", font(600), 17, Color(LABEL_INK, 0.7))

	_panel(t, "SetupPanel", _flat(PANEL_BG, 2, BORDER, Vector2(6, 6), 0.3))
	var header := _flat(PANEL_HEADER)
	header.border_width_bottom = 2
	header.border_color = BORDER
	_set_margins(header, 0, 5)
	_panel(t, "HeaderStrip", header)
	var caption := _flat(Color("#0C0B0A", 0.78))
	caption.border_width_top = 3
	caption.border_color = accent
	_set_margins(caption, 20, 10)
	_panel(t, "CaptionPanel", caption)
	var footer := _flat(FOOTER_BG)
	footer.border_width_top = 2
	footer.border_color = FOOTER_BORDER
	_set_margins(footer, 40, 0)
	_panel(t, "FooterPanel", footer)
	var bezel := _flat(Color("#2A2824"), 12, Color("#FFFBEB", 0.45))
	bezel.set_corner_radius_all(574)
	bezel.corner_detail = 64
	bezel.set_expand_margin_all(12)
	bezel.shadow_color = Color(0, 0, 0, 0.45)
	bezel.shadow_size = 70
	bezel.shadow_offset = Vector2(0, 24)
	_panel(t, "Bezel", bezel)

	_dropdown(t, accent)
	_popup(t, accent)
	_checkbox(t, accent)
	_red_button(t, accent)
	_footer_button(t, accent)
	_plain_button(t)
	_dialog(t)
	return t


## Saira Condensed of the weight (600 / 700 / 800), with letter spacing and an optional slant.
static func font(weight: int, spacing := 0, italic := false) -> Font:
	if not _fonts.has(weight):
		_fonts[weight] = _base_font(weight)
	var v := FontVariation.new()
	v.base_font = _fonts[weight]
	v.spacing_glyph = spacing
	if italic:
		v.variation_transform = Transform2D(Vector2(1, ITALIC_SLANT), Vector2(0, 1), Vector2.ZERO)
	return v


## SVG from ui/icons, sharp at any canvas scale, its #C8101A replaced by the accent.
static func icon(icon_name: String, accent := ACCENT) -> Texture2D:
	var svg := FileAccess.get_file_as_string("res://ui/icons/%s.svg" % icon_name)
	return DPITexture.create_from_string(svg, 1.0, 1.0, {ICON_RED: accent})


static func _base_font(weight: int) -> Font:
	var path: String = FONT_FILES[weight]
	if FileAccess.file_exists(path):
		var file := FontFile.new()
		if file.load_dynamic_font(path) == OK:
			return file
	var system := SystemFont.new()
	system.font_names = PackedStringArray(FALLBACK_FONTS)
	system.font_weight = weight
	system.font_stretch = 75
	return system


static func _label(t: Theme, type: String, f: Font, size: int, color: Color,
		shadow := Color.TRANSPARENT, shadow_offset := Vector2i.ZERO) -> void:
	t.set_type_variation(type, "Label")
	t.set_font("font", type, f)
	t.set_font_size("font_size", type, size)
	t.set_color("font_color", type, color)
	if shadow.a > 0:
		t.set_color("font_shadow_color", type, shadow)
		t.set_constant("shadow_offset_x", type, shadow_offset.x)
		t.set_constant("shadow_offset_y", type, shadow_offset.y)


static func _panel(t: Theme, type: String, style: StyleBox) -> void:
	t.set_type_variation(type, "PanelContainer")
	t.set_stylebox("panel", type, style)


## Flat box; a shadow offset gives the hard drop shadow of the design (1 px feather).
static func _flat(bg: Color, border := 0, border_color := BORDER, shadow := Vector2.ZERO, shadow_alpha := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border)
	s.border_color = border_color
	if shadow != Vector2.ZERO:
		s.shadow_color = Color(0, 0, 0, shadow_alpha)
		s.shadow_size = 1
		s.shadow_offset = shadow
	return s


static func _set_margins(s: StyleBox, horizontal: float, vertical: float) -> void:
	s.content_margin_left = horizontal
	s.content_margin_right = horizontal
	s.content_margin_top = vertical
	s.content_margin_bottom = vertical


## 3 px highlight outline around the focused control.
static func _focus() -> StyleBoxFlat:
	var s := _flat(Color.TRANSPARENT, 3, HIGHLIGHT)
	s.draw_center = false
	s.set_expand_margin_all(2)
	return s


static func _dropdown(t: Theme, accent: Color) -> void:
	var type := "SetupDropdown"
	t.set_type_variation(type, "OptionButton")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var bg := FIELD_BG
		if state.begins_with("hover") or state == "pressed":
			bg = FIELD_HOVER
		elif state == "disabled":
			bg = Color("#ECE5CE")
		var s := _flat(bg, 2)
		s.content_margin_left = 12
		s.content_margin_right = 8
		t.set_stylebox(state, type, s)
	t.set_stylebox("focus", type, _focus())
	t.set_icon("arrow", type, icon("dropdown_arrow", accent))
	t.set_constant("arrow_margin", type, 2)
	t.set_constant("h_separation", type, 10)
	t.set_constant("modulate_arrow", type, 0)
	t.set_font("font", type, font(600))
	t.set_font_size("font_size", type, 21)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, INK)
	t.set_color("font_disabled_color", type, Color(INK, 0.45))


## Lists of the dropdowns (PopupMenu children of the OptionButtons inherit the theme).
static func _popup(t: Theme, accent: Color) -> void:
	var panel := _flat(FIELD_BG, 2, BORDER, Vector2(4, 4), 0.35)
	_set_margins(panel, 2, 2)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("hover", "PopupMenu", _flat(HIGHLIGHT))
	t.set_font("font", "PopupMenu", font(600))
	t.set_font_size("font_size", "PopupMenu", 20)
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK, 0.4))
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_constant("h_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 14)
	t.set_icon("radio_checked", "PopupMenu", icon("list_selected", accent))
	t.set_icon("radio_unchecked", "PopupMenu", icon("list_unselected", accent))
	t.set_icon("radio_checked_disabled", "PopupMenu", icon("list_selected", accent))
	t.set_icon("radio_unchecked_disabled", "PopupMenu", icon("list_unselected", accent))


static func _checkbox(t: Theme, accent: Color) -> void:
	var type := "SetupCheckBox"
	t.set_type_variation(type, "CheckBox")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, type, StyleBoxEmpty.new())
	t.set_stylebox("focus", type, _focus())
	var on := icon("check_on", accent)
	var off := icon("check_off", accent)
	t.set_icon("checked", type, on)
	t.set_icon("unchecked", type, off)
	t.set_icon("checked_disabled", type, on)
	t.set_icon("unchecked_disabled", type, off)
	t.set_constant("h_separation", type, 10)
	t.set_font("font", type, font(700))
	t.set_font_size("font_size", type, 20)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, LABEL_INK)
	t.set_color("font_disabled_color", type, Color(LABEL_INK, 0.5))


## PLAY: vertical red gradient, 2 px dark border, white line on top, hard shadow (4, 4).
## The text is a PlayLabel inside the button (centred with the play icon), so only the box is here.
static func _red_button(t: Theme, accent: Color) -> void:
	var type := "RedButton"
	t.set_type_variation(type, "Button")
	var normal := _red_box(Color("#FF5A5A"), accent, Color("#5C0000"))
	var hover := _red_box(Color("#FF7A7A"), accent.lightened(0.18), Color("#7A0A0A"))
	var pressed := _red_box(Color("#FF5A5A"), accent, Color("#5C0000"))
	pressed.content_margin_top = 2
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, _red_box(Color("#B9B2A0"), Color("#8E877A"), Color("#4E4A42")))
	t.set_stylebox("focus", type, _focus())


static func _red_box(top: Color, mid: Color, bottom: Color) -> StyleBoxTexture:
	var svg := """<svg xmlns="http://www.w3.org/2000/svg" width="40" height="68" viewBox="0 0 40 68">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#%s"/><stop offset="0.42" stop-color="#%s"/><stop offset="1" stop-color="#%s"/>
</linearGradient></defs>
<rect x="4" y="4" width="36" height="64" fill="#000000" fill-opacity="0.38"/>
<rect width="36" height="64" fill="#2B0000"/>
<rect x="2" y="2" width="32" height="60" fill="url(#g)"/>
<rect x="2" y="2" width="32" height="2" fill="#FFFFFF" fill-opacity="0.35"/>
</svg>""" % [top.to_html(false), mid.to_html(false), bottom.to_html(false)]
	var s := StyleBoxTexture.new()
	s.texture = DPITexture.create_from_string(svg)
	s.texture_margin_left = 3
	s.texture_margin_top = 4
	s.texture_margin_right = 7
	s.texture_margin_bottom = 7
	s.expand_margin_right = 4
	s.expand_margin_bottom = 4
	return s


static func _footer_button(t: Theme, accent: Color) -> void:
	var type := "FooterButton"
	t.set_type_variation(type, "Button")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, type, StyleBoxEmpty.new())
	t.set_stylebox("focus", type, _focus())
	t.set_icon("icon", type, icon("pill", accent))
	t.set_constant("h_separation", type, 12)
	t.set_font("font", type, font(600))
	t.set_font_size("font_size", type, 30)
	t.set_color("font_color", type, Color.WHITE)
	t.set_color("font_focus_color", type, Color.WHITE)
	for c: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, type, HIGHLIGHT)


## Plain buttons (the exit confirmation): cream field with a dark border.
static func _plain_button(t: Theme) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := _flat(FIELD_HOVER if state != "normal" else FIELD_BG, 2)
		_set_margins(s, 18, 6)
		t.set_stylebox(state, "Button", s)
	t.set_stylebox("focus", "Button", _focus())
	t.set_font("font", "Button", font(700, 1))
	t.set_font_size("font_size", "Button", 21)
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", INK)


static func _dialog(t: Theme) -> void:
	var panel := _flat(PANEL_BG)
	_set_margins(panel, 20, 16)
	t.set_stylebox("panel", "AcceptDialog", panel)
	var border := _flat(PANEL_HEADER, 2, BORDER, Vector2(6, 6), 0.3)
	border.expand_margin_left = 2
	border.expand_margin_right = 2
	border.expand_margin_bottom = 2
	border.expand_margin_top = 38
	t.set_stylebox("embedded_border", "Window", border)
	t.set_stylebox("embedded_unfocused_border", "Window", border)
	t.set_constant("title_height", "Window", 36)
	t.set_font("title_font", "Window", font(700, 3))
	t.set_font_size("title_font_size", "Window", 20)
	t.set_color("title_color", "Window", INK)
