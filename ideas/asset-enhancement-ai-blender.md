---
type: idea
id: IDEA-003
title: "Vylepšení modelů a textur pomocí AI a automatizace v Blenderu"
status: idea            # idea | accepted | rejected | done
created: 2026-10-15
related: [D-008, D-009, IDEA-001]
tags: [assets, textures, upscaling, pbr, blender, bpy, pipeline, lod, damage]
---

# Vylepšení modelů a textur: AI a Blender

Původní modely (nízký počet polygonů) a textury (malé, 8bitová paleta) se dají zlepšit kombinací AI nástrojů a skriptované práce v Blenderu. U textur je AI spolehlivá. U geometrie víc pomůže klasické zpracování a automatizace v Blenderu než generativní AI.

Zařazení: až po hratelném prototypu s původními assety (D-009). Všechny výstupy z původních assetů patří do `decomposed/` a necommitují se (D-008).

## 1. Textury

| Technika | Nástroje | Přínos | Omezení |
| --- | --- | --- | --- |
| AI zvětšení (4–8×) | Real-ESRGAN a komunitní modely pro herní textury; na Macu chaiNNer (dávkové zpracování), Upscayl | Čistší a ostřejší textury | Nevznikne skutečný detail; nápisy, čísla a loga se rozmazávají; nejdřív odstranit dithering z palety |
| Generování PBR map | DeepBump (doplněk Blenderu), Materialize a podobné | Normálová mapa, drsnost, AO → největší vizuální skok v moderním enginu | Odhad, ne skutečná data; ruční kontrola u lesklých ploch |
| Generativní přetexturování | Stable Diffusion + ControlNet se starou texturou jako předlohou | Nový detail | Nesedí na švech UV, nekonzistence mezi díly; vhodné spíš na okolí (skály, tráva, zdi, asfalt) |

## 2. Geometrie

| Technika | Přínos | Omezení |
| --- | --- | --- |
| Přepočet normál, vyhlazovací skupiny, zkosení hran, cílené jemné dělení | Hladší vzhled starých modelů, levné, skriptovatelné | Nemění siluetu |
| Detail do normálové mapy (pečení z detailnější verze) | Spáry, mřížky, nýty bez nárůstu geometrie; vhodné pro deformovaná auta | Potřeba detailnější verze k pečení |
| AI generování 3D (Meshy, Tripo, Rodin, open-source Hunyuan3D, TRELLIS) | Rychlý model z obrázku nebo renderů | Hustá chaotická síť, zapečené světlo, nerozdělené díly → nevhodné pro auta s poškozováním bez přemodelování; open-source modely většinou vyžadují GPU NVIDIA, na Macu prakticky cloud |

AI 3D má smysl hlavně pro předměty v okolí trati (skály, kmeny, sudy, cedule, jednoduché budovy) a jako předloha pro ruční modelování.

## 3. Automatizace Blenderu Claudem

### Způsoby ovládání
- **Python API (bpy), bez okna:** `blender --background --python skript.py`. Claude Code skripty píše, spouští a verzuje v `tools/`. Nejspolehlivější pro dávkové zpracování.
- **Blender MCP (komunitní):** Claude ovládá běžící Blender a vidí snímky viewportu. Pro interaktivní práci.

### Silné stránky
- **Validátor herních pravidel:** počet polygonů, n-gony, nemanifoldní geometrie, duplicitní vrcholy, neaplikované transformace, měřítko, počátek, pojmenování, překrývající se UV, pevné hrany.
- **Optimalizace:** LOD, decimate s ochranou siluety, slučování materiálů, normály, zkosení hran.
- **Příprava pro hru:** kolizní konvexní obaly, rozdělení auta na díly pro poškození (nárazníky, kapota, dveře), skupiny vrcholů pro zóny deformace, UV, pečení normálových map.
- **Parametrické a procedurální modelování:** silnice podél křivky, terén, svodidla, budovy, kola, pneumatiky, ráfky (souvisí s IDEA-001).
- **Hromadné a reprodukovatelné zpracování** všech 44 aut.

### Limity
- Volné organické tvary (plynulá karoserie) se modelují podle oka. Claude pracuje se souřadnicemi a snímky, výsledek bývá technicky správný, ale tvarově průměrný.
- Čistá topologie složitých zakřivených ploch (quady, smyčky kolem otvorů, póly mimo deformované oblasti) se bez přímého vidění dodržuje obtížně.

## Doporučený postup

1. Prototyp (D-009) na původních assetech bez úprav.
2. Blender pipeline pro původní auta: import z `decomposed/` → normály → rozdělení na díly pro poškození → kolize → LOD → validace → export glTF. Část může být potřeba už pro prototyp (díly a zóny poškození).
3. Dávkové AI zvětšení textur + generování normálových map.
4. Zkosení hran a vyhlazení aut skriptem.
5. Fiktivní auta: Claude připraví parametrický základ (proporce, rozvor, kola, díly, technická pravidla), tvar karoserie doladí člověk nebo AI předloha, validátor zkontroluje pravidla.
6. AI 3D generování pro předměty v okolí tratí.

## Další kroky (pokud se nápad přijme)

- [ ] Ověřit instalaci Blenderu na Macu a spuštění bez okna
- [ ] Validátor herních pravidel `tools/blender/validate.py` + definice limitů (polygony na LOD, pojmenování dílů)
- [ ] Pipeline skript pro jedno původní auto (díly, kolize, LOD, export)
- [ ] Test AI zvětšení na texturách jednoho auta, porovnání před a po
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
