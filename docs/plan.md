---
type: plan
updated: 2026-10-29
current_phase: 1
phases:
  - id: 1
    name: "Data z originálu"
    status: in_progress
    gate: "Fyzika všech aut v JSON, textury v PNG, jedno auto v glTF jako vizuální reference"
  - id: 2
    name: "Prototyp jízdy"
    status: todo
    gate: "Jedno původní auto na jedné původní trati (D-009), jízdní pocit, kolize a poškození srovnatelné s originálem spuštěným přes Wine"
  - id: 3
    name: "Opravený původní obsah"
    status: todo
    gate: "Všech 44 aut, 15 tratí a zvuky originálu hratelné, bez překryvů ploch, děr a chyb, které ukazuje kontrola modelů (D-009, D-016)"
  - id: 4
    name: "Hra a atmosféra"
    status: todo
    gate: "Hratelná verze na Macu: rychlý závod, mise, kariéra, soupeři, provoz, policie"
  - id: 5
    name: "Vylepšený a doplněný obsah"
    status: todo
    gate: "Auta, tratě a zvuky originálu vylepšené a doplněné (textury, detail, díly pro poškození, zvuky prostředí), opakovatelně z nástrojů (D-009, IDEA-003)"
  - id: 6
    name: "Případné veřejné vydání"
    status: todo
    gate: "Jen pokud se o vydání rozhodne: fiktivní auta, vlastní tratě a zvuky, bez obsahu originálu (D-001, D-004, D-005, D-007)"
---

# Plán

Nejdřív se ověřují rizika (data, jízdní pocit), teprve potom se staví obsah.

**Pořadí (D-009):** fáze 2 ověří na jednom původním autě a jedné původní trati, že migrovaná hra funguje a je hratelná. Fáze 3 opraví všechna původní auta, tratě a zvuky, fáze 5 je vylepší a doplní. Opravy a vylepšení se zapisují jako pravidla a skripty v `tools/`, výstupy zůstávají v `decomposed/`. Vlastní tratě a fiktivní auta (fáze 6) jsou jen pro případné veřejné vydání (D-004, D-005).

## Fáze 1 – Data z originálu

- [x] Inventura instalace ([data-inventory.md](data-inventory.md))
- [x] Dekompresor EA RefPack ([tools/archives.py](../tools/archives.py)), ověřený na autě i trati
- [x] Částečné dekódování `.sim` ([formats/sim.md](formats/sim.md))
- [x] Zkopírovat assety hry do `sources/`
- [x] Převod všech `.sim` do `decomposed/GameData/Simulation/cars.json`
- [ ] Určit zbývající pole `.sim` (porovnáním aut s odlišnými vlastnostmi)
  - [x] Porovnání dvojic a hypotézy ([formats/sim.md](formats/sim.md#porovnání-dvojic))
  - [x] Párování s parametry NFS4 `carp.txt` podle Velocity/HighStakesRE, korelace a postřehy pro jízdní model ([formats/sim.md](formats/sim.md#hypotézy-z-nfs4--zdůvodnění))
  - [x] Význam polí z `Porsche.exe` (Ghidra + REA, [IDEA-012](../ideas/exe-analysis-rea-ghidra.md), [formats/sim.md](formats/sim.md#analýza-porscheexe-ghidra))
  - [x] Srovnání našeho jízdního modelu s originálem a postup zpracování dat ([driving-model.md](driving-model.md))
  - [x] Pole s fyzikální jednotkou v prototypu podle exe: 0x104 brzdy v m/s², 0x108 podíl brzd, 0x058 účinnost převodu, 0x098 brzdění motorem
  - [x] Vyvážení náprav z 0x0F0: `rear_grip` = (1 − 0x0F0) / 0x0F0 (D-027)
  - [ ] Převést kalibrací 0x0F4 (přilnavost) a 0x10C/0x110 (přítlak ×0,001 × rychlost) a ověřit testy ([návrhy](formats/sim.md#návrhy-testů-v-prototypu))
  - [ ] Přejmenovat v `tools/sim_dump.py` ověřená pole z `unknown` na pojmenované klíče
  - [x] Rejd řízení zmenšený s rychlostí podle principu 0x0FC, vzorec z rozvoru, μ a vrcholu směrového úhlu (D-026)
  - [x] Jednotka 0x0FC (rejd v 1/256 otáčky), tvar boční síly a těžiště ve stáčení z exe ([formats/sim.md](formats/sim.md#analýza-porscheexe-ghidra))
  - [ ] Pole AI 0x13C–0x144
  - [ ] Ověřit hypotézy v originále přes Wine
- [x] Převod textur FSH → PNG ([tools/fsh2png.py](../tools/fsh2png.py))
- [x] Parser geometrie auta v CRP → glTF (podle OpenNFS), všech 44 aut ([tools/crp2gltf.py](../tools/crp2gltf.py))
- [x] Převod CSV nastavení AI do JSON ([tools/ai_csv2json.py](../tools/ai_csv2json.py))
- [x] Exportér tratí CRP → glTF + data silnice `SimD`, zatím skidpad ([tools/track2gltf.py](../tools/track2gltf.py))
- [x] Exportér tratí: farmland (Normandie), úseky `SimD` a start/cíl z `_fstart.scn`
- [x] Objekty kolem trati: umístění z matice `tr`, značka v `Base` 0x44, vlastnosti z `animdefs.txt`, díly typu 4 a bez indexů ([formats/scn.md](formats/scn.md))
- [x] Exportér tratí: převod všech 15 tratí, terén `WOBJ … _SECONDARY` ve skupině terrain
- [x] Kontrola normál a děr všech aut a tratí ([tools/mesh_check.py](../tools/mesh_check.py), [model-check.md](model-check.md), D-016): orientace podle normál, terén nahoru
- [x] Varianty aut ze stylů `.tpg` (D-022): díly a textury každé varianty, f901 s karoserií, kabriolety a turba; kontrola všech 113 stylů kamerou kolem auta na skidpadu (`car_orbit_test`) a překryvů dílů (`mesh_check.py`), opravené zdvojené díly a z-fighting vnitřních panelů víek
- [ ] Spáry mezi silnicí a terénem a vedlejší úseky `SimD` mimo geometrii (varování z kontroly)
- [x] Exportér tratí: světelné záře a zdroje částic z `ef` (`_lights.json`), vzhled září z `flare.dat` ([tools/flare.py](../tools/flare.py))
- [ ] Exportér tratí: význam šířek `SimD`, spojení úseků (`.jnc`), předlohy z úloh (`_stNN.scn`), animace objektů, zdroje částic a stíny `ef`, `<trať>.map`
- [x] Ideální stopy soupeřů `.lsp` a klíče `.key` do `<trať>_ai.json` ([tools/ai_lines.py](../tools/ai_lines.py), [formats/lsp.md](formats/lsp.md)), profily `.ais` a řízení `TRAFCFG` ([tools/ais2json.py](../tools/ais2json.py), [formats/ais.md](formats/ais.md))
- [ ] Ověřit v exe význam `.key`, tabulek `.ais` A/B a rozdíl stop `.lsp` 0/1 (D-023)
- [ ] Spustit originál na Macu přes Wine jako referenci

## Fáze 2 – Prototyp jízdy

- [x] Godot 4.7 projekt, Jolt ([game/](../game/README.md)), běží na Metalu, automatický jízdní test
- [x] Vybrat původní auto a původní trať pro prototyp (D-009): 356 A coupe 1.6 na skidpadu
- [x] Import auta z `decomposed/` (glTF) a parametrů z `cars.json` (načítání za běhu)
- [x] Import vybrané trati z `decomposed/` (glTF + data silnice `SimD`), kolize z geometrie
- [x] Skutečná trať pro jízdní pocit: farmland (Normandie), start na startovní čáře originálu
- [x] Raycast podvozek, model pneumatik, motor a převodovka z dat JSON (pneumatiky: skluz, rotace kol, setrvačnost motoru; 0–100 km/h 15,8 s proti reálným ~16 s)
- [ ] Doladit pneumatiky a řízení proti originálu přes Wine (přilnavost 0x0F4 a setrvačnost 0x058 jsou hypotézy), asistent řízení pro klávesnici hotový; ABS naladěné podle ruční jízdy proti originálu, zadní přilnavost z 0x0F0 (D-027) (smyk zádí při brzdění v zatáčce); klávesy s náběhem pedálů a volantu jako v tehdejších hrách; kontrola trakce, spojka při rozjezdu, turbodíra a samosvor závodních aut (D-015); asistenti, zvuk a diagnostika se přepínají v menu (D-017)
- [x] HUD: kulatý rychloměr (s počítadlem km) a otáčkoměr v klasickém stylu (kreslené procedurálně, stupnice z dat auta, ručička s tlumenou setrvačností); otáčky motoru při řazení klesají a stoupají plynule (spojka)
- [x] Mechanické válečkové počitadlo kilometrů (D-013): vzdálenost z poháněných kol, nájezd uložený pro každé auto, vzhled podle éry auta
- [x] Díly aut z originálu (D-024): katalog `nfs5.prt`, seznamy dílů v `nfs5.car`, vzorce z exe; v menu Stock / Sport a pneumatiky sériové / slick / do deště ([formats/prt.md](formats/prt.md))
- [x] Kolize s objekty kolem trati: sražitelné značky (dynamická tělesa s původní hmotností), ostatní statické
- [x] Poškození auta: zóny `dz` a posuny `vt` 0x8000 jako blend shapes, náraz podle impulsu, následky (sbíhavost a přilnavost kol, výkon motoru, odpor vzduchu, rejstřík řízení)
- [x] Odpadající díly (světla, značka, výfuk, zástěry) a kola: házení od 50 % rohu, upadnutí při 100 % rohu i boku
- [x] Díly na pantech: kapota / kryt motoru se uvolní nad 50 % předku / zádi a utrhnou při nárazu z 100 km/h, dveře se uvolní a v zatáčkách otevírají
- [x] Zvuk motoru a auta ze zvuků originálu (lokálně, D-011): smyčky podle otáček a plynu, pneumatiky, vítr, nárazy, díly ([formats/bnk.md](formats/bnk.md))
- [ ] Naladit poškození a jeho následky proti originálu (Wine); textury poškození; další vážné následky ([IDEA-006](../ideas/severe-damage-wheel-loss.md))
- [x] Srovnávací jízdy s originálem (ruční jízda na druhém počítači 17. 10. 2026): hratelné a podobné originálu
- [x] Druhé auto a trať: 935 Moby Dick v Monte Carlu, nastavení odvozená z dat místo ladění na 356 (test na rovině `straight_test`)
- [x] Hlavní menu prototypu: výběr auta a trati, Play, Esc zpět do menu, poslední výběr uložený
- [x] Barva laku z palety originálu vedle výběru auta (D-020)
- [x] Noční světla tratí z originálu: záře `ef` a `flare.dat`, blikající výstražná světla, tunelová a pouliční světla (D-021, [formats/flare.md](formats/flare.md))
- [x] Závod od startu do cíle (D-025): odpočet 3-2-1, stopky, kontrolní body, průjezd cílovou čárou, nejlepší čas; kamera při startu obletí auto
- [x] Efekty (D-028): stopy pneumatik na silnici při smyku, prach a kousky země za koly mimo silnici v barvě terénu, jiskry při nárazu a drhnutí (`effects_test`)
- [ ] Efekty: listí a tráva podle trati, povrch z `df` článků CRP, jiskry jen od kovových a kamenných překážek
- [ ] Okruhy s počítáním kol (Monte Carlo, `lap` v `_road.json`), mezičasy, zvuk odpočtu
- [ ] Rozhodnout definitivně o enginu (D-002)

## Fáze 3 – Opravený původní obsah

- [ ] Kontrola překryvů ploch v `tools/mesh_check.py`; výsledky v [model-check.md](model-check.md)
  - [x] Pořadí vrcholů dílů kreslených jen z lícové strany, vrstvené díly bez odsazení a zapuštěné (29. 10. 2026)
  - [x] Vnitřní panely víek otočené po souvislých kusech, varianty `TrunkIn1` a víko f996 (všech 44 aut bez chyby)
  - [ ] Pořadí vrcholů dalších jednostranných dílů (motor, zrcátka, interiér, zavazadlový prostor)
  - [x] Odsazení vrstev o 1 mm v převodníku (světla, stíny kol, obtisky), i u cílů poškození (30. 10. 2026, podnět: blikající zadní světla 944; zbývá 7 drobných dvojic)
  - [ ] Hloubka protnutí dílů (bez dílů, které se jen dotýkají hranou)
- [ ] Auta: opravy jako pravidla v `crp2gltf.py` a `materials.gd` (světla a odznaky na laku, interiér / exteriér, vnitřní a vnější sklo, okna, dveře a víka), přegenerovat všech 44 aut a ověřit kontrolou a snímky za autem
- [ ] Tratě: spáry silnice a terénu, díry, orientace ploch, objekty kolem trati u všech 15 tratí
- [ ] Zvuky: sady motorů pro všechna auta (`engine.json`), chybějící nebo vadné smyčky, hlasitosti
- [ ] Všechna auta a tratě v menu hratelné (kolize, start/cíl, světla, poškození)

## Fáze 4 – Hra a atmosféra

- [ ] Rychlý závod, mise testovacího jezdce, kariéra
- [x] Rozbor AI originálu, srovnání s dnešními hrami a plán ([opponents.md](opponents.md), D-026)
- [x] Soupeři B: řidič AI pro jedno auto (`Car.auto_drive` bez klávesových ramp, `scripts/ai_driver.gd`, sdílená silnice `scripts/road.gd`, stopa `.lsp`, rychlostní profil, návrat na stopu); `ai_drive_test`: 356 A farmland 5:57, 935 a 356 A dvě kola Monte Carla (stopa 1) bez resetu, doteku a smyku nad 12° (po prvním vyzkoušení ve hře doplněno brzdění podle kruhu přilnavosti a ubírání plynu v zatáčce a ve smyku) ([game/README.md](../game/README.md))
- [x] Soupeři C1: startovní rošt (3 soupeři ve hře, `--opponents=0..7`, stejné auto v jiných barvách, odpočet a restart pro všechny, odstup od auta před sebou); `grid_test` se 3 i 7 soupeři bez doteku
- [ ] Soupeři C2: pořadí a cíl pro každé auto, pozice v HUD, výsledky; měření FPS v okně s 1 / 3 / 7 soupeři
- [x] Soupeři D1: objetí pomalého nebo stojícího auta (posun stopy na stranu s místem, těsně, dotyk dovolen; bez místa opatrné vytlačení pod prahem poškození); `pass_test` (zaparkované, šikmé a napříč stojící auto, zastavení před kolonou)
- [ ] Soupeři D: racecraft (předjíždění v jízdě, obrana, prostor) a osobnosti z `prsonal`
- [ ] Soupeři E: síla AI v menu, volitelná gumička
- [ ] Provoz, policie
- [ ] Zvuky originálu pro všechny situace (soupeři, provoz, policie, prostředí)

## Fáze 5 – Vylepšený a doplněný obsah

Postup podle [IDEA-003](../ideas/asset-enhancement-ai-blender.md). Každé vylepšení je skript v `tools/`, výstup v `decomposed/`.

- [ ] Textury: odstranění ditheringu, AI zvětšení, normálové mapy a drsnost
- [ ] Geometrie aut: normály a vyhlazení, zkosení hran, detail tam, kde chybí
- [ ] Díly pro poškození: oddělené nárazníky a blatníky s vnitřními plochami ([IDEA-006](../ideas/severe-damage-wheel-loss.md))
- [ ] Tratě: detail okolí, vegetace, předměty kolem trati
- [ ] Zvuky: vylepšené smyčky motorů, zvuky prostředí ([IDEA-004](../ideas/sound-engines-ambience.md))
- [ ] Řidič v kokpitu ([IDEA o řidiči](../ideas/driver-in-cockpit.md))

## Fáze 6 – Případné veřejné vydání

Jen pokud se o vydání rozhodne ([IDEA o distribuci](../ideas/distribution-bring-your-own-data.md)).

- [ ] Sada fiktivních aut podle ér (D-004)
- [ ] Vlastní tratě ve stylu originálu (D-005, [IDEA z reálných map](../ideas/real-map-tracks.md))
- [ ] Vlastní zvuky motorů ze samplů (D-007)
- [ ] Veřejné vydání bez obsahu originálu

## Rizika

| ID | Riziko | Pravděpodobnost | Dopad | Záložní plán |
| --- | --- | --- | --- | --- |
| R-1 | Jízdní pocit neodpovídá originálu | střední | vysoký | Porovnávat s originálem přes Wine, ladit podle `.sim` |
| R-2 | Rozsah přeroste možnosti jednoho člověka | vysoká | vysoký | Opravy a vylepšení jako obecná pravidla a dávkové skripty pro všechna auta a tratě naráz; malý rozsah režimů |
| R-3 | Zbývající pole `.sim` nejdou určit | střední | nízký | Doplnit z reálných technických údajů |
| R-4 | Výroba vlastních tratí je pomalá (jen fáze 6) | vysoká | střední | Procedurální silnice podél křivky, sdílené sady objektů |
| R-5 | Ruční úpravy v `decomposed/` přepíše další převod | střední | střední | Opravy jen jako pravidla v nástrojích, doplňky ve vlastní složce, kterou převodník skládá s původními daty (D-009) |
