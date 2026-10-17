---
type: idea
id: IDEA-007
title: "Realistické poškození aut, ničitelné okolí a částicové efekty"
status: idea            # idea | accepted | rejected | done
created: 2026-10-17
related: [D-003, D-010, D-012, IDEA-003, IDEA-004, IDEA-006, "docs/analysis.md#5-model-poškození"]
tags: [damage, deformation, destruction, softbody, cloth, particles, decals, godot, jolt]
---

# Poškození, ničitelné okolí a částice

Originál měl paušální poškození bez ohledu na místo nárazu a okolí trati bylo v podstatě nezničitelné. Částice (prach, štěrk, bláto) neměl. Remake může jít výrazně dál. Godot 4.7 na to má většinu stavebních kamenů: fyziku Jolt, soft body, GPU částice s kolizemi a decaly. Zbytek se postaví vlastními skripty, bez placených doplňků (D-012).

## 1. Jak to řeší moderní hry

| Hra / technologie | Přístup | Výsledek | Náročnost |
| --- | --- | --- | --- |
| BeamNG.drive | Celé auto je síť uzlů a pružin (node-beam), simulovaná ve vysoké frekvenci | Nejrealističtější deformace, ohyb rámu, utržené nápravy | Velmi vysoká, CPU náročné, v Godotu jen vlastní implementací |
| Wreckfest (Bugbear) | Deformace meshe podle místa a síly nárazu + strukturální zóny + odpadávající díly | Velmi přesvědčivé, výkonné pro mnoho aut | Střední, nejlepší vzor pro tento projekt |
| FlatOut (Bugbear) | Okolí z mnoha fyzikálních objektů: pneumatiky, ploty, sudy, hromady dřeva | Okolí reaguje na každý náraz | Nízká až střední |
| Burnout | Deformace meshe + dramatické zpomalené záběry | Efektní nehody | Střední |
| Battlefield (Frostbite), Unreal Chaos, Havok | Předem rozbité (pre-fractured) modely, kusy se uvolňují podle síly a „polí“ | Destrukce budov a objektů | Střední, hlavně příprava assetů |
| Teardown | Voxely, vše rozbitné | Úplná destrukce | Jiný typ hry, nevhodné |

**Závěr:** pro Stuttgart Speed je nejvhodnější přístup „Wreckfest + FlatOut“: deformace meshe auta se strukturálními zónami a hodně fyzikálních objektů kolem trati.

## 2. Poškození auta

### Vrstvy (rozšiřuje docs/analysis.md, kap. 5)

1. **Deformace meshe podle nárazu.** V místě kontaktu se vrcholy posunou ve směru impulzu. Síla klesá se vzdáleností (např. Gaussova křivka) a má limit podle tuhosti zóny.
2. **Deformační klec (lattice).** Místo posouvání tisíců vrcholů se deformuje hrubá klec (desítky bodů spojených pružinami) a vizuální mesh se podle ní přetváří (FFD / skinning). Výhody: plynulý tvar, rozumný výkon, jde i o „zjednodušený BeamNG“ jen pro auto hráče.
3. **Strukturální zóny.** Předek, zadek, boky, střecha, každá s tuhostí a „zdravím“. Tvrdé části (sloupky, rám) se deformují méně než blatníky a kapota.
4. **Odpadávající díly.** Nárazníky, kapota, dveře, zrcátka, spoilery jako samostatná tělesa připojená kloubem. Kloub se po překročení prahu impulzu nebo po nahromaděném poškození rozpojí (logika ve skriptu, sledování impulzů). Uvolněný díl je běžné fyzikální těleso s kolizí.
5. **Vážné následky** (utržení kola apod.) řeší přijatý nápad IDEA-006 (`severe-damage-wheel-loss.md`), tento nápad na něj navazuje.
6. **Dílčí poškození:** pootevřená kapota, viklající se nárazník (kloub s volností), praskající sklo (textura prasklin → při silném nárazu výměna za střepy a částice).
7. **Vizuál povrchu:** odřený lak a škrábance přes masku ve shaderu (vertex color nebo textura poškození), ohnutá kola, rozbitá světla.
8. **Mechanika:** výkon, chlazení, řízení, zavěšení, aerodynamika podle zón (beze změny oproti analýze).

### V Godotu
- Deformace: `ArrayMesh` / `MeshDataTool` na CPU pro okamžitý náraz, nebo posun ve vertex shaderu podle textury deformace (levnější, ale kolize se nemění).
- Kolize auta se po deformaci aktualizuje jen hrubě (konvexní obaly per zóna), ne přesným meshem.
- Pro plnou simulaci typu BeamNG by byla potřeba vlastní GDExtension v C++ a jen pro auto hráče. Doporučení: až jako experiment, ne základ.
- Příprava modelů (rozdělení na díly, zóny, klec) navazuje na Blender pipeline v IDEA-003.

## 3. Ničitelné okolí trati

| Objekt | Řešení | Chování |
| --- | --- | --- |
| **Svodidla** | Segmenty lan / plechů na sloupcích. Plech jako mesh ohýbaný podél deformované křivky (spline deformace) | Ohnou se v místě nárazu, sloupky se vyvrátí, při silném nárazu se segment utrhne a odletí |
| **Zídky (kamenné, cihlové)** | Předem rozbité (pre-fractured) moduly: celý model se při nárazu nad prahem vymění za kusy | Kameny a cihly se rozsypou, zbytek zídky stojí |
| **Dřevěné ploty, sloupky, cedule, kužely, sudy, balíky slámy, pneumatiky** | Jednoduchá fyzikální tělesa, „spí“, dokud do nich nikdo nenarazí | Odlétají, převalují se (FlatOut styl) |
| **Lampy, dopravní značky** | Kloub u paty, při nárazu se ohnou nebo ulomí | Ohnutý sloup zůstane šikmo |
| **Vlajky, prapory, transparenty** | Mírný vítr vertex shaderem (levné). Při nárazu nebo blízkém průjezdu výměna za `SoftBody3D` (látka) | Vlají ve větru, při nárazu se strhnou a zachytí na autě nebo spadnou |
| **Plachty stánků, markýzy, záclony v oknech** | `SoftBody3D` s ukotvenými body, jen v blízkosti hráče | Rozvlní se průjezdem, utrhnou se |
| **Křoví, nízké větve, rákos** | Vertex shader s ohybem podle pozice auta (interakční maska) | Ohnou se a vrátí, uvolní se listí (částice) |
| **Sklo (výlohy, budky)** | Výměna za střepy + částice | Rozbije se |

### Pravidla výkonu
- Rozbitné objekty jsou ve výchozím stavu statické nebo „spící“ a stávají se fyzikálními až při nárazu.
- Kusy po rozbití po čase zmizí (fade) nebo zamrznou jako statické. Limit počtu aktivních kusů (pool).
- Soft body a látky simulovat jen v okolí kamery, jinak shader.
- Fyzikální vrstvy: kusy nekolidují samy se sebou, jen s autem a terénem.

### Nástroje
- **Předem rozbité modely:** Blender, doplněk Cell Fracture (Voronoi), skriptovatelné (IDEA-003).
- **Rozbíjení za běhu – vlastní implementace** (bez placených doplňků, D-012):
  - Voronoi řez meshe v GDScriptu nebo C# (náhodné body uvnitř objektu → řez rovinami → uzavřené kusy s víčky), výpočet předem při načtení trati a uložení do cache, aby nezdržoval při nárazu.
  - Jednodušší varianta pro většinu objektů: předem rozbité modely z Blenderu (Cell Fracture, součást Blenderu zdarma), za běhu se jen vymění celý objekt za připravené kusy.
  - Pool kusů, limit aktivních těles, postupné zmizení.
  - Bezplatné open-source doplňky (MIT apod.) z Godot Asset Library lze použít jako referenci nebo základ po kontrole licence.
- **Látky:** `SoftBody3D` ([dokumentace Godot](https://docs.godotengine.org/en/stable/tutorials/physics/soft_body.html)). Podporu a výkon soft body s fyzikou Jolt je potřeba ověřit prototypem.

## 4. Částice

### Co Godot 4 nabízí
`GPUParticles3D` ([přehled funkcí](https://godotengine.org/article/improvements-gpuparticles-godot-40)):
- velké množství částic počítaných na GPU,
- **kolize** s koulí a kvádrem (pohyblivé), s **SDF** zapečeným z geometrie a s **výškovým polem** pro velký terén, které může následovat kameru ([3D particle collisions](https://docs.godotengine.org/it/4.4/tutorials/3d/particles/collision.html)),
- **atraktory** (koule, kvádr, vektorové pole),
- **sub-emitory** (částice vypouští další částice, např. kámen → prach při dopadu),
- stopy (trails), turbulence, emise z meshe.

Doplňkově **`Decal`** pro stopy na povrchu (smyky, bláto, olej, škrábance na asfaltu) a shadery pro mokré povrchy.

### Efekty

| Efekt | Spouštěč | Řešení |
| --- | --- | --- |
| **Štěrk a kamínky** | Kolo na štěrku, prokluz | Těžké částice s kolizí s terénem, odskok, sub-emitor prachu. Zvuk cvakání o podvozek (IDEA-004) |
| **Prach** | Prašný povrch, krajnice, rychlost | Velké měkké billboardy, dlouhá životnost, vítr, turbulence. Oblak za autem v suchém počasí |
| **Kouř z pneumatik** | Prokluz, smyk, brzdění v zablokování | Bílý kouř podle intenzity prokluzu, souvisí s modelem pneumatik |
| **Bláto** | Mokrá hlína, louka | Tmavé kapky s kolizí + **decal na karoserii** (auto se postupně ušpiní, maska ve shaderu laku) |
| **Louže a voda** | Průjezd louží | Louže jako plochy v terénu (shader s odrazem a vlnami), při průjezdu sprška kapek, vlny na hladině, krátké zpomalení (odpor) |
| **Listí** | Průjezd kolem stromů, keřů, náraz do křoví, proud vzduchu za autem | Lehké částice s vířením (turbulence, atraktor za autem), padání ve vzduchu |
| **Tráva a hlína** | Vyjetí mimo silnici | Kousky trávy a hlíny + decal vyjeté stopy v trávě |
| **Jiskry** | Kontakt kovu s asfaltem, svodidlem, zídkou | Rychlé světelné částice se stopou, krátká životnost |
| **Střepy, úlomky** | Náraz | Sub-emitor při rozbití skla a dílů |
| **Pára, kouř motoru** | Poškozený předek (chlazení) | Pára z masky, později tmavý kouř, souvisí s mechanikou poškození |
| **Výfuk** | Studený motor, ubrání plynu | Lehký kouř, záblesky při prskání |
| **Déšť, sprška od kol** | Počasí | Sprška za koly na mokru, kapky na čelním skle v kokpitu |

### Povrch jako zdroj
Každý povrch trati má materiál (asfalt, štěrk, tráva, hlína, sníh, voda) a ten určuje: částice, zvuk, přilnavost pneumatik a decaly. U tratí podle reálných map (IDEA-001) jde materiál odvodit z dat OpenStreetMap.

### Výkon
- Částice počítá GPU, ale průhledné billboardy (prach, kouř) zatěžují vykreslování. Omezit velikost a počet podle nastavení kvality.
- Emitory jen u aut blízko kamery, vzdálená auta zjednodušeně.
- Decaly s omezeným počtem a postupným mizením.

## 5. Doporučené pořadí

1. **Prototyp (D-009):** zóny poškození + odpadávající díly + jiskry a kouř z pneumatik. Hned prověří fyziku a kolize.
2. Deformace meshe auta (nejdřív přímý posun vrcholů, pak případně klec).
3. Fyzikální objekty kolem trati (kužely, sudy, cedule, ploty) a svodidla.
4. Povrchové částice (štěrk, prach, tráva) a decaly stop.
5. Bláto na karoserii, louže, listí.
6. Látky (vlajky, plachty) a předem rozbité zídky.
7. Experiment: klecová deformace nebo node-beam pro auto hráče.

## Rizika

- Výkon na Macu při mnoha fyzikálních tělesech a průhledných částicích, nutné profilování a nastavení kvality.
- Deformovaný mesh vs. kolize: vizuál a fyzika se mohou rozejít.
- Realistické poškození může zkazit hratelnost. Nutná volba realistické / arkádové poškození (D-003: sim-cade).
- Soft body a látky s Jolt: ověřit stabilitu a výkon.

## Další kroky (pokud se nápad přijme)

- [ ] Prototyp odpadávajícího dílu (nárazník) s kloubem a prahem impulzu
- [ ] Prototyp deformace meshe v místě nárazu na původním autě
- [ ] Testovací scéna: svodidlo, zídka, kužely, vlajka; měření výkonu
- [ ] Systém materiálů povrchu (částice, zvuk, přilnavost)
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`

## Zdroje

- [Godot – Using SoftBody3D](https://docs.godotengine.org/en/stable/tutorials/physics/soft_body.html)
- [Godot – Improvements to GPUParticles in Godot 4.0](https://godotengine.org/article/improvements-gpuparticles-godot-40)
- [Godot – 3D Particle collisions](https://docs.godotengine.org/it/4.4/tutorials/3d/particles/collision.html)
