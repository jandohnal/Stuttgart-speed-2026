# Prototyp jízdy (fáze 2)

Godot 4.7 projekt pro milník fáze 2 (D-009): původní **356 A coupe 1.6** na původní trati **farmland** (Normandie), případně na **skidpadu**.

## Data originálu

Projekt nic z originální hry neobsahuje ani neimportuje. Auto a trať se načítají **za běhu** (`GLTFDocument`, `JSON`) ze složky `../decomposed` (nastavení projektu `stuttgart/data_root`). Do gitu tak nemůže nic z originálu přijít (D-008).

Potřebné soubory vytvoří nástroje z `tools/` (spouštět z kořene repozitáře):

```bash
python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json
```

```bash
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/farmland.crp decomposed/GameData/Track/farmland/farmland.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
```

## Spuštění

Otevřít `game/project.godot` v Godotu 4.7 a spustit (F5). Fyzika Jolt, 120 Hz, renderer Forward+ přes Metal.

Trať určuje nastavení projektu `stuttgart/track` (výchozí `farmland`), z příkazové řádky přepíše argument `-- --track=skidpad`. Argument `--slice=<n>` postaví auto na řez silnice n (kontrola konkrétního místa trati). Auto startuje na startovní čáře originálu (`start` v `_road.json`), na skidpadu na řezu 0.

| Klávesa | Akce |
| --- | --- |
| W / S, šipky | plyn / brzda (při stání brzda = zpátečka) |
| A / D, šipky | řízení |
| mezerník | ruční brzda |
| R | návrat na nejbližší řez silnice (`SimD`) |
| F2 | záznam telemetrie do `user://telemetry_*.csv` (cesta se vypíše do konzole) |
| F3 | asistent řízení zapnout / vypnout (stav je v HUD, výchozí zapnuto) |
| F11 | celá obrazovka / okno |

Samostatně spuštěná hra běží přes celou obrazovku (ne v náhledu editoru, ne v testech bez okna). Okno si vynutí argument `-- --windowed=1`. HUD se škáluje se zvětšením okna (základ 1152 × 648).

**Asistent řízení** omezuje natočení předních kol na 1,1× vrchol úhlu skluzu pneumatiky (356: 8,6°) kolem směru, kterým se přední náprava skutečně pohybuje. Plné řízení z klávesnice tak znamená „zatáčej, jak nejvíc to jde“, ne „natoč kola na doraz“ (přední kola by skluzovala a auto by nedotáčelo). Ve smyku zadní nápravy dovolí kontrovat. Pod 2 m/s nepůsobí, do 6 m/s se postupně zapíná. Vypnutý = jen mechanický doraz 30°.

## Struktura

| Soubor | Obsah |
| --- | --- |
| `scenes/main.tscn` | scéna: prostředí, slunce, auto, kamera, HUD |
| `scripts/original_assets.gd` | načítání glTF a JSON z `decomposed/` |
| `scripts/main.gd` | načtení trati (kolize z mesh skupin `road`, `terrain`, `objects`), auta, start na řezu silnice, ovládání, záznam telemetrie |
| `scripts/car.gd` | auto: raycast podvozek nad `RigidBody3D` (D-003), motor a automatická převodovka z `cars.json`, model pneumatik (skluz, rotace kol, setrvačnost motoru) |
| `scripts/follow_camera.gd`, `scripts/hud.gd` | kamera za autem, údaje o jízdě |

## Testy

Automatický jízdní test (bez okna): auto plným plynem jede po skidpadu (nebo po trati z `-- --track=farmland`) podle řezů `SimD`. Před zatáčkami brzdí (dávkovaně), jen když by v nich potřebovalo víc než 0,55 g (plánuje se zpomalením 0,45 g a výhledem asi 240 m), změří 0–100 km/h, rychlost po 40 s, brzdnou dráhu ze 100 km/h a vypíše kontakty karoserie.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn
```

Snímky obrazovky (otevře okno na pár sekund, PNG uloží do zadané složky):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/screenshot.tscn -- /tmp --track=farmland --slice=1284
```

Výsledky (Godot 4.7.2, Apple M1 Pro), reálná 356 A 1600 pro srovnání: 0–100 km/h asi 16 s, maximum 160 km/h.

| Datum | Model | Trať | 0–100 km/h | Po 40 s | Brzdění 100–0 |
| --- | --- | --- | --- | --- | --- |
| 15. 10. 2026 | zástupné pneumatiky | skidpad | 12,7 s | 139 km/h, 0,67 g | 49 m |
| 16. 10. 2026 | pneumatiky, asistent, brzdy 0,8 g, stabilizátor hlavně vpředu | skidpad | 15,9 s | 133 km/h, 0,67 g | 51,0 m |
| 16. 10. 2026 | totéž | farmland | 26,6 s (zatáčky) | 61 km/h, brzdění v zatáčkách 11,9 s, max 0,83 g | – |

Na farmlandu auto 40 s jede po silnici z kopce bez kolize. Odvážnější řidič (0,7 g / 0,6 g) se ale ve 37. s roztočí. Brzdí na horizontu v klesající zatáčce, kde auto nese jen asi 60 % váhy a zadní vnitřní kolo skoro nic (46–122 N), takže záď se zadním motorem uteče. Je to typická přetáčivost 356 při brzdění. Míru je potřeba porovnat s originálem.

## Stav a známá omezení

- Model pneumatik (`car.gd`): každé kolo má vlastní rotaci se setrvačností 1,2 kg·m², poháněná kola navíc setrvačnost motoru přes převod (0x058 / 1000 kg·m², hypotéza). Podélný skluz a úhel skluzu tvoří jeden normovaný vektor skluzu. Síla roste k vrcholu (délka 1), pak klesá na 75 % (smyk). Vrchol: skluz 0,12, úhel 3° + 0,08° × profilové číslo (356: 8,6°). Přilnavost μ = 0,444 + 0,353 × `.sim` 0x0F4 (356: 0,85, hypotéza), citlivost na zatížení 10 %, valivý odpor 0,015. Kola se integrují v 8 podkrocích. Brzdy působí momentem (max. 0,8 g jako bubnové brzdy, 58 % vpředu) a mohou kola zablokovat, motor brzdí 12 % maximálního momentu. Převodovka řadí nahoru, když vyšší stupeň dá na kolech víc síly. Ladění proti originálu přes Wine zbývá.
- Stabilizátory: vpředu 1,0 × tuhost pružiny, vzadu 0,3 (356 měla stabilizátor jen vpředu). Se stejně tuhým vzadu se zadní vnitřní kolo při brzdění v zatáčce odlehčovalo a auto se roztáčelo.
- Kamera je 6 m za autem a 2,4 m nad ním.
- Parametry z `.sim`: hmotnost, převody, stálý převod, křivka momentu, otáčky omezovače, rozměr pneumatik, rozdělení pohonu, poloha motoru (posun těžiště). Hypotézy: přilnavost (0x0F4), setrvačnost motoru (0x058). Odhadem: odpor vzduchu (Cd·A 0,6), tuhost pérování (vlastní frekvence 1,44 Hz), stabilizátory, dorazy.
- Vestavěné tlumení `RigidBody3D` je vypnuté (výchozích 0,1 bralo autu ~1 600 N), odpory se modelují explicitně.
- Kolizní box karoserie začíná 1,1 × poloměr kola nad zemí, aby při náklonu nedrhl o silnici; při prudkém brzdění se ještě krátce dotkne předkem.
- Bez kolizí s objekty knihovny, bez poškození, bez zvuku.
