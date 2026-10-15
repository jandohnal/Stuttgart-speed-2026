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

- Ve hře žádné názvy, loga ani tvary vozů Porsche. Auta jsou fiktivní (D-004), tratě vlastní (D-005). Data originálu slouží jako reference.
- Při rozluštění dalšího formátu aktualizovat `docs/formats/<formát>.md` a `data/inventory.yaml`.
- Nová rozhodnutí zapisovat do `docs/decisions.md` jako D-xxx, hotové úkoly odškrtávat v `docs/plan.md`.
- Dokumentace je česky, kód a komentáře v kódu anglicky.

## Nástroje

- `python3 tools/refpack.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a.bin` – rozbalí EA RefPack.
- `python3 tools/fsh2png.py sources decomposed` – všechny textury FSH do PNG (+ `index.json` pro každý archiv).
- `python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf` – model auta do glTF (+ atlasy textur).
- `python3 tools/ai_csv2json.py sources/GameData/Simulation/AI decomposed/GameData/Simulation/AI` – nastavení AI do JSON, ověřené proti `.bin`.
- `python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf` – trať do glTF + data silnice (`_road.json`). Společný parser CRP je v `tools/crp.py`.
- `python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json` – fyzika aut do JSON.

## Stack

- Godot 4.6, Jolt, Metal (macOS, Apple Silicon). Rozhodnutí D-002 se potvrdí po prototypu jízdy.
- Nástroje pro data: Python 3, jen standardní knihovna, pokud to jde.
