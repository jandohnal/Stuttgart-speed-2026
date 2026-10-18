---
type: idea
id: IDEA-009
title: "Grafika: světlo, stíny, materiály, světla aut a efekty pneumatik"
status: accepted        # idea | accepted | rejected | done
created: 2026-10-17
related: [D-002, D-012, D-014, D-019, D-021, IDEA-003, IDEA-007, IDEA-008]
tags: [rendering, lighting, shadows, environment, materials, glass, particles, skidmarks, godot]
---

# Grafika: světlo, stíny, materiály a efekty

Godot 4.7 (Forward+, Metal) umí mnohem víc, než prototyp zatím využívá. Rychlá vylepšení (obloha, tonemapping, slunce a stíny, SSAO, glow, mlha, vyhlazování hran, filtrování textur, lak a sklo auta) jsou zadaná jako samostatný úkol pro Claude Code. Tento soubor popisuje celek včetně dalších kroků.

Výchozí stav (17. 10. 2026, `game/scenes/main.tscn`): `WorldEnvironment` s `ProceduralSkyMaterial`, okolní světlo z oblohy, tonemapping Filmic, slabá mlha; `DirectionalLight3D` se stíny do 250 m; MSAA 2×; materiály z `tools/crp.py` mají `roughness` 0,8, `metallic` 0.

## 1. Prostředí a světlo

| Oblast | Možnosti v Godotu 4.7 | Poznámka |
| --- | --- | --- |
| Obloha | `ProceduralSkyMaterial`, `PhysicalSkyMaterial` (Rayleigh/Mie, slunce podle `DirectionalLight3D`), `PanoramaSkyMaterial` s HDRI | HDRI zdarma z Poly Haven (CC0) |
| Tonemapping | Linear, Reinhard, Filmic, ACES, AgX + expozice, white | AgX: přirozené barvy |
| Globální osvětlení | SDFGI (dynamické, Forward+), VoxelGI, `LightmapGI` (zapečené) | Pro statickou trať nejkvalitnější a nejlevnější za běhu je LightmapGI |
| Ambient occlusion | SSAO, SSIL | Kontaktní stíny, nepřímé světlo v obrazu |
| Odrazy | SSR, odrazy z oblohy, `ReflectionProbe` | Probe sledující auto je dražší, zkusit s nízkou frekvencí aktualizace. **Hotovo:** sonda jedoucí s autem, `UPDATE_ONCE` (D-018) |
| Stíny slunce | PSSM 2/4 rozdělení, `blend_splits`, dosah, `light_angular_distance` (měkké stíny PCSS), velikost atlasu a kvalita filtru v nastavení projektu | |
| Mlha | Hloubková a výšková mlha, `fog_sun_scatter`, aerial perspective, volumetrická mlha, `FogVolume` | Volumetrická je dražší |
| Post-processing | Glow, úpravy (jas, kontrast, sytost), barevná korekce (LUT), DOF a automatická expozice přes `CameraAttributes` | |
| Vyhlazování hran | MSAA, TAA, FXAA, SMAA; upscaling FSR2, na Macu případně MetalFX (ověřit nabídku v 4.7) | |

### Denní doba a počasí
- **Hotovo (D-019):** den a noc podle trati z HDRI (`PanoramaSkyMaterial`), slunce ve směru nejjasnějšího místa HDRI, noc s měsícem, volba v menu (`game/scripts/sky_lighting.gd`).
- **Hotovo (D-021):** noční světla tratí originálu: záře z `ef` a `flare.dat` (lampy, tunely, blikající výstražná světla, šipky), skupina `OmniLight3D` u nejbližších září, svítící okna a neony v texturách Monaka (`game/scripts/track_lights.gd`).
- Pohyb slunce, barva světla, obloha a mlha podle času.
- Déšť: mokrá silnice (nižší drsnost + SSR), kapky, sprška od kol, menší přilnavost (IDEA-008).

## 2. Materiály

| Materiál | Nastavení | Efekt |
| --- | --- | --- |
| Lak auta | `clearcoat` 1,0, `clearcoat_roughness` ≈ 0,1, `roughness` ≈ 0,3, metalíza `metallic` ≈ 0,3 | Lesklý lak s odrazy oblohy |
| Chrom | `metallic` 1,0, `roughness` 0,05–0,15 | Nárazníky, lemy, ráfky |
| Sklo | Průhlednost alfa ≈ 0,25–0,35, `roughness` ≈ 0,05, vysoký `specular`, volitelně maska špíny | Vidět interiér za jízdy (interiér je v modelech originálu: `interior.fsh`, `intglass.fsh`) |
| Pneumatiky, plasty | `roughness` 0,8–0,95 | |
| Silnice, tráva | Detailní textura (`detail_enabled`), triplanární mapování pro terén | Zrno asfaltu a stébla zblízka přes nízké textury originálu |
| Reliéf | Normálová mapa; `heightmap_enabled` (parallax occlusion) pro dlažbu, obrubníky, kameny | Godot nemá teselaci; skutečný posun geometrie jen hustším meshem nebo vertex shaderem |
| Generované mapy | Normálové a drsnostní mapy z AI nástrojů | Viz IDEA-003 |

Rozlišení materiálu (lak, sklo, chrom...) podle názvu textury nebo materiálu z `.tpg` (`exterior`, `glass`, `intglass`...) v `tools/crp.py` nebo při načtení v Godotu.

## 3. Světla aut

- **Hotovo (D-019, `game/scripts/car_lights.gd`):** v noci dva reflektory `SpotLight3D` s měkkými stíny PCSS (dosah 200 m) a svítící skla, zadní světla v noci a při brzdění (emise tónovaná červeně + `OmniLight3D`). Zbývá: projektor kužele, dálková/potkávací, couvací zvlášť, zhasnutí při poškození.
- **Přední světla:** `SpotLight3D` se stíny a texturou kužele (projektor), emisivní skla, glow. Dálková/potkávací.
- **Brzdová a couvací:** emise + malé `OmniLight3D`, napojené na brzdu a zpátečku.
- **Poškození:** rozbité světlo zhasne (IDEA-007).
- Výkon: stíny jen u světel auta hráče, u soupeřů bez stínů.

## 4. Efekty pneumatik a povrchu

| Efekt | Řešení |
| --- | --- |
| Kouř z pneumatik | `GPUParticles3D`, měkké billboardy (proximity fade), množství podle prokluzu z modelu pneumatik, křivky velikosti a průhlednosti, turbulence, osvětlené sluncem |
| Stopy pneumatik | Generovaný pás (ribbon) podél dotyku kola, kruhový buffer stovek segmentů, mizení; intenzita podle prokluzu a povrchu. `Decal` jen pro jednotlivá místa (olej, stopa po nárazu) |
| Prach mimo silnici | Částice spouštěné povrchem pod kolem (IDEA-008), velké a dlouhožijící, vítr, kolize s terénem přes `GPUParticlesCollisionHeightField3D` |
| Štěrk, tráva, bláto, louže | Viz IDEA-007 |

Kouř a stopy pomáhají ladit jízdní model (vidět, kdy a kde kola prokluzují), proto se hodí už do prototypu.

## 5. Kvalita a výkon

- Předvolby kvality (nízká / střední / vysoká) v nastavení hry: stíny, SDFGI, SSR, SSAO, volumetrická mlha, počet částic, vyhlazování.
- Měřit FPS na Apple Silicon (Godot monitor, `Performance`), cíl stabilních 60 FPS při 120 Hz fyzice.

## Další kroky

- [x] Rychlá vylepšení prostředí a materiálů (17. 10. 2026, `game/scripts/materials.gd`, `main.tscn`, výsledky níže)

### Výsledky rychlých vylepšení (17. 10. 2026, M1 Pro, 3600 × 2260)

- Před 85 FPS, po s plnou kvalitou 35 FPS, výchozí nastavení 55 FPS (kokpit 47). Snímky v `decomposed/screenshots/before|after`.
- Nejdražší: měkké stíny (vypnuté stíny +15 FPS, filtr střední místo vysokého +6, PCSS `light_angular_distance` ~5), SSAO ~4, glow ~3, detail trati ~4, sklo a lak v kokpitu ~7. Atlas 8192 vs 4096 a anizotropie 16× bez měřitelného rozdílu.
- SDFGI: 26 FPS a vizuálně skoro beze změny, vypnuté. SSR: měření nespolehlivé, vypnuté. TAA s MSAA 29 FPS, bez přínosu, vypnuté.
- Godot 4.7 nabízí MetalFX spatial i temporal. Spatial 0,75 (jen macOS, `scaling_3d/mode.macos`) vrací ~20 FPS bez viditelné ztráty; temporal (bez MSAA) jen 42 FPS.
- MSAA bylo už předtím 4× (hodnota 2 = 4×), výchozí stav výše uvádí chybně 2×.
- Sklo: tabule z textury `glass`/`intglass` má alfa 0,3/0,15, rám zůstává neprůhledný; interiér je za jízdy vidět, chyby řazení na snímcích nejsou.
- Detail trati jen jako albedo (detailní normálová mapa by potřebovala tangenty).
- [ ] Kouř a stopy pneumatik napojené na prokluz
- [ ] Prach podle povrchu (po IDEA-008)
- [x] Přední a brzdová světla, den a noc z HDRI (18. 10. 2026, D-019; couvací zvlášť zbývá)
- [ ] LightmapGI pro trať a srovnání se SDFGI
- [ ] Předvolby kvality
- [x] Zapsat jako rozhodnutí do `docs/decisions.md` (D-014, výchozí nastavení prototypu)
