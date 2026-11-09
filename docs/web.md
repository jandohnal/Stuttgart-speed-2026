---
type: guide
---

# Hra v prohlížeči

Export Godotu pro web (D-040). Data originálu jsou v balíčcích, které si každý vytvoří ze své kopie hry a **nikdy se nezveřejňují** (D-039).

## Co je potřeba

- Hotový `decomposed/` (`docs/setup.md`).
- Godot 4.7.2 a webové šablony exportu ve verzi 4.7.2 (v editoru *Editor > Manage Export Templates*).
- Python 3 a prohlížeč s WebGL2 (ověřeno v Chromiu).

## Postup

```bash
python3 tools/pack_web.py decomposed build/web/data
```

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game --export-release "Web" ../build/web/index.html
```

```bash
python3 tools/serve_web.py build/web
```

Pak otevřít `http://127.0.0.1:8000`. Server poslouchá jen na tomto počítači. Balíčky jdou vytvořit i rovnou s převodem dat: `python3 tools/build_data.py --web`.

## Jak to funguje

- `tools/pack_web.py` vytvoří v `build/web/data/` balíčky a `manifest.json` s jejich velikostmi. Na každé auto `car-<model>.zip`, na trať `track-<trať>.zip`, na sadu motoru `engine-<sada>.zip`, zvuky nárazů a vodopádu `sfx.zip` a společná data `core.zip`. V `core.zip` jsou i naše ikony, písma a textury částic, protože je hra čte jako soubory a export obsahuje jen jejich importovanou podobu.
- Autoload `DataPacks` balíček stáhne a připojí do `res://decomposed`. Kód načítání je stejný jako na desktopu. Na desktopu `DataPacks` nedělá nic.
- `scenes/loading.tscn` je první scéna webového buildu a ukazuje postup stahování před menu a před každým závodem.
- Balíčky jsou v paměti prohlížeče (`/tmp`), při další návštěvě je vrátí HTTP cache. Stažené tratě nad 512 MB se uvolňují od nejdéle nepoužité.
- Nastavení a rekordy jsou v `user://` (IndexedDB prohlížeče) a přežijí znovunačtení stránky.

## Rozdíly proti desktopu

Řídí je `GameSettings.is_web_profile()`, přepínače `.web` v `project.godot` a preset v `game/export_presets.cfg`.

| Oblast | Web |
| --- | --- |
| Renderer | Compatibility (WebGL2), bez SSAO a decalů |
| Stíny | atlas 4096, měkkost 2, slunce ve 2 pásmech do 200 m, světlomety bez stínů |
| Obloha | procedurální, HDRI se nestahují |
| Auta | bez odrazu okolí, soupeři bez efektů kol |
| Částice | jiskry a kapky bez stop, bez trávy a listí od kol, mlha bez atraktorů a turbulence |
| Tratě | bez map `advanced/` |
| Světla tratě | 4 místo 12 |
| Geometrie tratě | statické díly sloučené podle materiálu do buněk 500 m (`track_batcher.gd`) |
| Fyzika | nejvýš 4 kroky na snímek, při nízkém FPS se hra zpomalí |
| Okno | celá obrazovka jen klávesou F11, bez tlačítka Konec a bez záznamu telemetrie |

## Stav (9. 11. 2026)

Ověřeno v Chromiu: menu, stažení balíčků, závod se 3 soupeři na Monaku a Farmlandu, HUD, trvalé nastavení, čistý zvuk motoru. Monako běželo kolem 58 FPS v malém okně. Na Farmlandu je omezením počet volání kreslení ve WebGL, ne rozlišení ani počet trojúhelníků. Sloučení tratě snížilo špičku z asi 6000 na 1700 volání a jízda s AI v debug buildu běžela 44 až 94 FPS (M1 Pro, Chromium, malé okno). Čísla z panelu prohlížeče na pozadí neplatí, prohlížeč v něm omezuje snímkování. Firefox a Safari nejsou vyzkoušené.
