---
type: guide
---

# Hra v prohlížeči

Webová verze je hlavní výstup tohoto repozitáře (D-042), desktopová hra se vyvíjí v samostatném repozitáři. Je to export Godotu pro web (D-040). Data originálu jsou v balíčcích, které si každý vytvoří ze své kopie hry a **nikdy se nezveřejňují** (D-039).

## Co je potřeba

- Hotový `decomposed/` ([setup.md](setup.md)).
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

## Soukromý hosting za heslem (D-041)

Jen pro autora a kamarády na testování, ne pro veřejné šíření. Běží na Cloudflare: soubory jsou v privátním bucketu R2 (10 GB a přenos zdarma), každý požadavek prochází Workerem s heslem. Potřebuješ Node.js a účet Cloudflare, aktivace R2 může chtít platební kartu.

Jednorázově se přihlásit, vytvořit bucket a nahrát Worker:

```bash
npx --yes wrangler@4 login
```

```bash
npx --yes wrangler@4 r2 bucket create stuttgart-speed-web
```

```bash
npx --yes wrangler@4 deploy --config tools/web_host/wrangler.toml
```

Nastavit heslo (zadává se ručně, do repozitáře nepatří; bez něj Worker odmítá všechny):

```bash
npx --yes wrangler@4 secret put GAME_PASSWORD --config tools/web_host/wrangler.toml
```

Nahrát build, i po každé nové verzi (nezměněné soubory přeskočí):

```bash
python3 tools/deploy_web.py build/web
```

Hra pak běží na adrese `https://stuttgart-speed-web.<účet>.workers.dev`, kterou vypíše `deploy`. Prohlížeč se zeptá na jméno (může být libovolné) a heslo. U bucketu nikdy nezapínat veřejný přístup (`r2.dev` ani vlastní doménu), obešlo by to heslo.

Lokální zkouška bez účtu: `deploy_web.py --local --persist-to <složka>` naplní simulátor a `wrangler dev --persist-to <složka> --var GAME_PASSWORD:<heslo>` ho spustí.

Ruční nahrání přes dashboard, bez Node.js a bez napojení na repozitář:

```bash
python3 tools/package_web.py build/web
```

Vytvoří `build/cloudflare/` se soubory pro bucket (`bucket/`), kódem Workeru a návodem `NAVOD.md` (zdroj je `tools/web_host/NAVOD.md`). Do bucketu se nahrají soubory z `bucket/` a obsah `bucket/data/` do složky `data`, Worker se vloží v editoru, binding R2 se jmenuje `BUCKET` a tajná proměnná `GAME_PASSWORD`.

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
