---
type: file-format
format: map
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/Track/*.map", "GameData/Track/*.env"]
count: {map: 15, env: 15}
status: done
tool: ["tools/light_decals.py", "tools/fsh2png.py"]
output: ["decomposed/GameData/Track/<trať>/<trať>_decals.json", "decomposed/GameData/Track/<trať>/env/*.png"]
updated: 2026-11-15
---

# Formát `.map` a `.env` – světelné obtisky na autech

`<trať>.map` je textový INI, `<trať>.env` archiv SHPI s obrázky 64×64 ([fsh.md](fsh.md)). Dohromady popisují, jaké světlo nebo stín se promítá na auto v určitém místě trati: záblesky lamp v tunelech, stín stromů nad silnicí, světla Monaka. Nejde o odrazy okolí (ty jsou v originálu jinde, hra je řeší sondou, D-018).

Rozluštěno z `Porsche.exe` (Ghidra, 15. 11. 2026): načítání `FUN_004409d0` (cesty `%s%s.env` a `%s%s.map`), výběr sekce `FUN_00441140`, textury `FUN_00441180`, nastavení auta na adrese 0x43a724 až 0x43a8a6 (kód mimo funkce Ghidry) a výpočet UV `FUN_00445b10`.

## `.map`

Načítá se pouze tehdy, když existuje sekce `[header]`. Klíče, které hra nečte, se ignorují. Sekce `[section0]` většiny tratí má navíc `texture1`, `clamp1/2`, `tint1/2` a `scroll1/2` bez `.open`, které hra nečte (asi starší podoba formátu).

| Sekce | Klíč | Typ | Výchozí | Význam |
| --- | --- | --- | --- | --- |
| header | `count` | int | 0 | počet sekcí `[section0]` … `[section<count−1>]` |
| header | `tint`, `ambient`, `interior`, `interiordiffuse`, `lightdecal` | 4× float (a, r, g, b) | 1; `ambient` 0,3 | barevné faktory trati. `lightdecal` násobí barvu obtisku, ostatní zatím nevyužité (viz [flare.md](flare.md)) |
| sectionN | `startslice`, `endslice` | int | 0 | rozsah řezů `SimD` (včetně obou krajů) |
| sectionN | `texture1.open` … `texture3.open`, `texture1.covered` … `texture3.covered` | u32 | `ENV0` | 4CC jména obrázku v `.env`, zapsané jako desítkové číslo little-endian (540103746 = `BT1 `) |
| sectionN | `texturesize` | float | 6,0 | velikost textury v metrech |
| sectionN | `aspect` | float | 1,0 | poměr podélného měřítka k příčnému |

Sekce v paměti zabírá 0x48 B: start, konec, tři `open`, tři `covered` (offset +8 + (stupeň + 3 · covered) · 4), ukazatele za běhu, na +0x40 `texturesize` a na +0x44 `aspect`. `ENV0` v žádném `.env` není, takže chybějící klíč znamená, že tam žádný obtisk není.

## `.env`

Archiv SHPI s obrázky 64×64 typu 0x7D (32 bitů). RGB je v celém obrázku jedna barva (barva světla), tvar a sílu nese alfa. Dvojice `x1`/`x2` mají stejnou barvu, `x2` má dvojnásobnou alfu. Názvy obsahují barvu a druh: `BT`, `YT`, `WT`, `GT` modrá, žlutá, bílá a zelená tunelová světla, `TT`/`TTL` černé (stín stromů a mostů), `AT`, `TD`, `BD`, `TL` světla dálnice, `T1S`/`T1M` tunel Monaka, `Ind` průmysl. Obrázek `1` je celý průhledný (bez obtisku), `2` a `3` jsou tmavé se světly lamp (na canyonu a v industrial). Obrázky `SKY` a `TUNN` na skidpadu a `BT` na foothills žádná sekce nepoužívá.

## Použití v originále

1. Při každém snímku hra najde podle řezu, na kterém auto je, **první** sekci s `startslice ≤ řez ≤ endslice`. Mimo všechny sekce auto žádný obtisk nemá.
2. Tři stupně textur: materiál auta podle své hodnoty (první float jeho parametrů) dostane `texture1` (< 0,05), `texture2` (< 0,95) nebo `texture3` (jinak). V datech jsou `texture1` a `texture2` téměř vždy stejné, `texture3` je silnější varianta `x2`.
3. `covered` platí pod střechou, `open` pod širým nebem. `FUN_00473330` najde nejbližší plochu víc než 3,5 m nad autem a vrátí její příznaky, `covered` platí, když mají bity 0xC000. Varianty se liší na autobahn (sekce 51, 56, 57, 59–62), coastal 0, foothills 6–13, forest 6, monaco1 1 a monaco3–5 (téměř všechny sekce). V tunelech monaco3–5 a foothills jsou lampy jen v `covered`, `open` je tam `1` (nic).
4. UV vrcholu: vrchol se převede do souřadnic auta (x napříč, z podél). Pak `u = x / texturesize + boční_posun / 60 + 0,5` a `v = z · aspect / texturesize + podélný_posun / 6 + 0,5`. Posuny jsou vzdálenost auta od středu jeho řezu podél vektoru doprava a dopředu (`SimD` +0x28 a +0x1C). Konstanty jsou 1/6 (`0x5b2420`), boční posun se navíc násobí 0,1. Textura se tedy posune o celou délku na každém řezu (~6 m): uprostřed řezu s lampou je auto pod středem záře, ke krajům řezu záře slábne.
5. Volbu hra zapíná nastavením (`0x6197cb`, nejspíš Graphics.Reflections). Jinak jsou všechny tři stupně prázdné.

Jak originál obtisk míchá s autem (stav texturových stupňů Direct3D), zatím rozluštěné není. Z dat vyplývá prolnutí podle alfy: černý stín ztmavuje, barevná záře zesvětluje.

## Převod a hra

`tools/light_decals.py` zapíše `<trať>_decals.json`: hlavičku, sekce (`first`, `last`, `open`, `covered`, `size`, `aspect`) a cesty k PNG z `env/` jen pro použité a ne úplně průhledné obrázky. Obrázky `.env` převádí `tools/fsh2png.py` do `<trať>/env/`.

Hra (`game/scripts/light_decals.gd`, shader `game/shaders/light_decal.gdshader`, D-044) dělá krok 1 až 4 pro každé auto. Stupně přiděluje podle druhu materiálu: interiér, podvozek a kola 1, karoserie 2, chrom a skla 3. Střechu nad autem pozná paprskem nahoru proti kolizi trati (silnice, terén, objekty) od 3,5 do 100 m nad autem. Příznaky ploch se nečtou, takže za střechu platí i převis skály. Obtisk se kreslí jako další průchod materiálu (`next_pass`). Míchání se od originálu liší: barva se přičítá jako světlo (`rgb · a · 0,25`) a auto se ztmaví jen o `a · (1 − jas)`, viz D-044.

Sekce podle tratí (počet / použité obrázky): alps 39 (`BT`, `YT`), autobahn 63 (`TTL`, `AT`, `TD`, `BD`, `TL`), canyon 69, castle 19 (`WT`), coastal 24, farmland 4 (`TT`, stín u řezů 56–105, 127–337 a 1808–1857), foothills 14, forest 13, industrial 29, monaco1–5 4–23, skidpad 1 (`SKY` jen na řezu 0).
