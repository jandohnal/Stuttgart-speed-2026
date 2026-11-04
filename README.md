# Stuttgart Speed

Duchovní nástupce závodní hry *Need for Speed: Porsche 2000* (EA, 2000), postavený v moderním enginu a hratelný nativně na Macu, Windows i Linuxu.

Cílem není kopie originálu, ale zachování toho, co ho dělalo výjimečným: cesta automobilovou historií od 50. let po rok 2000, „sim-cade“ jízdní model, ve kterém se každé auto řídí jinak, otevřené silnice evropské krajiny a poškozování, které ovlivňuje jízdu i ekonomiku kariéry.

## Hlavní body

- **Engine:** Godot 4.7, fyzika Jolt, renderer Forward+ (vývoj na Metalu a Apple Silicon, jinde Direct3D 12 nebo Vulkan).
- **Jízdní model:** vlastní raycast podvozek, model pneumatik, přenos hmotnosti, nastavitelné asistenty.
- **Poškození:** zóny, deformace meshe, odpadávající díly a dopad na mechaniku.
- **Obsah:** jen pro osobní použití, nešíří se. Původní auta, tratě a zvuky originálu, opravené a doplněné (i pomocí AI), bez hudby. Fiktivní auta a vlastní tratě jen pro případné veřejné vydání (D-004, D-005, D-009).
- **Data originálu** existují jen lokálně. Leží ve složkách `sources/` (původní assety) a `decomposed/` (rozbalené), které se nikdy necommitují.

## Spuštění

Potřebuješ složku s instalací původní hry, Python 3 a Godot 4.7.2. Přesný postup pro macOS, Windows a Linux je v [docs/setup.md](docs/setup.md). Ve zkratce:

```bash
python3 tools/build_data.py --install "/cesta/k/instalaci"
```

```bash
godot --headless --path game --import
```

```bash
godot --path game
```

## Stav

Fáze 2: hratelný prototyp se všemi auty a tratěmi originálu, závodem se soupeři, poškozením a zvukem, zbývá doladění proti originálu. Podrobnosti najdeš v [docs/plan.md](docs/plan.md).

## Struktura

| Cesta | Obsah |
| --- | --- |
| `docs/setup.md` | Postup spuštění na macOS, Windows a Linuxu |
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
| `tools/` | Nástroje pro čtení dat z vlastní kopie hry ([přehled](tools/README.md)) |
| `sources/` | Assety z originální hry, jen lokálně (v `.gitignore`) |
| `decomposed/` | Rozbalené a převedené assety, jen lokálně (v `.gitignore`) |

## Právní upozornění

Projekt není nijak spojen s Electronic Arts ani s Porsche AG. Repozitář je privátní a neobsahuje žádná data původní hry. Ta existují jen lokálně ve složkách `sources/` a `decomposed/`. Nástroje v `tools/` pracují jen s daty z kopie hry, kterou uživatel legálně vlastní.
