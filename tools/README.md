# Nástroje pro data originálu

Python 3, jen standardní knihovna. Čtou ze `sources/`, zapisují do `decomposed/` se stejnou strukturou složek (CLAUDE.md, D-008). Spouštějí se z kořene repozitáře: `python3 tools/<nástroj>.py …`. Formáty jsou popsané v `docs/formats/`.

## Převodníky (spouštějí se)

| Nástroj | Vstup → výstup | Formát |
| --- | --- | --- |
| `archives.py` | `refpack <in> <out>`: rozbalí EA RefPack (`.crp` …); `bigf <in.viv> <složka>`: rozbalí archiv BIGF | [crp.md](../docs/formats/crp.md), [bnk.md](../docs/formats/bnk.md) |
| `fsh2png.py` | textury FSH (SHPI) → PNG + `index.json`; jeden soubor nebo celý strom | [fsh.md](../docs/formats/fsh.md) |
| `crp2gltf.py` | model auta `.crp` → glTF (+ atlasy textur, morph targety poškození `dz0`–`dz9`, oddělené levé a pravé díly) + `<auto>_damage.json` (zóny, odpojitelné díly) | [crp.md](../docs/formats/crp.md) |
| `track2gltf.py` | trať `.crp` → glTF (skupiny road, terrain, vegetation, objects, props) + `<trať>_road.json` (řezy SimD, úseky, start a cíl) + `<trať>_objects.json` (rozmístěné objekty, kolize a hmotnost) | [crp.md](../docs/formats/crp.md), [scn.md](../docs/formats/scn.md) |
| `snd2wav.py` | zvukové banky `.viv` / `.bnk` → WAV + `index.json`; u sad motoru `sd*.viv` i `engine.json` (smyčky pod plynem a bez plynu, otáčky) | [bnk.md](../docs/formats/bnk.md) |
| `sim_dump.py` | fyzika aut `.sim` → JSON na standardní výstup (`cars.json`) | [sim.md](../docs/formats/sim.md) |
| `ai_csv2json.py` | nastavení AI `.csv` → JSON, ověřené proti `.bin` | [ai-csv.md](../docs/formats/ai-csv.md) |

## Sdílené moduly (importují se)

| Modul | Obsah | Používají |
| --- | --- | --- |
| `common.py` | `find_file` (soubor ve složce bez ohledu na velikost písmen), `source_files` (soubory s příponou ve stromu a jejich relativní cesta pro zrcadlení do `decomposed/`) | `fsh2png`, `crp2gltf`, `track2gltf`, `snd2wav`, `ai_csv2json`, `scn` |
| `archives.py` | `decompress` (RefPack), `read_bigf` (BIGF) | `crp`, `fsh2png`, `snd2wav` |
| `crp.py` | kontejner CRP (`parse_crp`, `find`, `entry_text`, `base_info`), díly a geometrie (`article_mesh` se seznamem, pruhem i čtyřúhelníky, `article_matrix`), převod souřadnic `to_gltf`, zápis glTF s morph targety `write_gltf` | `crp2gltf`, `track2gltf` |
| `scn.py` | scény tratí `.scn` (`read_triggers`, `start_finish`) a vlastnosti objektů `animdefs.txt` (`read_animdefs`) | `track2gltf` |
| `fsh2png.py` | dekódování FSH a zápis PNG (`parse`, `decode_image`, `write_png`) | `crp2gltf` (atlasy aut), `track2gltf` (textury tratí) |

## Pořadí pro hru

```bash
python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
python3 tools/track2gltf.py sources/GameData/Track/farmland.crp decomposed/GameData/Track/farmland/farmland.gltf
python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds
```
