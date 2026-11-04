---
type: guide
updated: 2026-11-04
---

# Spuštění hry na macOS, Windows a Linuxu

Předpoklad: máte složku s instalací původní hry *Need for Speed: Porsche 2000* (obsahuje `Porsche.exe`, `GameData` a `FEData`). Hra samotná v repozitáři žádná data originálu nemá, vytvoří si je z této složky (D-008, D-037).

## Co je potřeba

| Program | Verze | Poznámka |
| --- | --- | --- |
| [Git](https://git-scm.com/downloads) | libovolná | jen pro stažení repozitáře |
| [Python](https://www.python.org/downloads/) | 3.8 a novější (ověřené 3.9 a 3.12) | stačí standardní knihovna, nic se nedoinstalovává |
| [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) | 4.7.2, verze bez .NET | jeden soubor, neinstaluje se |

Soubory Godotu ke stažení: [macOS](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip), [Windows x64](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_win64.exe.zip), [Linux x64](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip), [Linux ARM64](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.arm64.zip).

Místo na disku: asi 280 MB `sources/`, 370 MB `decomposed/`, volitelně HDRI oblohy (4k asi 40 MB na trať a denní dobu). Grafická karta musí umět Metal (macOS), Direct3D 12 nebo Vulkan (Windows), Vulkan (Linux).

## Postup

Všechny příkazy se spouštějí z kořene repozitáře. Na Linuxu i macOS musí složka s instalací být dostupná jako obyčejná složka (zkopírovaná z Windows nebo připojený disk).

### macOS a Linux

```bash
git clone <adresa repozitáře> Stuttgart-speed
```

```bash
cd Stuttgart-speed
```

```bash
python3 tools/build_data.py --install "/cesta/k/instalaci"
```

```bash
python3 tools/fetch_hdri.py --res 2k
```

Na Linuxu dále podle souboru Godotu (`x86_64` nebo `arm64`; soubor je po rozbalení potřeba jednou označit jako spustitelný příkazem `chmod +x`):

```bash
./Godot_v4.7.2-stable_linux.x86_64 --headless --path game --import
```

```bash
./Godot_v4.7.2-stable_linux.x86_64 --path game
```

Na macOS (`Godot.app` rozbalený například do `~/Downloads`):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game --import
```

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game
```

### Windows (PowerShell)

```powershell
git clone <adresa repozitáře> Stuttgart-speed
cd Stuttgart-speed
py tools\build_data.py --install "C:\Program Files (x86)\EA GAMES\Need For Speed Porsche"
py tools\fetch_hdri.py --res 2k
C:\cesta\Godot_v4.7.2-stable_win64_console.exe --headless --path game --import
C:\cesta\Godot_v4.7.2-stable_win64.exe --path game
```

Cestu k instalaci upravte podle svého počítače. Python z python.org se spouští příkazem `py`, z Microsoft Store příkazem `python`. Soubor `_console.exe` je ve stejném zipu jako Godot a vypisuje do okna PowerShellu, proto se hodí na testy a hledání chyb.

### Co jednotlivé kroky dělají

1. **`build_data.py --install`** zkopíruje `GameData`, `FEData` a `Porsche.exe` do `sources/`, všechno převede do `decomposed/` (asi 2 minuty) a ověří, že vznikly soubory, které hra potřebuje. Při dalším spuštění bez `--install` použije už zkopírované `sources/`.
2. **`fetch_hdri.py`** stáhne oblohy z Poly Haven (CC0) do `assets/hdri/`. Je to volitelné: bez oblohy hra běží s procedurální oblohou a do logu napíše „HDRI sky … not found“. Volba `--track farmland` stáhne jen jednu trať, `--res` určuje rozlišení (`1k`, `2k`, `4k`, `8k`).
3. **`--import`** je potřeba jednou po stažení repozitáře a po přidání textur nebo tříd skriptů. Vytvoří `game/.godot/` (není v gitu). Stejně poslouží první otevření projektu v editoru Godotu.
4. **`--path game`** spustí hru přes celou obrazovku (s `-- --windowed=1` v okně). Ovládání je v [game/README.md](../game/README.md#spuštění).

Rychlá kontrola bez okna (na konci vypíše `all passed`), příkaz upravte podle systému:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/menu_test.tscn
```

## Když něco nefunguje

| Příznak | Příčina a řešení |
| --- | --- |
| `Parse Error: Identifier "OriginalAssets" not declared`, hra visí | Chybí krok `--import`. |
| V menu je položka neaktivní s poznámkou „chybí data“ | Převod neproběhl nebo neskončil dobře. Spusťte `build_data.py` znovu a podívejte se na řádky `FAIL` a `MISSING`. |
| `... is not the game's installation, missing: ...` | Složka v `--install` není kořen instalace. Musí v ní přímo ležet `Porsche.exe`, `GameData` a `FEData`. |
| `Missing .../decomposed/...` v logu Godotu | Hra hledá data v `../decomposed` vedle složky `game/` (nastavení projektu `stuttgart/data_root`, smí být i absolutní cesta). |
| Windows: `python3` otevře Microsoft Store | Použijte `py`. Ve Windows nespouštějte příkazy s přesměrováním `>`: PowerShell 5 by zapsal soubor v UTF-16. |
| Chcete přijít o uložená nastavení a časy | Soubory `settings.cfg`, `records.cfg` a `odometer.cfg` jsou ve složce `user://`: macOS `~/Library/Application Support/Godot/app_userdata/Stuttgart Speed/`, Windows `%APPDATA%\Godot\app_userdata\Stuttgart Speed\`, Linux `~/.local/share/godot/app_userdata/Stuttgart Speed/`. |

## Rozdíly mezi systémy

- **Zvětšení obrazu:** 3D obraz se kreslí nejvýš v 1 080 řádcích (D-030). Na macOS ho zvětšuje MetalFX, na Windows a Linuxu bilineární filtr, takže na displeji nad Full HD bude obraz měkčí. Nastavení projektu `stuttgart/render_height = 0` kreslí v nativním rozlišení.
- **Velikost písmen v názvech:** Linux ji rozlišuje. Převodníky i hra jsou na to vyzkoušené (převod a testy na svazku rozlišujícím velikost písmen dávají stejné výsledky).
- **Vylepšené textury:** autorova kopie `decomposed/` má u farmlandu a skidpadu navíc ručně vylepšené textury (`original/` s převedenými) a mapy `advanced/`. Nejsou v gitu a nástroje je nevytvoří, jinde se proto tyto tratě kreslí s původními texturami 128 px. Převod takto vylepšené textury nepřepisuje.
- **Export:** hra se spouští jen z projektu přes Godot, hotový spustitelný soubor zatím neexistuje (data čte z `../decomposed` vůči projektu, viz [IDEA o distribuci](../ideas/distribution-bring-your-own-data.md)).

## Co je ověřené (4. 11. 2026)

| Systém | Ověřeno | Neověřeno |
| --- | --- | --- |
| macOS (Apple Silicon, Python 3.9, Godot 4.7.2) | celý postup z čistého klonu, 24 testů bez okna, snímky obrazovky s oknem | |
| Linux ARM64 (kontejner Ubuntu 24.04, Python 3.12, Godot 4.7.2) | celý postup z čistého klonu, stejné výsledky převodu i testů bez okna | okno, grafika a zvuk (kontejner nemá GPU ani displej) |
| Linux x64 | | nespuštěno; stejný kód, jiný soubor Godotu |
| Windows | názvy souborů (žádné znaky ani jména zakázaná ve Windows), kódování (převod s jiným než UTF-8 výchozím kódováním dává stejný výstup) | nespuštěno, na ověření je potřeba počítač s Windows |
