# Voda v originálních datech

Rozbor vodních prvků tratí originálu (30. 10. 2026) jako podklad pro vodní hladiny, vodopády, fontány a tříšť ve hře. Možnosti Godotu jsou shrnuté na konci.

## Jak se hledalo

- **Textury:** názvy materiálů všech tratí (glTF z `track2gltf.py`) a průměrná barva všech 3 139 textur tratí vážená průhledností. Modré pozadí karet stromů a keřů tak nemate. Kandidáty jsem ověřil náhledem.
- **Geometrie:** pro každý vodní materiál vodorovná plocha (normála |y| > 0,7) a strmá plocha, rozsah výšek a vzdálenost od nejbližšího řezu silnice.
- **Částice:** systémy v `particle.ini` (`particles.json`, [formats/particle.md](formats/particle.md)) a zdroje `ef` druhu 3 v `<trať>_lights.json` (`emitters`, [formats/crp.md](formats/crp.md#efekty-ef-článku)).
- **Objekty:** značka `HYDR` v `<trať>_objects.json`.
- **Omezení:** voda jiné barvy s nenápadným názvem (třeba zelený rybník) mohla uniknout. Data pro déšť ani mokrou silnici jsem nenašel.

## Po tratích

| Trať | Hladina | Vodopád | Částice (`ef`) | Ostatní |
| --- | --- | --- | --- | --- |
| forest | potok `rvr1` (2 420 m², 22 m od silnice) a peřeje `rvr2` pod mostem (2 405 m², 6 m) | `wfw2`, `wfw4`, výška asi 90 m (y 96–188), 30 m od silnice | peřeje `RPD1`–`RPD4` (most `BROOKBRIDGE`), vodopád `WF07` (`BIGWF2`), mlha `WF08`, `WF02` | |
| canyon | řeka nebo jezero `wtr3`, `wtr4` (asi 24 ha, y −51 až 18), 217 m od silnice | `wfw2`, `wfw4`, výška asi 90 m, 44–50 m od silnice | `WF03` (hlavní), `WF04` (malý), `WF05` (rozdělený), `WF06` (mlha u paty) | |
| castle | – | `wfw1`, `wfw2`, `wfw4`, `wfw2` padá přes 130 m (y −102 až 32), 27–31 m od silnice | vodopád `WF01`, mlha `WF02`, fontána na nádvoří `CTM1`, kapky `CTD1`, `CTD2` (`COURTYARD`) | 19 rozmístěných hydrantů (`HYDR`) |
| coastal | moře `wtr3`, `wtr4` (asi 167 ha, hladina y −7,3), 36 m od silnice | – | – | pobřeží `seaa`–`seah`: skály, tráva a pláž přecházející do vody (`seaa` 17 ha mělčiny, `seab` 4 m od silnice) |
| monaco1–4 | přístav a moře `wtr1`, `wtr2` (40–85 ha, y −47 až −14), 26–105 m od silnice | – | fontána u kasina `CSF1`, `CSF2`, po 4 (`CASINOFOUNTAIN`) | fontána: proudy `fnt1`–`fnt3`, nádrž `fnt4` (77 m²), 20–37 m od silnice |
| monaco5 | přístav a moře `wtr1`, `wtr2`, 27 m od silnice | – | – | bez fontány |
| alps | rovná tmavě modrá plocha `alkb` (1,9 ha, y 184–186), 58 m od silnice | – | – | nejspíš horské jezero, na trati neověřeno |
| farmland, foothills, autobahn, industrial, skidpad | – | – | – | vodu jsem nenašel |

## Zavádějící názvy

| Název | Ve skutečnosti |
| --- | --- |
| `wtr2` na castle a industrial | textura náklaďáku (na monaco je to voda) |
| `aqa*`, `aqua`, `aq10` (castle) | zdi akvaduktu |
| `waa*` (monaco) | fasády domů |
| `wav1`, `wav2` (forest) | postavičky v krojích |
| `wf01`–`wf06` | ploty a zdi |
| `wfc4`–`wfc6` (castle) | skály u vodopádu |
| `dokc` (industrial) | 18 m², není to vodní plocha |

Vodu tedy nepoznáme podle názvu: stejný název má na různých tratích různé obrázky. Hra by měla vodu brát ze seznamu (trať, textura) z této tabulky.

## Vodní částice originálu

| Systém | Značka | Textura | Počet | Barvy (první → poslední) |
| --- | --- | --- | --- | --- |
| WaterfallTop | `WF01` | `WFAL` | 34 | `#ffffffff` → `#64bcc0a0` |
| WaterfallMistBottom | `WF02` | `sstk` | 30 | `#ffdbe3c6` → `#00dfe1ec` |
| CanyonWaterfalMain | `WF03` | `WFAL` | 44 | `#ffffffff` → `#449db1d7` |
| CanyonWaterfalSmall | `WF04` | `WFAL` | 46 | `#ffffffff` → `#809dbed9` |
| CanyonWaterfalSplit | `WF05` | `WFAL` | 24 | `#ffffffff` → `#b3acc8e3` |
| CanyonWaterfalBottom | `WF06` | `sstk` | 40 | `#ffcebbd9` → `#00ffffff` |
| WaterfallForestTop | `WF07` | `WFAL` | 40 | `#ffffffff` → `#44cdf3fe` |
| WaterfallForestWindomist | `WF08` | `sstk` | 14 | `#00ffffff` → `#34ffffff` |
| RiverRapidLeft, Right, Back | `RPD1`–`RPD3` | `WFAL` | 20 | `#ffffffff` → `#28ccd7f2` / `#28b7cee6` |
| RiverRapidMist | `RPD4` | `sstk` | 20 | `#00ffffff` → `#50ffffff` |
| CastletownFountainMain | `CTM1` | `FOUN` | 36 | `#ffffffff` → `#3ccee9ff` |
| CastletownFountainDrips | `CTD1`–`CTD3` | `DRIP` | 20–40 | `#3cf2feff` → `#c3dfeeff` |
| CasinoFountainTop | `CSF1`, `CSF2` | `FOU2` | 22, 14 | `#93ffffff` → `#d3cee9ff` |
| HydrantSpout, Top, MistBottom | `HYDR`, `HYDB`, `HYDM` | `WFAL`, `sstk` | 28, 40, 20 | bílá → průhledná |

Polohy a směry zdrojů jsou v `<trať>_lights.json` (`emitters`, s článkem). Zdroje `HYDR`, `HYDB` a `HYDM` v převedených tratích nejsou. Nejspíš patří k předloze hydrantu, kterou rozmisťují úlohy (`.scn`).

## Možnosti Godotu (D-012: jen vestavěné prostředky)

- **Hladina:** rovina nebo původní mesh s vlastním shaderem: posouvané normálové mapy, Fresnel, barva a průhlednost podle hloubky (`DEPTH_TEXTURE`), pěna u břehu, lom (`SCREEN_TEXTURE`). Odrazy dává SSR, `ReflectionProbe` nebo obloha. Planární zrcadlo by potřebovalo druhou kameru (`SubViewport`), skoro dvojnásobek vykreslování.
- **Vodopád:** původní mesh s posouvaným UV a průhledností, k tomu `GPUParticles3D` tříště a mlhy podle systémů výše na polohách z `emitters`.
- **Tříšť od kol:** jako prach (D-028), povrch podle textury pod kolem.
- **Déšť:** částice kolem kamery (čárky jako jiskry), `GPUParticlesCollisionHeightField3D`, aby nepršelo pod střechy, mokrá silnice (nižší drsnost, tmavší albedo), `FogVolume`, nižší přilnavost pneumatik.
