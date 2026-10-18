---
type: idea
id: IDEA-010
title: "Řidič v kabině vozu"
status: idea            # idea | accepted | rejected | done
created: 2026-10-18
related: [D-004, D-008, D-009, D-012, IDEA-003, IDEA-009]
tags: [driver, cockpit, interior, animation, ik, character]
---

# Řidič v kabině

Díky průhledným sklům (IDEA-009) je vidět, že v autě nikdo nesedí. Řešení: postava řidiče, která drží volant a reaguje na řízení.

## 1. Řidič v datech originálu (pro prototyp, D-009)

Původní modely aut řidiče obsahují. `tools/crp2gltf.py` ho ve výchozím stavu vynechává jako „variantní díl“ (příznak `BIL_DRIVER`); přepínač `--all` ho vyexportuje.

Díly v modelu 356 A (export `--all`, 18. 10. 2026):

| Díl | Počet | Pravděpodobný význam (ověřit) |
| --- | --- | --- |
| `DriverBody1–10` | 10 | Varianty těla / oblečení (styly nebo éry) |
| `LODDriver1–10` | 10 | Zjednodušené verze pro větší vzdálenost |
| `LeftArm1–4`, `RightArm1–4` | 2× 4 | Polohy paží podle natočení volantu (originál pravděpodobně přepínal pevné pózy) |
| `LeftHand1–2`, `RightHand1–2` | 2× 2 | Ruce |
| `Legs1–4` | 4 | Nohy |

Textury: `suit.fsh` (kombinéza), `head.fsh` (hlava), viz `.tpg`. Patch originálu zmiňuje opravu „driver animation“, řidič byl tedy animovaný.

Se stejným přepínačem se exportují i chybějící části interiéru: `Seat1`, `Steer1` (volant), `Dash1`, `Needle1a/2a` (ručičky budíků), `DecalGauge1`, `Interior1–2`, `InteriorRoof1–2`, `InteriorGlass`, `DoorIn`, varianty střechy kabrioletu (`Cabrio*`) a další.

### Postup pro prototyp
1. Rozšířit export: místo vše-nebo-nic (`--all`) vybírat díly podle typu (interiér, řidič, varianta stylu). Výchozí sada: základní karoserie + interiér + jeden řidič (vybraná varianta těla, paže, ruce, nohy).
2. Určit význam variant (`DriverBody` 1–10, `Arm` 1–4) porovnáním v Blenderu nebo v Godotu, zapsat do `docs/formats/`.
3. V Godotu: volant (`Steer1`) otáčet podle natočení kol; paže přepínat mezi pózami 1–4 podle úhlu volantu (jako originál), nebo je natáčet kolem ramene.
4. Ručičky budíků (`Needle*`) napojit na otáčky a rychlost, pokud palubní deska v kokpitu není řešená jinak.
5. Vzdálená auta: `LODDriver` nebo řidiče skrýt.

Vše jen lokálně v `decomposed/` (D-008).

## 2. Volně dostupné modely postav (pro vlastní obsah, D-004)

| Zdroj | Licence | Poznámka |
| --- | --- | --- |
| **MakeHuman** | Exportované modely CC0 | Generátor realistických postav, vlastní proporce, oblečení, export s kostrou (rig) |
| **Mixamo** (Adobe) | Zdarma s účtem Adobe, použití ve hrách bez poplatků (ověřit aktuální podmínky) | Postavy + automatický rig + knihovna animací, včetně „sedící“ póz |
| **Quaternius**, **Kenney** | CC0 | Stylizované low-poly postavy s rigem |
| **Sketchfab** | Podle modelu (CC0, CC-BY; vyhnout se NC) | Hledat „racing driver“, „pilot helmet“; kontrolovat licenci a topologii |
| **Blender Studio** | Většinou CC-BY | Kvalitní postavy z filmových projektů |

Řidiče stačí od pasu nahoru (nohy nejsou přes sklo vidět), což zjednoduší model a ušetří výkon.

### Vzhled podle éry
| Éra | Vybavení |
| --- | --- |
| 50.–60. léta | Kožená čepice nebo otevřená přilba, brýle, šála / košile, kožené rukavice |
| 70.–80. léta | Otevřená nebo integrální přilba, kombinéza |
| 90. léta | Integrální přilba, moderní kombinéza, HANS není (až po roce 2000) |
| Silniční auta | Bez přilby, civilní oblečení |

## 3. Animace

- **Ruce na volantu:** inverzní kinematika (IK) rukou k úchopovým bodům na volantu. Godot 4.7 má IK modifikátory kostry (`SkeletonModifier3D`; konkrétní dostupné uzly ověřit v dokumentaci 4.7). Jednodušší alternativa: předpřipravené pózy pro několik úhlů volantu a míchání mezi nimi.
- **Hlava:** natočení do zatáčky (pohled na apex), pohupování podle přetížení (boční a podélné g z telemetrie).
- **Tělo:** mírný náklon v zatáčkách a při brzdění podle g.
- **Řazení:** pravá ruka na řadicí páku při přeřazení (krátká animace).
- **Nehoda:** cuknutí hlavy a těla při nárazu podle impulzu.

## 4. Kokpitový pohled
- V pohledu z kokpitu skrýt hlavu (kamera je v hlavě), ruce a volant ponechat.
- Pozice kamery řidiče je v `.tpg` (`drivercampos`, `drivercamrotstyle*`), lze ji převzít.

## Další kroky (pokud se nápad přijme)

- [ ] Výběrový export dílů v `tools/crp2gltf.py` (interiér, řidič, styl) a export 356 A a 935 s řidičem a interiérem
- [ ] Určit význam variant `DriverBody` a `Arm`
- [ ] Volant a paže podle řízení v Godotu, řidič viditelný přes sklo
- [ ] Později: vlastní řidič (MakeHuman / Mixamo) s IK pro fiktivní auta
- [ ] Zapsat jako rozhodnutí do `docs/decisions.md`
