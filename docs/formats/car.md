# `nfs5.car` – databáze aut menu (barvy laku)

`sources/FEData/Data/nfs5.car`, převodník `tools/car_colors.py` → `decomposed/FEData/Data/car_colors.json`. Rozluštěné jen to, co hra potřebuje (barvy), 18. 10. 2026.

## Struktura

109 záznamů po 0x670 B (velikost souboru 179 632 B), jeden na variantu auta (i policie, provoz `eas*`/`eden*`, tovární auta `F*`). Řetězce jsou nulou ukončené, latin-1.

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x02 | char[0x31] | jméno v menu („'56 356 A 1600 Coupé“) |
| 0x34 | char | řada („356“) |
| 0x4D | char | identifikátor („1956356ACabrio13“) |
| 0x7F | char | model = složka v `GameData/CarModel` („356A“, „996“, „cop993“; velikost písmen nesedí) |
| 0xB1 | char | klíč varianty = klíč v `cars.json` a `main.gd CARS` („356Acoupe16“) – u policie a provozu se opakuje |
| 0xE4 | char | jméno fotky/loga („356-14“), dál logo, zvuková sada („sd1b“), karoserie, motor |
| 0x1BF | u8 | 1 u otevřených karoserií (cabrio, speedster, roadster, Boxster, targa ne) – jen pozorováno |
| 0x1C0 | u8 | **styl modelu − 1**: `[styleN]` v `.tpg` modelu, který vybírá díly a textury varianty ([crp.md](crp.md#styly-varianty-modelu)); ověřeno 19. 10. 2026: 356Acoupe16 → style9 „16Coupe“, 356Aspeed16 → style11 „Speeds1600“, 901carreraRS27 → style7 u 901 a style1 u F901, 993Tcoupe36 → style9 „turbocoupe“, 964coupe436 → style5 „Carrera4coupe“ |
| 0x1F8+ | float32[] | křivka točivého momentu a další data – nerozluštěno |
| 0x3E6 | u16 | počet barev exteriéru (19, 550: 1, provoz a cop930: 0) |
| 0x3E8 | 16 B × počet | barvy exteriéru |
| za nimi | 16 B | nuly |
| dál | u32 + 16 B × počet | barvy interiéru (5) |

### Položka barvy exteriéru (16 B)

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0 | u32 | příznak 0 nebo 0xCD (bílá, krémová, černá – význam neznámý) |
| 4 | `FF R G B` | **lak karoserie** |
| 8 | `FF R G B` | doplňková barva 1 (pruhy/obtisky?) |
| 12 | `FF R G B` | doplňková barva 2 |

Paleta je u všech aut stejná (19 barev), liší se jen pořadí: **první položka je tovární barva varianty** (356 A coupe modrá `#004396`, 996 červená `#ff0000`, 935 žlutá `#fbb112`). Interiér má položky se stejnou stavbou a jednou barvou (`#626364`, `#586782`, `#c5a162`, `#984141`, `#a3a6aa`), zbytek je černý.

## Použití ve hře

`car_colors.json` má u každé varianty `styles: {model: N}`. Klíč varianty se opakuje u policejních a továrních záznamů (993Tcoupe36 je 993 i cop993), proto styl pro každý model zvlášť. `main.gd` (`car_style_of`) bere styl modelu z menu, varianty bez záznamu v `nfs5.car` mají styl v `CARS` (993 Carrera 4S: 5, 944 Turbo S: 6).

Alfa atlasu exteriéru kromě síly odlesku určuje, čím se texel barví (ověřeno na mapě alfy 356 A, 935 a 996, 18. 10. 2026):

| Alfa | Oblast |
| --- | --- |
| 204 | karoserie |
| 153, 179, 230 | pruhy přes kapotu, střechu a víko (vodorovný pás a svislé pruhy) |
| 166 | pás na boku nad prahem |
| 77 | prahy a 1–2 px okraje pruhů |
| 255, 0 | chrom, světla, nápisy, mřížky / ořez |

Pruhy jsou v textuře světle šedé jako karoserie a originál je zřejmě barví podle sady pruhů z `.clr` (`stripepackage`, 4 barvy). Proto se po obarvení jen alfy 204 objevil bílý pruh. Hra barví všechny tyto zóny jednou barvou: 77, 153, 166, 179, 204 a 230 (±2). Barva se násobí svítivostí texelu dělenou průměrnou svítivostí jeho zóny, takže každá zóna má v průměru zvolenou barvu a stínování textury zůstane (`game/scripts/materials.gd`, `_paint`). Stejně se barví i obtisky, protože některé mapují texely karoserie (u 935 dva pruhy na víku motoru, `DecalHood`). Jejich potištěné části mají jinou alfu a zůstanou beze změny, stejně jako chrom a světla.

`GameData/CarModel/*.clr` (INI, `[sectionN]`, `stripepackage`, `colorN.h/s/v`, `colorN.r/g/b`) nejsou barvy laku, ale sady barev pruhů. Hra je nepoužívá.
