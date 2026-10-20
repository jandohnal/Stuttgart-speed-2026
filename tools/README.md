# Nástroje pro data originálu

Python 3, jen standardní knihovna. Čtou ze `sources/`, zapisují do `decomposed/` se stejnou strukturou složek (CLAUDE.md, D-008). Spouštějí se z kořene repozitáře: `python3 tools/<nástroj>.py …`. Formáty jsou popsané v `docs/formats/`.

## Převodníky (spouštějí se)

| Nástroj | Vstup → výstup | Formát |
| --- | --- | --- |
| `archives.py` | `refpack <in> <out>`: rozbalí EA RefPack (`.crp` …); `bigf <in.viv> <složka>`: rozbalí archiv BIGF | [crp.md](../docs/formats/crp.md), [bnk.md](../docs/formats/bnk.md) |
| `fsh2png.py` | textury FSH (SHPI) → PNG + `index.json`; jeden soubor nebo celý strom | [fsh.md](../docs/formats/fsh.md) |
| `crp2gltf.py` | model auta `.crp` → glTF (+ atlasy textur, morph targety poškození `dz0`–`dz9`, oddělené levé a pravé díly) + `<auto>_damage.json` (zóny, odpojitelné díly) + `<auto>_styles.json` (styly z `.tpg`: díly k odebrání a atlasy každé varianty, D-022); vynechá zdvojené díly nižší úrovně detailu, vnitřní panely víek otočí od vnějších | [crp.md](../docs/formats/crp.md#styly-varianty-modelu) |
| `track2gltf.py` | trať `.crp` → glTF (skupiny road, terrain, vegetation, objects, props) + `<trať>_road.json` (řezy SimD, úseky, start a cíl) + `<trať>_objects.json` (rozmístěné objekty, kolize a hmotnost) + `<trať>_lights.json` (záře `ef`: ve světě, na objektech, na předlohách; zdroje částic) | [crp.md](../docs/formats/crp.md), [scn.md](../docs/formats/scn.md) |
| `snd2wav.py` | zvukové banky `.viv` / `.bnk` → WAV + `index.json`; u sad motoru `sd*.viv` i `engine.json` (smyčky pod plynem a bez plynu, otáčky) | [bnk.md](../docs/formats/bnk.md) |
| `car_colors.py` | databáze aut menu `FEData/Data/nfs5.car` → `car_colors.json` (palety barev laku a interiéru podle modelu, tovární barva a styl modelu podle varianty) | [car.md](../docs/formats/car.md) |
| `parts.py` | katalog dílů `FEData/Data/nfs5.prt` + seznamy dílů aut z `nfs5.car` + konstanty vzorců a tabulka pneumatik z `Porsche.exe` → `parts.json` (díly, sady Stock / Sport, pneumatiky pro každou variantu z `cars.json`); `--report` vypíše tabulku Sport | [prt.md](../docs/formats/prt.md) |
| `sim_dump.py` | fyzika aut `.sim` → JSON na standardní výstup (`cars.json`) | [sim.md](../docs/formats/sim.md) |
| `mesh_check.py` | hotový glTF → jeden řádek na model (OK / WARN / FAIL) + `<model>_check.json`: trojúhelníky obrácené proti normálám, zahozené při převodu, u aut pro každý styl překryvy dílů v jedné rovině a délka otevřených hran, u tratí plochy terénu mířící dolů a díry v silnici (paprsky přes řezy SimD) | [model-check.md](../docs/model-check.md) |
| `flare.py` | záře světel `GameData/Render/flare.dat` → `flares.json` (vrstvy, barvy, velikosti, blikání) | [flare.md](../docs/formats/flare.md) |
| `ai_csv2json.py` | nastavení AI `.csv` → JSON, ověřené proti `.bin` | [ai-csv.md](../docs/formats/ai-csv.md) |

## Sdílené moduly (importují se)

| Modul | Obsah | Používají |
| --- | --- | --- |
| `car_colors.py` | `model_styles` (styl každé varianty modelu z `nfs5.car`) | `crp2gltf` (výchozí styl) |
| `common.py` | `find_file` (soubor ve složce bez ohledu na velikost písmen), `source_files` (soubory s příponou ve stromu a jejich relativní cesta pro zrcadlení do `decomposed/`) | `fsh2png`, `crp2gltf`, `track2gltf`, `snd2wav`, `ai_csv2json`, `scn` |
| `archives.py` | `decompress` (RefPack), `read_bigf` (BIGF) | `crp`, `fsh2png`, `snd2wav` |
| `crp.py` | kontejner CRP (`parse_crp`, `find`, `entry_text`, `base_info`, efekty `article_effects`), díly a geometrie (`article_mesh` se seznamem, pruhem i čtyřúhelníky, otočením trojúhelníků podle normál nebo nahoru a statistikou `STATS`, `article_matrix`), převod souřadnic `to_gltf`, zápis glTF s morph targety `write_gltf` | `crp2gltf`, `track2gltf`, `mesh_check` (`cross`) |
| `scn.py` | scény tratí `.scn` (`read_triggers`, `start_finish`) a vlastnosti objektů `animdefs.txt` (`read_animdefs`) | `track2gltf` |
| `fsh2png.py` | dekódování FSH a zápis PNG (`parse`, `decode_image`, `write_png`) | `crp2gltf` (atlasy aut), `track2gltf` (textury tratí) |

## Pořadí pro hru

```bash
python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
python3 tools/track2gltf.py sources/GameData/Track/farmland.crp decomposed/GameData/Track/farmland/farmland.gltf
python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds
python3 tools/car_colors.py sources/FEData/Data/nfs5.car decomposed/FEData/Data/car_colors.json
python3 tools/parts.py sources/FEData decomposed/FEData/Data/parts.json
python3 tools/flare.py sources/GameData/Render/flare.dat decomposed/GameData/Render/flares.json
```

Všechna auta a tratě najednou, potom kontrola:

```bash
for f in sources/GameData/CarModel/*.crp; do c=$(basename $f .crp); python3 tools/crp2gltf.py $f decomposed/GameData/CarModel/$c/$c.gltf; done
for t in skidpad farmland monaco1 monaco2 monaco3 monaco4 monaco5 alps autobahn canyon castle coastal foothills forest industrial; do python3 tools/track2gltf.py sources/GameData/Track/$t.crp decomposed/GameData/Track/$t/$t.gltf; done
python3 tools/mesh_check.py decomposed/GameData/CarModel decomposed/GameData/Track
```
