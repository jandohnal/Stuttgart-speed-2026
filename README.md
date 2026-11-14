# Stuttgart Speed

Duchovní nástupce závodní hry *Need for Speed: Porsche 2000* (EA, 2000), postavený v enginu Godot a hratelný v prohlížeči.

Tento repozitář je **webová verze**. Hraje se na Cloudflare za heslem, jen pro autora a okruh kamarádů (D-041). Hra spouštěná přímo v Godotu na desktopu se vyvíjí v samostatném repozitáři (D-042).

Cílem není kopie originálu, ale zachování toho, co ho dělalo výjimečným: cesta automobilovou historií od 50. let po rok 2000, „sim-cade“ jízdní model, ve kterém se každé auto řídí jinak, otevřené silnice evropské krajiny a poškozování, které ovlivňuje jízdu i ekonomiku kariéry.

## Hlavní body

- **Engine:** Godot 4.7, fyzika Jolt, export pro web (WebAssembly, WebGL2, renderer Compatibility, D-040). Při vývoji v editoru renderer Forward+.
- **Jízdní model:** vlastní raycast podvozek, model pneumatik, přenos hmotnosti, nastavitelné asistenty.
- **Poškození:** zóny, deformace meshe, odpadávající díly a dopad na mechaniku.
- **Obsah:** repozitář obsahuje jen kód, nástroje a dokumentaci. Auta, tratě a zvuky si každý převede z vlastní kopie původní hry a hra je opravuje a doplňuje, bez hudby (D-009, D-039). Fiktivní auta a vlastní tratě jsou jen možnost pro samostatné vydání s vlastním obsahem (D-004, D-005).
- **Data originálu** se nešíří a existují jen lokálně. Leží ve složkách `sources/` (původní assety) a `decomposed/` (rozbalené), webové balíčky v `build/`. Nic z toho se nikdy necommituje, balíčky se nahrávají jen do privátního úložiště za heslem (D-041).

## Spuštění

Repozitář data původní hry neobsahuje a bez nich hra nepoběží. Potřebuješ složku s vlastní instalací původní hry, Python 3 a Godot 4.7.2 s webovými šablonami exportu. Převod dat popisuje [docs/setup.md](docs/setup.md), webový build, místní server a nahrání na Cloudflare [docs/web.md](docs/web.md). Ve zkratce:

```bash
python3 tools/build_data.py --install "/cesta/k/instalaci" --web
```

```bash
godot --headless --path game --import
```

```bash
godot --headless --path game --export-release "Web" ../build/web/index.html
```

```bash
python3 tools/serve_web.py build/web
```

Hra pak běží na `http://127.0.0.1:8000`. Při vývoji jde projekt `game/` spustit i přímo v Godotu (`godot --path game`).

## Stav

Fáze 2: hratelný prototyp se všemi auty a tratěmi originálu, závodem se soupeři, poškozením a zvukem, zbývá doladění proti originálu. Webová verze běží v Chromiu, Firefox a Safari nejsou vyzkoušené ([docs/web.md](docs/web.md#stav-9-11-2026)). Podrobnosti najdeš v [docs/plan.md](docs/plan.md).

## Struktura

| Cesta | Obsah |
| --- | --- |
| `docs/setup.md` | Převod dat a spuštění projektu na macOS, Windows a Linuxu |
| `docs/web.md` | Webový build, místní server a hosting na Cloudflare za heslem |
| `docs/analysis.md` | Analýza originálu, enginů, fyziky a poškození |
| `docs/decisions.md` | Přijatá rozhodnutí (ADR) |
| `docs/plan.md` | Fáze, milníky, rizika, úkoly |
| `docs/legal.md` | Právní mantinely: co smí a nesmí do repozitáře |
| `docs/data-inventory.md` | Inventura dat originální hry |
| `docs/water.md` | Voda v datech originálu po tratích (hladiny, vodopády, fontány, vodní částice) |
| `docs/formats/` | Popis rozluštěných formátů souborů |
| `ideas/` | Nápady k případnému budoucímu využití (zatím nepřijaté) |
| `data/inventory.yaml` | Strojově čitelná inventura dat |
| `game/` | Godot projekt hry ([popis a testy](game/README.md)) |
| `tools/` | Nástroje pro čtení dat z vlastní kopie hry a pro webový build ([přehled](tools/README.md)) |
| `tools/web_host/` | Worker s heslem pro Cloudflare a návod k ručnímu nahrání |
| `sources/` | Assety z originální hry, jen lokálně (v `.gitignore`) |
| `decomposed/` | Rozbalené a převedené assety, jen lokálně (v `.gitignore`) |
| `build/` | Webový export a balíčky dat, jen lokálně (v `.gitignore`) |

## Licence

Kód a dokumentace jsou pod licencí MIT, viz [LICENSE](LICENSE). Přiložené cizí assety mají vlastní licence uložené vedle nich: částice v `game/assets/particles/` jsou CC0 a písmo v `game/ui/fonts/` je pod SIL OFL 1.1. Licence se nevztahuje na data původní hry ani na názvy a značky jejich vlastníků.

## Právní upozornění

Projekt není nijak spojen s Electronic Arts ani s Porsche AG. Názvy her, vozů a značek patří jejich vlastníkům. Repozitář neobsahuje žádná data původní hry a neodkazuje na jejich stažení. Data vznikají jen lokálně ve složkách `sources/`, `decomposed/` a `build/`. Hostovaná webová verze je soukromá, za heslem a jen pro autora a okruh kamarádů, nejde o veřejné šíření. Nástroje v `tools/` pracují jen s daty z kopie hry, kterou uživatel legálně vlastní.
