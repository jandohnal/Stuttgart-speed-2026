# Stuttgart Speed – instrukce pro Claude Code

Duchovní nástupce NFS: Porsche 2000. Kontext: `README.md`, rozhodnutí: `docs/decisions.md`, plán a aktuální fáze: `docs/plan.md`.

## Složky s daty originální hry

| Složka | Obsah | Git |
| --- | --- | --- |
| `sources/` | Veškeré assety z originální hry v původní podobě (kopie instalace: `GameData/`, `FEData/` ...), případně licencované modely | ignorováno |
| `decomposed/` | Vše rozbalené a převedené ze `sources/` (JSON, PNG, glTF, WAV ...) | ignorováno |

- Obě složky jsou v `.gitignore` a **nikdy se necommitují**, i když je repozitář privátní. Existují jen lokálně.
- Nástroje čtou ze `sources/` a zapisují do `decomposed/`. Struktura `decomposed/` kopíruje strukturu `sources/` (např. `sources/GameData/Track/alps.crp` → `decomposed/GameData/Track/alps.bin`).
- Nic mimo tyto dvě složky nesmí obsahovat data originální hry.

## Pravidla

- Cílová auta jsou fiktivní (D-004) a tratě vlastní (D-005), bez názvů, log a tvarů vozů Porsche. Výjimka: prototyp (fáze 2) používá jedno původní auto na jedné původní trati z `decomposed/` (D-009). Tyto assety se nikdy necommitují.
- Při rozluštění dalšího formátu aktualizovat `docs/formats/<formát>.md` a `data/inventory.yaml`.
- Nová rozhodnutí zapisovat do `docs/decisions.md` jako D-xxx, hotové úkoly odškrtávat v `docs/plan.md`.
- Nápady, o kterých se zatím nerozhodlo, ukládat do `ideas/` jako samostatný soubor s hlavičkou `type: idea`, `id: IDEA-xxx`, `status`. Po přijetí nápadu z něj udělat rozhodnutí D-xxx a změnit `status` na `accepted`.
- Žádné placené doplňky (D-012). Jen vestavěné funkce Godotu, vlastní kód nebo bezplatné open-source doplňky s kompatibilní licencí.
- Dokumentace je česky, kód a komentáře v kódu anglicky.

## Nástroje

- Přehled všech nástrojů a sdílených modulů: `tools/README.md`.
- `python3 tools/archives.py refpack sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a.bin` – rozbalí EA RefPack (`archives.py bigf` rozbalí archiv `.viv`).
- `python3 tools/fsh2png.py sources decomposed` – všechny textury FSH do PNG (+ `index.json` pro každý archiv).
- `python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf` – model auta do glTF (+ atlasy textur).
- `python3 tools/ai_csv2json.py sources/GameData/Simulation/AI decomposed/GameData/Simulation/AI` – nastavení AI do JSON, ověřené proti `.bin`.
- `python3 tools/track2gltf.py sources/GameData/Track/farmland.crp decomposed/GameData/Track/farmland/farmland.gltf` – trať do glTF + data silnice (`_road.json`: řezy, úseky, start/cíl) + objekty kolem trati (`_objects.json`). Farmland = Normandie. Společný parser CRP je v `tools/crp.py`.
- `python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json` – fyzika aut do JSON.
- `python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds` – zvukové banky do WAV (+ `index.json`) a sady motorů pro hru (`engine.json`).

## Hra

- Godot projekt je v `game/` (popis a testy v `game/README.md`). Godot je zatím v `~/Downloads/Godot.app`. Jízdní test: `~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn`. Data originálu načítá **za běhu** z `../decomposed` (nastavení `stuttgart/data_root`), nikdy je neimportuje do `res://` ani nekopíruje do `game/`.

## Stack

- Godot 4.7 (4.7.2), Jolt, Metal (macOS, Apple Silicon). Rozhodnutí D-002 se potvrdí po prototypu jízdy.
- Nástroje pro data: Python 3, jen standardní knihovna, pokud to jde.
