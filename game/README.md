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

Trať určuje nastavení projektu `stuttgart/track` (výchozí `farmland`), z příkazové řádky přepíše argument `-- --track=skidpad`. Auto startuje na startovní čáře originálu (`start` v `_road.json`), na skidpadu na řezu 0.

| Klávesa | Akce |
| --- | --- |
| W / S, šipky | plyn / brzda (při stání brzda = zpátečka) |
| A / D, šipky | řízení |
| mezerník | ruční brzda |
| R | návrat na nejbližší řez silnice (`SimD`) |
| F2 | záznam telemetrie do `user://telemetry_*.csv` (cesta se vypíše do konzole) |

## Struktura

| Soubor | Obsah |
| --- | --- |
| `scenes/main.tscn` | scéna: prostředí, slunce, auto, kamera, HUD |
| `scripts/original_assets.gd` | načítání glTF a JSON z `decomposed/` |
| `scripts/main.gd` | načtení trati (kolize z mesh skupin `road`, `terrain`, `objects`), auta, start na řezu silnice, ovládání, záznam telemetrie |
| `scripts/car.gd` | auto: raycast podvozek nad `RigidBody3D` (D-003), motor a automatická převodovka z `cars.json`, **zástupný model pneumatik** |
| `scripts/follow_camera.gd`, `scripts/hud.gd` | kamera za autem, údaje o jízdě |

## Testy

Automatický jízdní test (bez okna): auto plným plynem jede po skidpadu (nebo po trati z `-- --track=farmland`) podle řezů `SimD`, změří 0–100 km/h, rychlost po 40 s, brzdnou dráhu ze 100 km/h a vypíše kontakty karoserie.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn
```

Snímky obrazovky (otevře okno na pár sekund, PNG uloží do zadané složky):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/screenshot.tscn -- /tmp
```

Výsledek 15. 10. 2026 (Godot 4.7.2, Apple M1 Pro): auto stojí na všech 4 kolech (zatížení 8 125 N ≈ hmotnost), 0–100 km/h 12,7 s, po 40 s na kruhu 139 km/h při 0,67 g, brzdná dráha 100–0 km/h 49 m. Reálná 356 A 1600: 0–100 asi 16 s, maximum 160 km/h – zrychlení je zatím příliš dobré (zástupné pneumatiky, bez valivého odporu a setrvačnosti motoru).

## Stav a známá omezení

- Model pneumatik je zástupný (úhel skluzu s nasycením, kruh tření). Nahrazení skutečným modelem a ladění proti originálu přes Wine je hlavní úkol fáze 2.
- Parametry z `.sim`: hmotnost, převody, stálý převod, křivka momentu, otáčky omezovače, rozměr pneumatik, rozdělení pohonu, poloha motoru (posun těžiště). Odhadem: přilnavost, odpor vzduchu (Cd·A 0,6), tuhost pérování (vlastní frekvence 1,44 Hz), stabilizátory, dorazy.
- Vestavěné tlumení `RigidBody3D` je vypnuté (výchozích 0,1 bralo autu ~1 600 N), odpory se modelují explicitně.
- Kolizní box karoserie začíná 1,1 × poloměr kola nad zemí, aby při náklonu nedrhl o silnici; při prudkém brzdění se ještě krátce dotkne předkem.
- Bez kolizí s objekty knihovny, bez poškození, bez zvuku.

Farmland 16. 10. 2026 (`-- --track=farmland`): auto ze startu sjede za 40 s asi 1,2 km z kopce, drží se 1–3 m od osy silnice (jednou 9,5 m), 0–100 km/h 13,2 s. Při 130 km/h karoserie několikrát dosedne na silnici (horizonty) a jednou se dotkne terénu. Na skutečné trati se tedy ukazuje, že podvozek a pneumatiky ještě potřebují práci.
