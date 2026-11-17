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

- `tools/pack_web.py` vytvoří v `build/web/data/` balíčky a `manifest.json` s jejich velikostmi. Na každé auto `car-<model>.zip`, na trať `track-<trať>.zip`, na sadu motoru `engine-<sada>.zip`, zvuky nárazů a vodopádu `sfx.zip` a společná data `core.zip`. Balíček trati obsahuje i její denní a noční oblohu z `assets/hdri/` zmenšenou na 1024 × 512 px (D-043). Balíček trati obsahuje i textury oblohy originálu `Sky/<Trať>/` podle `<trať>_sky.json` (výchozí obloha, D-045). Bez stažených HDRI (`tools/fetch_hdri.py`) se volba HDRI nahradí oblohou originálu. V `core.zip` je i index `GameData/Track/tracks.json` s příznakem noci každé trati (D-050), který menu potřebuje před stažením balíčku trati. Jsou v něm i naše ikony, písma a textury částic, protože je hra čte jako soubory a export obsahuje jen jejich importovanou podobu.
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
| Obloha | výchozí obloha a horizont originálu (`Sky/<Trať>/` v balíčku trati, D-045), s volbou HDRI trati zmenšené na 1024 × 512 px (`sky/<trať>_<day\|night>.hdr`, asi 1,5 MB) |
| Auta | bez odrazu okolí, soupeři bez efektů kol |
| Částice | jiskry a kapky bez stop, bez trávy a listí od kol, mlha bez atraktorů a turbulence |
| Tratě | bez map `advanced/` |
| Světla tratě | 4 místo 12 |
| Geometrie tratě | statické díly sloučené podle materiálu do buněk 500 m (`track_batcher.gd`) |
| Fyzika | nejvýš 4 kroky na snímek, při nízkém FPS se hra zpomalí |
| Okno | celá obrazovka jen klávesou F11, bez tlačítka Konec a bez záznamu telemetrie |

### Nízká kvalita (D-043)

Pro slabší počítače je v menu zaškrtávátko LOW QUALITY. Zapnout ho jde i adresou `…/?quality=low` (vypnout `?quality=high`), třeba v odkazu pro kamaráda, a volba se uloží. Kreslí jako originál, bez stínů počítaných za běhu (D-048): trať je neosvětlená, protože světlo a stín mají její textury, pod autem je tmavá skvrna a v noci před autem světelná skvrna světlometů. Vypne glow, SSAO, úpravu barev, padající listí z korun stromů a světelné obtisky na autech, 3D obraz kreslí nejvýš 720 řádků, dohled zkrátí na 1 500 m (s hustší mlhou bez aerial perspective). V noci nesvítí lampy trati ani reflektory soupeřů, protože neosvětlená trať světla ignoruje. Odrazy a okolní světlo aut z oblohy mají malou mapu, která se obnovuje po částech (D-049). Počet soupeřů nízká kvalita nemění, nastavuje se posuvníkem OPPONENTS. Materiály trati jsou bez detailu a parallaxu a 3D rozlišení se samo snižuje až na 360 řádků, dokud hra nejede aspoň 50 FPS. HUD vlevo nahoře ukazuje FPS a počet volání kreslení (`draws`), pod tím kvalitu, 3D rozlišení / velikost plátna a skutečnou grafickou kartu, takže je vidět, co pomohlo. Když FPS roste se zmenšením okna, omezuje grafická karta počtem pixelů, ne procesor. Notebook se dvěma grafikami: ve Windows *Nastavení > Systém > Obrazovka > Grafika*, pro Chrome zvolit *Vysoký výkon*.

Ladit se dá bez nahrání na Cloudflare: export a místní server jako v postupu výše. Godot ve webovém exportu vyžaduje zabezpečené připojení (HTTPS nebo `localhost`), jinak ohlásí chybějící HTTPS. Pro jiný počítač ve stejné síti proto spustit server s HTTPS:

```bash
python3 tools/serve_web.py build/web --bind 0.0.0.0 --https
```

Server vypíše adresy, na testovacím počítači otevřít `https://<IP tohoto počítače>:8000/?quality=low`. Certifikát je podepsaný sám sebou (vytvoří ho příkaz `openssl` do `build/web-cert/` a obnoví ho, když se změní adresa), takže prohlížeč jednou varuje. V Chrome *Rozšířené > Pokračovat*, v Safari *Zobrazit podrobnosti > navštívit tento web*. Vlastní certifikát jde zadat přes `--cert` a `--key`. macOS se při prvním spuštění může zeptat, zda povolit příchozí připojení pro Python. Server nemá heslo, proto jen v domácí síti a po testu ho zastavit. Pokud hra na slabém počítači běží pod 10 FPS i s nízkou kvalitou, stojí za to v Chrome otevřít `chrome://gpu`. „Software only“ u WebGL znamená, že prohlížeč nepoužívá grafickou kartu.

## Stav (9. 11. 2026)

Ověřeno v Chromiu: menu, stažení balíčků, závod se 3 soupeři na Monaku a Farmlandu, HUD, trvalé nastavení, čistý zvuk motoru. Monako běželo kolem 58 FPS v malém okně. Na Farmlandu je omezením počet volání kreslení ve WebGL, ne rozlišení ani počet trojúhelníků. Sloučení tratě snížilo špičku z asi 6000 na 1700 volání a jízda s AI v debug buildu běžela 44 až 94 FPS (M1 Pro, Chromium, malé okno). Čísla z panelu prohlížeče na pozadí neplatí, prohlížeč v něm omezuje snímkování. Firefox a Safari nejsou vyzkoušené.
