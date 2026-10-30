# Stuttgart Racing — Main Menu (Godot 4 implementation spec)

This spec describes the main menu of **Stuttgart Racing**, a racing game remake. It is written so it can be implemented in **Godot 4.x** (GDScript, Control nodes) without the original HTML mockup.

The design reference is a 1920×1080 mockup. All coordinates below are in that space.

---

## 1. Project & display settings

| Setting | Value |
|---|---|
| `display/window/size/viewport_width` | `1920` |
| `display/window/size/viewport_height` | `1080` |
| `display/window/stretch/mode` | `canvas_items` |
| `display/window/stretch/aspect` | `keep` (letterbox on other ratios) |
| Default theme | `res://ui/theme/stuttgart_theme.tres` (see §4) |

Root scene: `res://ui/main_menu/MainMenu.tscn`, root node `Control` with **Full Rect** anchors, script `MainMenu.gd`.

---

## 2. Visual language

### Colours

| Token | Hex | Use |
|---|---|---|
| `ground` | `#E2D9BB` | Screen background (cream / khaki) |
| `ring_line` | `#6E5C32` @ 16% alpha | Concentric background rings |
| `spoke_line` | `#6E5C32` @ 12% alpha | Radial background spokes |
| `top_shade` | `#161512` | Dark gradient at the top (opaque → transparent over 290 px) |
| `accent` | `#C8101A` | Signal red: buttons, dropdown arrows, checked boxes, pills |
| `accent_light` | `#FF5A5A` | Top of the red button gradient |
| `accent_dark` | `#5C0000` | Bottom of the red button gradient |
| `button_border` | `#2B0000` | Border of red buttons |
| `panel_bg` | `#F6F1E0` @ 97% | Race setup panel |
| `panel_header` | `#D6CEB0` | Panel header strip |
| `ink` | `#1D1B16` | Main dark text / borders (`#1E1C18` for borders) |
| `label_ink` | `#2A2620` | Field labels in the panel |
| `field_bg` | `#FFFAF0` | Dropdown field, list, unchecked box |
| `divider` | `#BFB594` | Divider line in the panel |
| `highlight` | `#F2B705` | Hover on list items, focus outline, footer hover text |
| `footer_bg` | `#0E0D0B` | Bottom bar |
| `footer_border` | `#3A362E` | Bottom bar top border |
| `footer_muted` | `#8A826C` | "MAIN MENU" text in bottom bar |
| `logo_light` | `#E9E2C8` | "STUTTGART" in the logo |

Make `accent` a single exported variable / theme constant. The design allows swapping it for `#B3001E`, `#D4380D` or `#1F5AA6`.

### Typography

Font: **Saira Condensed** (Google Fonts, SIL Open Font License — free to ship in a game). Import these static TTFs into `res://ui/fonts/`:

- `SairaCondensed-SemiBold.ttf` (600)
- `SairaCondensed-Bold.ttf` (700)
- `SairaCondensed-ExtraBold.ttf` (800)

Wrap the 800 weight in a `FontVariation` with `variation_transform` skew ≈ `0.2` for the italic "RACING" logo text (or ship the ExtraBold Italic file).

| Role | Weight | Size | Colour | Extra |
|---|---|---|---|---|
| Screen title "main menu" | 800 | 64 | white | lowercase; shadow `#000` 60%, offset (2, 3) |
| Logo "STUTTGART" | 600 | 22 | `logo_light` | letter spacing ≈ 9 px (use `FontVariation.spacing_glyph = 9`) |
| Logo "RACING" | 800 italic | 50 | `accent` | shadow black, offset (2, 2) |
| Panel header | 700 | 20 | `ink` | letter spacing 3 |
| Field labels | 700 | 21 | `label_ink` | uppercase, letter spacing 1 |
| Dropdown value / items | 600 | 21 / 20 | `ink` | |
| Checkbox labels | 700 | 20 | `label_ink` | uppercase |
| PLAY button | 800 | 40 | white | letter spacing 6, shadow `#3A0000` offset (2, 2) |
| Footer buttons | 600 | 30 | white | lowercase |
| Footer "MAIN MENU" | 700 | 26 | `footer_muted` | letter spacing 6 |
| Porthole caption | 600 | 23 | `#F4EEDB` | centred |

### Style rules

- Hard, flat drop shadows (no blur), offset down-right: 4–6 px, black 30–45% alpha.
- No rounded corners, except the footer "pill" icons and the circular porthole.
- 2 px dark borders on panels and fields.

---

## 3. Layout & scene tree

```
MainMenu (Control, full rect)            MainMenu.gd
├─ Background (ColorRect, full rect)     shader: background.gdshader (§5.1)
├─ TopShade (TextureRect)                0,0 → 1920×300, GradientTexture2D vertical
├─ Logo (VBoxContainer)                  pos (44, 22), separation -6
│  ├─ LogoTop (Label)                    "STUTTGART"
│  └─ LogoBottom (Label)                 "RACING"
├─ Title (Label)                         pos (330, 8)  "main menu"
├─ Porthole (Control)                    §3.2
│  ├─ Bezel (Panel)                      pos (548, 288) size 1124×1124, circle
│  ├─ Photo (TextureRect)                pos (566, 306) size 1088×1088, circle mask shader
│  ├─ PhotoOverlay (ColorRect)           same rect, shader: scanlines + vignette + grid lines
│  ├─ SideText (Label)                   "STUTTGART RACING", vertical, inside photo
│  └─ Caption (PanelContainer)           pos (760, 906) size 700×~50
│     └─ CaptionLabel (Label)
├─ RaceSetup (PanelContainer)            §3.3, pos (40, ~208) width 453
│  └─ VBox
│     ├─ Header (Label in PanelContainer) "RACE SETUP"
│     └─ Body (MarginContainer 16/14/16/16)
│        └─ VBoxContainer (separation 8)
│           ├─ RowCarModel   (HBox: Label + OptionButton)
│           ├─ RowCarProfile (HBox: Label + OptionButton)
│           ├─ RowCarColor   (HBox: Label + OptionButton with colour icons)
│           ├─ RowTires      (HBox: Label + OptionButton)
│           ├─ RowTrack      (HBox: Label + OptionButton)
│           ├─ Divider (ColorRect 2 px, margin 6 top/bottom)
│           ├─ Options (GridContainer, columns 2, h_sep 16, v_sep 6)
│           │  └─ 7 × CheckBox
│           └─ PlayButton (Button, height 64, top margin 8)
└─ Footer (PanelContainer)               pos (0, 1010) size 1920×70
   └─ HBox (margins 40 left/right)
      ├─ FooterTitle (Label)             "MAIN MENU"
      ├─ Spacer (Control, expand)
      └─ HBox (separation 48)
         ├─ CreditsButton (Button)       "credits..."
         └─ ExitButton (Button)          "exit"
```

Draw order (back → front): Background, TopShade, Porthole, Logo/Title, RaceSetup, Footer. The porthole extends below the footer; the footer covers it.

### 3.1 Background

- Solid `ground` plus a shader-drawn pattern of concentric rings and radial spokes (see §5.1).
- Ring centre: **(1060, 820)**. Ring period **73 px**, line width **3 px**, colour `ring_line`.
- Spoke centre: **(1172, 829)**. One spoke every **12°**, spoke width **0.5°**, colour `spoke_line`.
- `TopShade`: vertical gradient from `#161512` (alpha 1.0) at 0 px → alpha 0.88 at 110 px → alpha 0 at 290 px.

### 3.2 Porthole (central archive photo)

- **Bezel**: circle, centre (1110, 850), radius 562. Radial fill `#3A3732` (centre) → `#1A1916` (edge). Outer ring: 12 px `#FFFBEB` at 45% alpha, plus a soft shadow (≈ 70 px blur, black 45%, offset y 24).
- **Photo**: circle, centre (1110, 850), radius 544. A black-and-white archive photo of Stuttgart (1950s–60s, at least 1600×1600 px), `STRETCH_KEEP_ASPECT_COVERED`, masked to a circle by a shader.
- Until the photo exists, use a radial gradient placeholder: `#A49E91` (50% x, 35% y) → `#6F6A60` (55%) → `#2C2A26` (edge).
- Apply a desaturate + slight sepia (≈ 0.15) + contrast (≈ 1.15) in the photo shader so any photo matches the look.
- **Overlay** (inside the photo circle):
  - vertical scanlines: white @ 5%, 1 px line every 4 px;
  - three vertical guide lines, 2 px, white @ 28%, at photo-local x = 218, 464, 566;
  - one horizontal guide line at photo-local y = 70.
- **SideText**: "STUTTGART RACING", 700 / 22 px, white @ 55%, letter spacing 6. Rotated 90° (reads top → bottom), photo-local position (136, 210).
- **Caption**: dark strip `#0C0B0A` @ 78%, 3 px top border in `accent`, padding 10/20, text centred.
  - Default text: the selected car model (e.g. "Roadster 1600").
  - On Credits: "Credits — the people behind Stuttgart Racing".
  - On Play: "Loading… {track} · {model}, {color} · {day|night}".

Only the top part of the porthole is visible (the screen ends at y = 1080, the footer starts at y = 1010).

### 3.3 Race setup panel

- Width **453 px**, left x = **40**, **vertically centred** in the area above the footer (centre y = 505). In Godot, set `position.y = 505 - size.y / 2` after layout, e.g. in `_ready()` with `await get_tree().process_frame`. The panel height is ≈ 594 px.
- Panel style: `panel_bg`, 2 px border `#1E1C18`, hard shadow (6, 6) black 30%.
- Header strip: height 36, `panel_header` background, 2 px bottom border, centred text "RACE SETUP".
- Each dropdown row: height 42, label on the left, field **270 px** wide on the right (`size_flags_horizontal = SHRINK_END`).
- The checkbox grid has 2 columns × 4 rows, each item 38 px tall. The 7th item is alone in the last row.
- PLAY button: full panel width, height 64, play-triangle icon left of the text, gap 14.

### 3.4 Footer

- Background `footer_bg`, 2 px top border `footer_border`, height 70, horizontal padding 40.
- Left: "MAIN MENU" label. Right: `credits...` and `exit`, 48 px apart.
- Each footer button is flat (no background): white text with a **pill icon** on the left.
  - Pill: 40×24, `accent` fill, 2 px white border, radius 12. Gap between icon and text: 12.
  - Hover: text colour `highlight`.

---

## 4. Theme (`stuttgart_theme.tres`)

Build one `Theme` resource. Use **type variations** so one theme serves every control.

### `RedButton` (base type `Button`) — used by PLAY

- `normal`: `StyleBoxTexture` with a vertical `GradientTexture2D`.
  - Stops: `#FF5A5A` @ 0.0, `accent` @ 0.42, `#5C0000` @ 1.0.
  - Draw the 2 px `#2B0000` border with `texture_margin_*` / an outer `StyleBoxFlat`, or nest a `Panel`.
  - Hard shadow: `StyleBoxFlat.shadow_offset = (4, 4)`, `shadow_size = 0`, black 38%. Use a separate shadow panel if you use StyleBoxTexture.
  - Inner highlight: 2 px line `#FFFFFF` @ 35% at the top.
- `hover`: same gradient, ~18% brighter (e.g. stops `#FF7A7A`, `#E8303A`, `#7A0A0A`).
- `pressed`: same as normal, offset 2 px down (`content_margin_top + 2`).
- `focus`: `StyleBoxFlat`, no fill, 3 px border `highlight`, `expand_margin_* = 2`.
- `font_color` white, `font_outline_size` 0. Shadow via `font_shadow_color = #3A0000`, `shadow_offset_x/y = 2`.

### `SetupDropdown` (base type `OptionButton`)

- `normal` / `hover` / `pressed`: `StyleBoxFlat`.
  - bg `field_bg`, 2 px border `#1E1C18`, no radius, `content_margin_left = 12`.
  - hover bg `#F2E7BF`.
- `arrow` icon: a 38×38 texture with an `accent` square, 2 px dark left border and a white chevron (stroke 2.5).
  - Simplest: author `ui/icons/dropdown_arrow.svg` and set `arrow_margin = 0`.
- `font_color` `ink`, font 600 / 21.
- Popup (`PopupMenu` theme items inside the same theme):
  - `panel`: bg `field_bg`, 2 px border `#1E1C18`, shadow (4, 4) black 35%.
  - `hover`: `StyleBoxFlat` bg `highlight`. `font_hover_color` `ink`.
  - Selected item: show it with the `accent` background and white text. PopupMenu has no "selected bg" item, so use the `radio_checked` icon or override per item via `set_item_icon`. Alternatively, build a custom popup (`PanelContainer` + `VBoxContainer` of `Button`s) for an exact match.
  - Item height 38, font 600 / 20, `h_separation 10`.

### `SetupCheckBox` (base type `CheckBox`)

- `checked` icon: 28×28, `accent` fill, 2 px `#1E1C18` border, white check mark (stroke 2.8).
- `unchecked` icon: 28×28, `field_bg` fill, 2 px `#1E1C18` border.
- `checked_disabled` / `unchecked_disabled`: same icons at 50% alpha.
- `h_separation` 10. Font 700 / 20, `font_color` `label_ink`.
- All `StyleBox`es empty except `focus` (3 px `highlight` outline).

### `FooterButton` (base type `Button`)

- All `StyleBox`es `StyleBoxEmpty`, except `focus` (3 px `highlight` outline).
- `icon`: `ui/icons/pill.svg` (40×24 red pill with white border). `h_separation` 12.
- `font_color` white, `font_hover_color` `highlight`, `font_pressed_color` `highlight`. Font 600 / 30.

### `SetupLabel` / `PanelHeader` / `FooterTitle` (base type `Label`)

Font sizes and colours as in the typography table.

---

## 5. Shaders

### 5.1 `background.gdshader` (on `Background` ColorRect)

```glsl
shader_type canvas_item;

uniform vec4 ground : source_color = vec4(0.886, 0.851, 0.733, 1.0); // #E2D9BB
uniform vec4 line_col : source_color = vec4(0.431, 0.361, 0.196, 1.0); // #6E5C32
uniform vec2 screen_size = vec2(1920.0, 1080.0);
uniform vec2 ring_center = vec2(1060.0, 820.0);
uniform float ring_period = 73.0;
uniform float ring_width = 3.0;
uniform float ring_alpha = 0.16;
uniform vec2 spoke_center = vec2(1172.0, 829.0);
uniform float spoke_step_deg = 12.0;
uniform float spoke_width_deg = 0.5;
uniform float spoke_alpha = 0.12;

void fragment() {
    vec2 p = UV * screen_size;

    float d = length(p - ring_center);
    float ring = step(ring_period - ring_width, mod(d, ring_period));

    vec2 s = p - spoke_center;
    float ang = degrees(atan(s.x, -s.y)) + 180.0;
    float spoke = step(mod(ang, spoke_step_deg), spoke_width_deg);

    vec3 c = ground.rgb;
    c = mix(c, line_col.rgb, ring * ring_alpha);
    c = mix(c, line_col.rgb, spoke * spoke_alpha);
    COLOR = vec4(c, 1.0);
}
```

### 5.2 `porthole_photo.gdshader` (on `Photo` TextureRect)

- Circle mask: `COLOR.a *= 1.0 - smoothstep(0.495, 0.5, length(UV - 0.5));`
- Look: grayscale → `mix` with sepia 0.15 → contrast 1.15 around 0.5.
- Overlay (or a separate ColorRect): scanlines, vignette and the 2 px guide lines from §3.2. Use the same circle mask.

---

## 6. Data

Put these in `MainMenu.gd`, or better in a `RaceConfig` autoload / `Resource`.

```gdscript
const CAR_MODELS   := ["Roadster 1600", "Coupé 2.0", "Neckar 2.7 RS", "Solitude Turbo 3.3"]
const CAR_PROFILES := ["Street", "Track", "Rally", "Custom 1"]
const CAR_COLORS := {
    "Signal red":   Color("#C8101A"),
    "Ivory":        Color("#EFE6CF"),
    "Silver grey":  Color("#A7A9AB"),
    "Racing green": Color("#1F4D34"),
    "Night blue":   Color("#1D2C4F"),
    "Black":        Color("#141414"),
}
const TIRES  := ["Street", "Sport", "Racing slick", "Wet", "Snow"]
const TRACKS := ["Solitude ring", "Schwarzwald pass", "Neckar valley", "Killesberg city circuit", "Works test track"]
```

| Field | Default |
|---|---|
| Car model | Roadster 1600 |
| Car profile | Street |
| Car color | Signal red |
| Tires | Sport |
| Track | Solitude ring |

| Checkbox (label) | Key | Default |
|---|---|---|
| NIGHT RACE (unchecked = day) | `night` | off |
| DRIVING ASSIST | `assist` | on |
| ABS | `abs` | on |
| TRACTION CONTROL | `traction` | on |
| SOUND | `sound` | on |
| DIAGNOSTICS | `diag` | off |
| OPPONENTS | `opponents` | on |

Car colour dropdown: each item gets a 20×20 swatch icon (2 px `#1E1C18` border). Generate it at runtime:

```gdscript
func _make_swatch(c: Color) -> ImageTexture:
    var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
    img.fill(Color("#1E1C18"))
    img.fill_rect(Rect2i(2, 2, 16, 16), c)
    return ImageTexture.create_from_image(img)
```

---

## 7. Behaviour

```gdscript
extends Control

signal race_requested(config: Dictionary)
signal credits_requested
signal exit_requested

@onready var caption: Label = %CaptionLabel
# ... %CarModel, %CarProfile, %CarColor, %Tires, %Track (OptionButton)
# ... %Night, %Assist, %Abs, %Traction, %Sound, %Diag, %Opponents (CheckBox)

func _ready() -> void:
    _fill_options()
    _apply_defaults()
    %CarModel.item_selected.connect(func(_i): _update_caption())
    %PlayButton.pressed.connect(_on_play)
    %CreditsButton.pressed.connect(_on_credits)
    %ExitButton.pressed.connect(func(): exit_requested.emit())
    %CarModel.grab_focus()
    _update_caption()

func get_config() -> Dictionary:
    return {
        "model":   %CarModel.get_item_text(%CarModel.selected),
        "profile": %CarProfile.get_item_text(%CarProfile.selected),
        "color":   %CarColor.get_item_text(%CarColor.selected),
        "tires":   %Tires.get_item_text(%Tires.selected),
        "track":   %Track.get_item_text(%Track.selected),
        "night":   %Night.button_pressed,
        "assist":  %Assist.button_pressed,
        "abs":     %Abs.button_pressed,
        "traction":  %Traction.button_pressed,
        "sound":     %Sound.button_pressed,
        "diagnostics": %Diag.button_pressed,
        "opponents":   %Opponents.button_pressed,
    }

func _update_caption() -> void:
    caption.text = %CarModel.get_item_text(%CarModel.selected)

func _on_credits() -> void:
    caption.text = "Credits — the people behind Stuttgart Racing"
    credits_requested.emit()

func _on_play() -> void:
    var c := get_config()
    caption.text = "Loading… %s · %s, %s · %s" % [c.track, c.model, c.color, "night" if c.night else "day"]
    race_requested.emit(c)
```

Rules:

- Selecting any dropdown item or toggling a checkbox resets the caption to the default (the selected car model).
- Opening a dropdown closes any other open one. This is automatic with `OptionButton`.
- Persist the last config with `ConfigFile` at `user://race_setup.cfg` and restore it in `_ready()`.
- The `exit` button should ask for confirmation (`ConfirmationDialog` in the same style), then call `get_tree().quit()`.

### Animations / feedback

| Element | Effect |
|---|---|
| Red buttons (PLAY) | Hover: brightness ×1.15 over 0.12 s (`modulate` tween to `Color(1.15, 1.15, 1.15)`). Press: move 2 px down. |
| Footer buttons | Hover: text → `highlight`. |
| List items | Hover: background `highlight`, text `ink`. |
| Checkbox | Hover: unchecked box fill `#F2E7BF`. |
| Caption | Optional: fade text in over 0.15 s on change. |

---

## 8. Input & accessibility

- The menu must be fully playable with **keyboard and gamepad**.
- Set `focus_neighbor_*` so the D-pad moves top → bottom through: 5 dropdowns → checkbox grid (2 columns) → PLAY → credits → exit.
- Wrap from exit back to the first dropdown.
- `ui_accept` opens/confirms a dropdown and toggles a checkbox. `ui_cancel` closes an open popup.
- Every focusable control shows the 3 px `highlight` (`#F2B705`) focus outline.
- Minimum hit size is 38 px tall (already satisfied).
- Text contrast: dark ink on cream and white on red both pass WCAG AA.
- Do not reduce the label sizes below the typography table.

---

## 9. Assets checklist

| Asset | Path | Notes |
|---|---|---|
| Saira Condensed 600 / 700 / 800 | `res://ui/fonts/` | OFL licence, include `OFL.txt` |
| Dropdown arrow | `res://ui/icons/dropdown_arrow.svg` | 38×38, red square + white chevron |
| Checkbox on / off | `res://ui/icons/check_on.svg`, `check_off.svg` | 28×28 |
| Play triangle | `res://ui/icons/play.svg` | 26×26, white |
| Footer pill | `res://ui/icons/pill.svg` | 40×24 |
| Archive photo | `res://ui/photos/porthole_*.jpg` | B/W Stuttgart, 1950s–60s, ≥1600 px square. **Only use photos with a clear licence** (public domain or CC with attribution in credits). |
| Background shader | `res://ui/shaders/background.gdshader` | §5.1 |
| Photo shader | `res://ui/shaders/porthole_photo.gdshader` | §5.2 |

The menu must not use Porsche names, logos or original Need for Speed artwork.

---

## 10. Acceptance criteria

- [ ] At 1920×1080 the screen matches the layout in §3 within ±4 px.
- [ ] Other aspect ratios letterbox, without stretching.
- [ ] All 5 dropdowns show the listed options and defaults. The colour dropdown shows swatches.
- [ ] All 7 checkboxes toggle and default as listed.
- [ ] PLAY emits `race_requested` with the full config and updates the caption.
- [ ] Credits and exit work. Exit asks for confirmation.
- [ ] The menu is fully usable with keyboard only and with gamepad only. The focus outline is always visible.
- [ ] The last setup is restored after restarting the game.
