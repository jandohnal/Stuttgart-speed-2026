---
type: idea
id: IDEA-015
title: "Noční tratě originálu (Monaco 1–5, Industrial) v noci už ve výchozím stavu"
status: accepted        # idea | accepted | rejected | done
created: 2026-11-17
related: [D-019, D-043, D-044, D-045, D-048, D-050, D-051, IDEA-009]
tags: [night, sky, lighting, low-quality, monaco, industrial]
---

# Noční tratě originálu ve výchozím stavu v noci

Originál jezdí Monaco 1–5 a Industrial vždy v noci, ostatní tratě vždy ve dne. Volbu denní doby nemá. Hra teď noc zapíná jen volbou NIGHT RACE. Ta je určená pro umělou noc na denní trati: ztmaví trať, vymění HDRI a rozsvítí autům světla. Cíl je, aby se noční tratě originálu v noci spouštěly samy, s nastavením podle dat originálu. Předpokládá se profil LOW QUALITY (D-048) a obloha originálu (D-045).

## Co říkají data originálu

### Příznak noci

Noc určuje trať. Render metody (`RMth`) v `.crp` Monaka 1–5 a Industrial obsahují vrstvy `Headlights` (typy 0x8002, 0x8003, 0x8011). Když je hra vytvoří, nastaví globální příznak noci (`0x628A28`). `tools/track2gltf.py` příznak zapisuje do `<trať>_lights.json` jako `night` ([crp.md](../docs/formats/crp.md#render-metody-rmth-a-noc)).

### Světla aut

- **Světlomety na trati.** V noci hra načte `GameData/Render/night.psh`. Je to archiv `SHPP` s jedinou texturou `nght`: 128 × 128, 8 bitů s paletou, kulatá světelná skvrna s měkkým okrajem. Funkce na 0x4526C0 ji každý snímek promítá z polohy a natočení auta hráče na trať šedou barvou 0xFF808080 (50 % bílé). Konstanty projekce jsou 1,28, 3,62, −4,8 a −17. Jejich význam (rozměr kuželu, posun před auto) zatím rozluštěný není. Projekci kreslí vrstvy `Headlights` render metod trati, proto je mají jen noční tratě.
- **Druhá projekce.** Hra vybere nejbližší auto s příznakem (bit 2 na +0xECC) a promítá jeho světlo v barvách 0xFFFF0000 a 0xFF0000FF (červená, modrá). Pravděpodobně jde o majáky policie.
- **Auta samotná** nemají záře `ef`. Klíč `night=1` v `.tpg` mají jen textury `gnl*` a `gnm*` v `interior.fsh` u 6 aut (964, 996, boxster, gt3, f996, fboxster), denní protějšky jsou `gal*` a `gam*`. Jsou to nejspíš podsvícené budíky v kokpitu. Kokpit se teď neověřuje, takže pro tento krok nejsou potřeba.
- **Světelné obtisky** `.map` (D-044): Monaco `tint` 1,80, `ambient` 0,30, `lightdecal` 1,11; Industrial 1,27, 0,73 a 1,17. Hypotéza: `ambient` je okolní světlo aut. Neověřeno.

### Obloha a prstenec horizontu

Pro trať se berou soubory podle jejího jména (`Monaco1.*` až `Monaco5.*`, `Industrial.*`). Monaco1–5 mají stejné `.txt` a `.fsh`, liší se jen `.bin` (prolnutí oblastí podle řezu). `Monaco.*` bez čísla hra pro tratě nepoužívá.

| | Monaco 1–5 | Industrial |
| --- | --- | --- |
| Úroveň HIGH | `basic`, mapa `st1a`, mrak `flat` (bílá plocha), měřítko 0,5, bez větru | `multinormal`, mapy `st1a` + `sc1a`, mraky `cm1a` + `cm2a`, vítr 7 a 3 (270°, 220°), `move ratio` 400 |
| Úroveň MEDIUM (low quality) | stejná jako HIGH | jedna vrstva: `st1a` s mrakem `cm1a`, měřítko 2, vítr 2 (40°) |
| Blokuje slunce | ne | ano |
| Barva oblohy `st1a` | tmavá šedozelená (průměr RGB 50, 57, 51), uprostřed tmavší | žlutohnědá (145, 116, 44): oranžová světelná mlha nad městem; mraky `cm*` béžové |
| Kopule | šířka 1 500, výška 125, měřítko 0,1 | šířka 500, výška 56,6, měřítko 1,5 |
| Prolnutí oblastí A → B | podle řezu (0 až 1) | celou dobu 0 (jen oblast A) |
| Prstenec `horz` | 4 × 1 dlaždice: noční město na skalnatém kopci se světly a moře s odlesky; vlevo od kopce obloha průhledná | 4 × 2 dlaždice: noční průmyslové panorama se světly a jejich odrazy, spodek průhledný |
| Další textury | `st1b`, `sc1a`, `cc1a`, `fct1` (nepoužité úrovní) | `hor0` (stejné panorama, spodek neprůhledný hnědý), `sc2a`, `cc1b`, `ltmp` 7 × 7 |
| Barvy horizontu `hzcl` | 16 × 2, posun sloupce 5 | 16 × 2, posun sloupce 5 |

Industrial má navíc `industrial_lightning.bin` (blesky, formát nerozluštěný, [sky.md](../docs/formats/sky.md)).

### Trať

Textury obou tratí jsou namalované v noci. Monaco má rozsvícená okna `win*` a neony `neo*`. Industrial má tmavé zdi, žlutá rozsvícená okna `lwin` a lampy `lyte` a `iolp`. Originál trať neosvětluje (D-048), jen na ni přičítá projekci světlometů.

## Jak to dělá hra teď (low quality, obloha originálu)

- `time_of_day` je jen z NIGHT RACE v menu, z `--time` nebo z `stuttgart/time` (výchozí `day`). Monaco tak běží ve dne a `OriginalSky.DAY_SCALE` jeho noční oblohu zesvětlí trojnásobně.
- Noc (NIGHT RACE) dělá umělou noc:
  - trať se ztmaví na `LOW_TRACK_LIGHT` 0,4, na Monaku a Industrial tedy podruhé,
  - `SkyLighting.NIGHT` nastaví měsíc 0,1, expozici a modrou mlhu,
  - `CarLights` rozsvítí lampy aut, `CarBeam` přidá vlastní skvrnu před autem hráče,
  - `TrackLights` zapne lampy a rozsvícená okna, tabulky (`LAMPS`, `LIT_TEXTURES`) ale má jen pro Monaco.
- `OriginalSky.is_night_sky` pozná noční oblohu podle jasu `st1a`. Industrial za noční nepovažuje, a v noci by jeho oblohu ztlumil na 0,06 (skoro černá).

## Kroky

Kroky 1–4 jsou hotové (D-050, 17. 11. 2026), kroky 5 a 6 také (D-051). V menu je NIGHT RACE u nočních tratí zaškrtnuté a neaktivní.

1. **Příznak trati ve hře.** Načíst `night` z `<trať>_lights.json` (soubor se už načítá v `main.gd` a je ve webovém balíčku). Když klíč chybí (starý `decomposed/`), platí den a do logu jde výzva přegenerovat trať (`track2gltf.py`).
2. **Výchozí denní doba.** Na trati s `night` je denní doba vždy noc, bez ohledu na NIGHT RACE, `--time` a `stuttgart/time`. Originál volbu nemá. Ve hře rozlišit dva druhy noci, třeba `night_source`: `original` (noc trati) a `race` (NIGHT RACE na denní trati). Kód pak na noční trati nedělá umělé ztmavení. V menu u Monaka a Industrial zobrazit NIGHT RACE zaškrtnuté a neaktivní, nebo volbu skrýt (rozhodnout).
3. **Obloha.** `is_night_sky` nahradit příznakem trati, aby se Industrial neztlumil. Při noci originálu kreslit oblohu i prstenec s energií 1 (`DAY_ENERGY`, bez `NIGHT_SCALE`) a barvu mlhy brát z `OriginalSky.horizon_color` (Industrial oranžovohnědá, Monaco tmavá), ne pevnou modrou z `SkyLighting.NIGHT`. Úroveň MEDIUM už vybírá `pick_level`. Ověřit, zda má low quality u Industrial použít `hor0` místo `horz`. Originál bere `hor<n>` přednostně pro úroveň výkonu *n* a nejdřív je potřeba zjistit, která úroveň odpovídá MEDIUM.
4. **Jas trati.** Při noci originálu v low quality kreslit trať s jasem 1,0, protože textury jsou malované v noci. Ztmavení 0,4 nechat jen pro NIGHT RACE na denní trati. Ověřit snímkem proti originálu.
5. **Světla aut.** Při noci originálu zapnout `CarLights` (světlomety, zadní světla) jako teď. `CarBeam`:
   - místo vlastní textury použít `nght` z `night.psh` (převést do PNG; SHPP s paletou zatím `fsh2png.py` nepřevádí, doplnit převod a `docs/formats`),
   - přičítat ji barvou 0x808080,
   - dorozluštit projekci v exe (funkce na 0x4526C0, konstanty 1,28 / 3,62 / −4,8 / −17) a podle ní nastavit délku, šířku a posun skvrny.

   Originál promítá jen světla auta hráče (a majáky, krok 9), to `CarBeam` už dělá.
6. **Lampy a okna Industrial.** Doplnit `industrial` do `TrackLights.LIT_TEXTURES` (`lwin`, `lyte`, `iolp`, případně další podle snímků) a do `LAMPS` podle září trati (`strg`, `stry`, `lpol`, `bldy` …). Monaco už záznam má.
7. **Jas aut.** V noci svítí auta jen měsíc (0,1) a tmavá obloha. Porovnat se snímky originálu a případně použít `ambient` z `.map` (0,30 Monaco, 0,73 Industrial) jako okolní světlo aut. Hypotézu nejdřív ověřit v exe.
8. **Testy a měření.**
   - Test: `monaco1` a `industrial` bez `--time` startují v noci s oblohou originálu a neztlumenou tratí, `farmland` ve dne.
   - Snímky za autem (stojící a v jízdě) v low quality na monaco1 a industrial.
   - FPS za autem (kokpit ne).
9. **Později (mimo tento krok).** Majáky policie jako druhá projekce (červená a modrá), blesky Industrial (`industrial_lightning.bin`), podsvícené budíky `gnl*` v kokpitu.
10. **Dokumentace.** Po přijetí rozhodnutí D-xxx, úkoly do `docs/plan.md`, `night.psh` do `data/inventory.yaml` a `docs/formats`.
