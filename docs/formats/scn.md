---
type: file-format
format: scn, animdefs
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: "GameData/Track/*.scn, GameData/Track/animdefs.txt"
count: "78 .scn, 1 animdefs.txt"
encoding: "text, latin1, CRLF"
status: partial
tool: "tools/track2gltf.py (start/cíl z _fstart.scn, vlastnosti objektů z animdefs.txt)"
updated: 2026-10-30
---

# Scény tratí (`.scn`) a vlastnosti objektů (`animdefs.txt`)

## Soubory `.scn`

Textové soubory s prvky (`<DRUH>_ELEMENT <verze>`). Čísla na řádku oddělují mezery a tabulátory.

| Soubor | Obsah |
| --- | --- |
| `<trať>_fstart.scn`, `_bstart.scn` | start a cíl pro jízdu dopředu / pozpátku (`TRIGGER_ELEMENT`, start je typ 2, cíl typ 1), startovní brána (`GEOM_ELEMENT`) |
| `<trať>_stNN.scn` | rozestavení pro úlohy (kužely, šipky, zdi, cíl); skidpad jich má 11 |
| `<trať>_cameras.scn` | kamery záznamu (`CAMERA_ELEMENT`) |
| `<trať>_audio.scn` | zdroje zvuku (`AUDIO_ELEMENT`) |

Výskyt ve všech 78 souborech: `TRIGGER_ELEMENT` 1 645, `AUDIO_ELEMENT` 1 538, `CAMERA_ELEMENT` 716, `GEOM_ELEMENT` 614.

### `GEOM_ELEMENT 5` (verze 4 má na řádku 4 jen jedno číslo za 1 1)

| Řádek | Obsah |
| --- | --- |
| 1 | poloha x y z (souřadnice originálu, levotočivé; pro glTF zrcadlit X) |
| 2 | báze 3 × 3 (9 čísel, řádky = osy) |
| 3 | `0 <značka> 0 0 -1 1 1 100 100 100`; značka je čtyřznakový kód jako celé číslo little-endian (1162760003 = 0x454E4F43 = „CONE“), poslední tři čísla jsou nejspíš měřítko v % |
| 4 | text `Geometry Element` |

Značka odkazuje na předlohu v CRP trati (`Base` 0x44, [crp.md](crp.md)) a na vlastnosti v `animdefs.txt`. Všechny `GEOM_ELEMENT`: CONE 291, ARW1 138, ENDW 61, ARW2 51, FNSH 46, ARW3 18, ARW4 9.

#### Umístění předlohy

Vrcholy předlohy se umístí maticí z řádků 1 a 2 tak, jak jsou: řádky báze jsou osy jako v matici `tr` rozmístěných objektů (zrcadlí se stejně, [crp.md](crp.md#převod-do-gltf)), poloha je počátek předlohy. Vlastní `tr` předlohy (pivot) se **nepoužije**. Ověřeno na cílové čáře (29. 10. 2026): s `tr` by dlaždice na farmlandu byly 3 m vedle silnice, bez ní pokryjí silnici širokou 2 × 6 m přesně.

**FNSH** (předloha `FinishLine`) je plochá dlaždice 6 × 6 m, 0,18 m nad počátkem, jedna textura šachovnice (`fini`, 2 × 2 pole po 3 m). V `_fstart.scn` ji mají všechny tratě se startem a cílem (farmland, alps, foothills, forest, industrial, coastal 2×, canyon 3×, castle 4×, autobahn 5×) vedle sebe přes silnici u cílového triggeru, pás začíná 0–3 m před čárou. Startovní čára vlastní předlohu nemá.

### `TRIGGER_ELEMENT 5`

Popis start/cíl je v [crp.md](crp.md#start-a-cíl--tratfstartscn-tratbstartscn): poloha, báze, parametry (typ první), dva krajní body čáry, řádek s nulami. V `_stNN.scn` mají triggery jiné typy (0 = ?), zatím nerozluštěno.

## `animdefs.txt`

Společné vlastnosti objektů podle značky. Bloky `SECTION:ANIM { … }` (a `SECTION:Audio`), uvnitř `klíč=hodnota;`, komentáře `//`, vnořené `SECTION:PIECE` popisují úlomky a animaci. Hlavička souboru vyjmenovává:

- `collideType`: `kCylinder`, `kBox`, `kSmackable` (sražitelný), `0` = bez kolize,
- `audioType`: `kAudSign`, `kAudMetalSign`, `kAudGlass`, `kAudWoodBox`, `kAudPylon`, `kAudTree`, `kAudBush`, `kAudCarBody`, `kAudWood`, `kAudSnow`, `kAudIce`, `kAudEarth`, `kAudRock`,
- dále `mass` (kg), `velocityFactor`, `radius`, `triggerable`, `drivethrough` / `drivethru`, `dynamicLight`, `ticksPerVertFrame`.

Příklady: SIGN sražitelná 80 kg, CONE 20 kg, CLMH 3 500 kg, auta provozu 1 500–9 999 kg, BUSH válec průjezdný, ARW1–4 bez kolize (spouštěče), FNSH bez kolize. Stejná značka může být v souboru dvakrát (GATE, WELD, FTRK); `track2gltf.py` bere první výskyt.

## Využití

- `tools/track2gltf.py` čte start/cíl z `_fstart.scn` (triggery do `_road.json`, `GEOM_ELEMENT` jako uzly skupiny `gates`) a pro rozmístěné objekty typ kolize, hmotnost a průjezdnost z `animdefs.txt` (`<trať>_objects.json`).
- Hra (`game/scripts/track_props.gd`): sražitelné objekty jsou dynamická tělesa s původní hmotností, zmrazená, dokud se nepřiblíží pohyblivé těleso; ostatní statické.
- Průjezdnost (`drivethrough=1`, jen značka `BUSH`) platí pro všechny články se značkou, nejen pro rozmístěné. `track2gltf.py` je dá do skupiny glTF `drivethrough`, které hra nedává kolizi (D-031, [crp.md](crp.md#články)). V originálu načítá trať funkce 0x004876e0, ta hned po `.crp` čte `animdefs.txt` (0x0047eba0). Jednu položku rozebírá 0x0047dcf0: `collideType` uloží jako typ kolize (`kSmackable` = 3, `kCylinder` = 1 …), `drivethru` i `drivethrough` jako stejný příznak definice značky (+0x14). Jak tento příznak používá kolize, zatím nerozluštěno.
- Zbývá: rozmístění předloh z `_stNN.scn` (úlohy), triggery úloh, kamery, zvuky, úlomky a animace (`SECTION:PIECE`).
