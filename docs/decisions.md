---
type: decisions
updated: 2026-10-17
format: "Každé rozhodnutí má ID, stav (accepted | proposed | superseded), kontext a důsledky."
---

# Rozhodnutí

## D-001 Duchovní nástupce, ne kopie
- **Stav:** accepted
- **Rozhodnutí:** Hra bude mít vlastní název (Stuttgart Speed). Zachovává hratelnost a atmosféru originálu, nekopíruje jeho obsah.
- **Důsledky:** Nepoužívají se loga, názvy ani tvary vozů Porsche. Mechaniky (kariéra napříč érami, mise testovacího jezdce) se přebírají jako nápad.

## D-002 Engine Godot 4.7
- **Stav:** proposed (potvrdit po prototypu jízdy, fáze 2)
- **Rozhodnutí:** Godot 4.7 (původně 4.6, 15. 10. 2026 přechod na tehdy aktuální 4.7.2), fyzika Jolt, renderer Forward+ přes Metal.
- **Důvod:** zdarma (MIT), nativní na Apple Silicon, nejrychlejší vývoj pro jednoho autora.
- **Alternativa:** Unity 6. Unreal 5 zamítnut kvůli náročnosti a slabší podpoře Macu.

## D-003 Vlastní jízdní model
- **Stav:** accepted
- **Rozhodnutí:** Raycast kola nad tuhým tělesem v Jolt, ne `VehicleBody3D`.
- **Důvod:** Charakter jednotlivých aut a „sim-cade“ pocit jde vyladit jen s plnou kontrolou nad modelem pneumatik a přenosem hmotnosti.

## D-004 Fiktivní auta
- **Stav:** accepted
- **Rozhodnutí:** Cílová auta hry jsou fiktivní designy inspirované érami (zadní motor 50. let, klínové tvary 70. let...).
- **Důsledky:** Fyzikální parametry originálu slouží jako reference pro realistické hodnoty dané éry. Výjimka pro první krok: viz D-009.

## D-005 Vlastní tratě ve stylu originálu
- **Stav:** accepted
- **Rozhodnutí:** Tratě se nekopírují. Zachovává se styl: evropská krajina, světlo, otevřené silnice, alternativní cesty. Silnice budou užší než v originálu.
- **Důsledky:** Cílové tratě jsou vlastní. Výjimka pro první krok: viz D-009, kvůli které je exportér alespoň jedné původní trati potřeba.

## D-006 Bez hudby
- **Stav:** accepted
- **Rozhodnutí:** Hra nebude mít hudbu z originálu ani licencovanou hudbu.

## D-007 Zvuky ze samplů
- **Stav:** accepted
- **Rozhodnutí:** Zvuky motorů se skládají z nasamplovaných smyček podle otáček a zátěže (granulární/crossfade syntéza). Zdroje: vlastní nahrávky nebo knihovny s licencí CC0/CC-BY.
- **Důsledky:** Několik typů motorů (např. plochý 4válec, plochý 6válec, turbo) sdílí více aut s jiným doladěním.

## D-008 Data originálu jen lokálně
- **Stav:** accepted
- **Rozhodnutí:** Repozitář je privátní. Veškeré assety z originální hry (a licencované modely) leží v `sources/`, vše rozbalené a převedené v `decomposed/`. Obě složky jsou v `.gitignore` a existují jen lokálně.
- **Důsledky:** Do gitu jde jen kód, nástroje, dokumentace a vlastní obsah. Nástroje čtou ze `sources/` a zapisují do `decomposed/` se stejnou strukturou podsložek.

## D-009 První krok s původním autem na původní trati
- **Stav:** accepted
- **Rozhodnutí:** Prototyp (fáze 2) se staví s jedním původním autem a na jedné původní trati z originální hry, převedenými do glTF ze `sources/` do `decomposed/`.
- **Cíl:** Ověřit, že migrovaná hra funguje a je hratelná. Teprve po splnění tohoto cíle se začne s vlastními tratěmi a vlastními auty.
- **Důvod:** Přímé srovnání s originálem. Stejné auto se stejnými parametry `.sim` na stejné trati umožní objektivně ladit jízdní model, kolize a poškození proti originálu spuštěnému přes Wine. Odpadá také tvorba vlastních assetů před ověřením hratelnosti.
- **Důsledky:**
  - Assety zůstávají jen lokálně v `decomposed/` (D-008). Godot projekt je načítá odtud a nic z nich necommituje.
  - Exportér auta (CRP → glTF) a exportér vybrané trati mají vysokou prioritu.
  - Fiktivní auta (D-004) a vlastní tratě (D-005) zůstávají cílem, ale práce na nich začne až po splnění milníku fáze 2 (hratelný prototyp s původním obsahem).
  - Volba konkrétního auta a trati: viz otevřená otázka v `docs/plan.md`.

## D-010 Poškození s následky a odpadajícími díly
- **Stav:** accepted
- **Rozhodnutí:** Poškození auta má kromě deformace i mechanické následky, které jsou realističtější a závažnější než v originále: rozbíhavost a menší přilnavost kola na poškozeném rohu, ztráta výkonu motoru, větší odpor vzduchu, menší rejstřík řízení. Při plném poškození zóny odpadnou její díly, kola se od poloviny poškození rohu viklají a při plném poškození rohu i boku upadnou. Kapota, kryt motoru a dveře se nejdřív uvolní na pantech (nad 50 % poškození předku nebo zádi, dveře i po tvrdém nárazu) a kapota a kryt motoru se utrhnou při nárazu z 100 km/h.
- **Důvod:** Přání uživatele (17. 10. 2026). Originál díly ani kola neodhazuje.
- **Důsledky:** Prototyp používá díly, které jsou v modelu originálu samostatné (kapota, víko motoru, dveře, světla, značka, výfuk, zástěry). Vlastní auta (D-004) se modelují s oddělenými nárazníky a blatníky, kotevními body a vnitřními plochami. Další návrhy jsou v [IDEA-006](../ideas/severe-damage-wheel-loss.md). Míru následků je potřeba doladit po srovnání s originálem.

## D-011 Zvuky originálu v prototypu, vlastní ve vydání
- **Stav:** accepted
- **Rozhodnutí:** Prototyp (fáze 2) používá zvuky originálu (motor 356 A ze sady `sd1a`, nárazy a pneumatiky ze `SND_coll.bnk`), převedené do `decomposed/` a načítané za běhu. Přehrávač pracuje s popisem sady (`engine.json`: smyčky a otáčky), takže se sada vymění za vlastní samply bez změny kódu.
- **Důvod:** Přímé srovnání s originálem a slyšitelná zpětná vazba (řazení, plyn, smyk) hned, bez čekání na vlastní nahrávky (obdoba D-009).
- **Důsledky:** Zvuky originálu se nikdy necommitují (D-008). Pro vydání platí D-007 a zdroje z [IDEA-004](../ideas/sound-engines-ambience.md); evidence licencí (`assets/audio/LICENSES.md`) vznikne s prvním vlastním zvukem.

## D-012 Žádné placené doplňky
- **Stav:** accepted
- **Rozhodnutí:** Projekt nepoužívá placené doplňky (Godot Asset Library, itch.io, Blender Market apod.). Funkce, které by doplněk řešil, se implementují vlastním kódem nebo se použije bezplatný open-source doplněk s kompatibilní licencí (MIT, BSD, Apache, CC0).
- **Důsledky:** Rozbíjení objektů, látky, částice a podobné systémy se staví z vestavěných funkcí Godotu 4.7 a vlastních skriptů. Použitý open-source doplněk se eviduje i s licencí. Nástroje mimo hru (Blender a jeho vestavěné doplňky, Python knihovny) musí být také zdarma.

## D-014 Výchozí grafické nastavení prototypu
- **Stav:** accepted
- **Rozhodnutí:** Prototyp používá `PhysicalSkyMaterial` (okolní světlo a odrazy z oblohy), tonemapping AgX, SSAO, glow a výškovou mlhu se sun scatter. Slunce pozdního odpoledne má PSSM 4 rozdělení do 500 m, `light_angular_distance` 0,5 a atlas 8192 se středním filtrem měkkých stínů. MSAA 4×, anizotropie 16×, na macOS upscaling MetalFX spatial 0,75. SDFGI, SSR a TAA jsou vypnuté. Materiály modelů originálu doplňuje za běhu `game/scripts/materials.gd` (lak, chrom, sklo, guma, detailní šum trati), bez nových assetů.
- **Důvod:** Měření z 17. 10. 2026 ([IDEA-009](../ideas/graphics-lighting-effects.md), `game/README.md`): na M1 Pro při 3600 × 2260 dá nastavení 55 FPS (kokpit 47) proti 35 FPS s plnou kvalitou. MetalFX 0,75 je na snímcích k nerozeznání od nativního rozlišení, SDFGI stojí třetinu FPS a skoro není vidět, TAA nic nepřidá.
- **Důsledky:** Cílových 60 FPS zatím nejsou. Zbytek dorovnají předvolby kvality (IDEA-009, krok 5): stíny, SSAO, glow a měřítko upscalingu. Na jiných platformách zůstává nativní rozlišení.
