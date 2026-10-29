# Stuttgart Speed

Duchovní nástupce závodní hry *Need for Speed: Porsche 2000* (EA, 2000), postavený v moderním enginu a hratelný nativně na Macu.

Cílem není kopie originálu, ale zachování toho, co ho dělalo výjimečným: cesta automobilovou historií od 50. let po rok 2000, „sim-cade“ jízdní model, ve kterém se každé auto řídí jinak, otevřené silnice evropské krajiny a poškozování, které ovlivňuje jízdu i ekonomiku kariéry.

## Hlavní body

- **Engine:** Godot 4.7, fyzika Jolt, renderer Metal (Apple Silicon).
- **Jízdní model:** vlastní raycast podvozek, model pneumatik, přenos hmotnosti, nastavitelné asistenty.
- **Poškození:** zóny, deformace meshe, odpadávající díly a dopad na mechaniku.
- **Obsah:** jen pro osobní použití, nešíří se. Původní auta, tratě a zvuky originálu, opravené a doplněné (i pomocí AI), bez hudby. Fiktivní auta a vlastní tratě jen pro případné veřejné vydání (D-004, D-005, D-009).
- **Data originálu** existují jen lokálně. Leží ve složkách `sources/` (původní assety) a `decomposed/` (rozbalené), které se nikdy necommitují.

## Stav

Fáze 1: analýza dat originálu a příprava nástrojů. Podrobnosti najdeš v [docs/plan.md](docs/plan.md).

## Struktura

| Cesta | Obsah |
| --- | --- |
| `docs/analysis.md` | Analýza originálu, enginů, fyziky a poškození |
| `docs/decisions.md` | Přijatá rozhodnutí (ADR) |
| `docs/plan.md` | Fáze, milníky, rizika, úkoly |
| `docs/legal.md` | Právní mantinely: co smí a nesmí do repozitáře |
| `docs/data-inventory.md` | Inventura dat originální hry |
| `docs/formats/` | Popis rozluštěných formátů souborů |
| `ideas/` | Nápady k případnému budoucímu využití (zatím nepřijaté) |
| `data/inventory.yaml` | Strojově čitelná inventura dat |
| `tools/` | Nástroje pro čtení dat z vlastní kopie hry |
| `sources/` | Assety z originální hry, jen lokálně (v `.gitignore`) |
| `decomposed/` | Rozbalené a převedené assety, jen lokálně (v `.gitignore`) |

## Právní upozornění

Projekt není nijak spojen s Electronic Arts ani s Porsche AG. Repozitář je privátní a neobsahuje žádná data původní hry. Ta existují jen lokálně ve složkách `sources/` a `decomposed/`. Nástroje v `tools/` pracují jen s daty z kopie hry, kterou uživatel legálně vlastní.
