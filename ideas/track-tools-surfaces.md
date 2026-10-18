---
type: idea
id: IDEA-008
title: "Nástroje pro rekonstrukci tratí, destrukční prvky a povrchy krajnic"
status: idea            # idea | accepted | rejected | done
created: 2026-10-17
related: [D-003, D-008, D-009, D-012, IDEA-001, IDEA-003, IDEA-004, IDEA-007]
tags: [tracks, tools, blender, godot, surfaces, physics, destruction, pipeline]
---

# Rekonstrukce tratí, destrukční prvky a povrchy

Vše zdarma (D-012). Hlavní editor tratí je Blender, rozmístění herních objektů a chování povrchů se řeší v Godotu.

## 1. Nástroje

| Nástroj | Použití |
| --- | --- |
| **Blender** (zdarma) | Hlavní editor trati: import glTF z `tools/track2gltf.py`, úpravy geometrie, krajnic a příkopů. Geometry Nodes pro rozmístění svodidel, sloupků, patníků a cedulí podél křivky silnice. Cell Fracture pro předem rozbité zídky a sloupky (IDEA-007). Malování povrchů (Texture Paint / Vertex Paint) |
| **Godot editor** | Destrukční prvky jako samostatné scény (prefaby): `guardrail.tscn`, `wall_stone.tscn`, `cone.tscn`, `flag.tscn`... každá s fyzikou, prahy rozbití a částicemi |
| **Bezplatné doplňky Godotu** (licence ověřit, očekávaná MIT) | **Terrain3D** (terén + malování povrchů), **ProtonScatter** (rozmístění objektů po plochách a podél cest), **Road Generator** (silnice podle křivek) |
| **Krita / GIMP** (zdarma) | Malování mapy povrchů |
| **Vlastní import skript** (`EditorScenePostImport`) | Převod značek z Blenderu na herní scény podle konvence názvů nebo vlastních vlastností (custom properties → glTF `extras`). Vestavěné přípony Godotu: `-col`, `-colonly`, `-convcolonly`, `-rigid` |

## 2. Pipeline trati

1. `tools/track2gltf.py`: trať originálu → glTF v `decomposed/`.
2. Blender: úpravy, krajnice, značky (prázdné objekty) pro destrukční prvky, malování povrchů. Soubor `.blend` obsahuje geometrii originálu → ukládat do `decomposed/` nebo jiné necommitované složky (D-008).
3. Export glTF → import do Godotu → import skript nahradí značky scénami (`guardrail_01` → instance `guardrail.tscn`), nastaví kolizní vrstvy a materiály povrchů.
4. Validace: chybějící kolize, neznámé značky, objekty mimo terén.

### Konvence značek (návrh)
| Název / vlastnost v Blenderu | Výsledek v Godotu |
| --- | --- |
| `guardrail_*` | Instance svodidla, orientace podle objektu |
| `wall_*` | Zídka s předem rozbitou variantou |
| `prop_<typ>_*` (cone, barrel, sign, fence) | Fyzikální objekt, spící do nárazu |
| `cloth_<typ>_*` (flag, tarp, curtain) | Látka (shader / `SoftBody3D` v blízkosti) |
| vlastnost `surface=<typ>` na meshi | Povrch geometrie (viz kap. 3) |

## 3. Povrchy krajnic: šotolina, hlína, tráva, štěrk

Kola jsou vlastní raycasty (D-003), takže každé kolo v každém fyzikálním kroku zjistí povrch pod sebou.

### Způsoby určení povrchu
1. **Mapa povrchů (doporučeno):** textura při pohledu shora přes celou trať, barva/kanál = typ povrchu. Kolo čte podle pozice X/Z. Rychlé, plynulé přechody (míchání), krajnice se upravuje malováním. Malování v Blenderu, Kritě/GIMPu nebo v Terrain3D.
2. **Povrch podle geometrie:** vertex color nebo materiál na plochách v Blenderu, kolo čte podle zasaženého trojúhelníku. Přesnější pro mosty, tunely a svislá místa.
3. **Kombinace:** mapa pro terén a krajnice, geometrie pro mosty a tunely.

Nejdřív zkontrolovat, zda data trati originálu (`SimD`) neobsahují příznaky povrchu. Pokud ano, vygenerovat z nich první verzi mapy automaticky.

### Tabulka povrchů (`surfaces.json`, výchozí odhady k ladění)

| Povrch | Přilnavost | Valivý odpor | Nerovnosti | Částice | Zvuk | Stopy |
| --- | --- | --- | --- | --- | --- | --- |
| Asfalt | 1,0 | nízký | žádné | kouř při smyku | pískání | černé stopy |
| Šotolina | 0,6–0,7 | střední | drobné | štěrk + prach | šustění, cvakání | rýhy |
| Štěrk (hrubý) | 0,5–0,6 | vyšší | výrazné | kamínky | křupání | hluboké rýhy |
| Hlína | 0,55–0,7 (mokrá 0,35) | střední (mokrá vysoký) | střední | prach / bláto | tupé | vyjeté koleje |
| Tráva | 0,4–0,5 (mokrá 0,3) | vysoký | drobné | tráva, hlína | šelest | ušlapaná tráva |

Povrch ovlivní: model pneumatiky (přilnavost, odpor, vibrace řízení), zvuk (IDEA-004), částice a decaly (IDEA-007).

## Další kroky (pokud se nápad přijme)

- [ ] Zkontrolovat příznaky povrchu v datech `SimD`
- [ ] `surfaces.json` + čtení povrchu v kole (nejdřív mapa povrchů pro jednu trať)
- [ ] Import skript se značkami a jedna testovací scéna svodidla
- [ ] Ověřit licence doplňků Terrain3D, ProtonScatter, Road Generator
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
