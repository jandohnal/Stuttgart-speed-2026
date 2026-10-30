---
type: analysis
title: "Soupeři: data originálu, srovnání a plán"
updated: 2026-10-29
related: ["formats/lsp.md", "formats/ais.md", "formats/ai-csv.md", "decisions.md#d-026-soupeři-jezdí-stejnou-fyzikou-jako-hráč-po-stopě-z-originálu", "../ideas/llm-opponent-personas.md"]
---

# Soupeři: data originálu, srovnání a plán

## 1. Jak to dělal originál (z dat)

AI soupeřů v NFS: Porsche 2000 stojí na čtyřech vrstvách. Všechny jsou v datech a jsou převedené do `decomposed/`.

| Vrstva | Data | Co obsahují |
| --- | --- | --- |
| **Stopa** | `Track/racer/work/<trať>0.lsp`, `1.lsp` ([lsp.md](formats/lsp.md)) | Dvě předpočítané ideální stopy na trať, bod pro každý řez silnice. Na rovinkách často ve středu, v zatáčkách posun o 1–4 m. |
| **Tempo** | `.ais` tabulky A/B ([ais.md](formats/ais.md)), `<trať>_forward/_backwards.key`, `.sim` 0x13C–0x144 | Pro rodinu aut dohled podle rychlosti a (hypotéza) rychlostní limit podle ostrosti zatáčky; po úsecích trati klíče s neznámou jednotkou; násobiče pro konkrétní verzi auta. |
| **Řízení** | `AI/TRAFCFG.DAT` ([ais.md](formats/ais.md#trafcfgdat-a-trafcfgdes)) | Auto AI se **nesimuluje jako auto hráče**: kaskáda regulátorů posouvá auto na boční polohu stopy (poloha → boční rychlost → boční zrychlení) a natáčí ho (úhel → úhlová rychlost → úhlové zrychlení). Druhá, měkčí sada platí „mimo kontrolu“ po nárazu nebo smyku. |
| **Chování** | `AI/*.csv` ([ai-csv.md](formats/ai-csv.md)) | 9 osobností × 14 vlastností 0–3 (blokování, odstřižení, dohled, kličkování, brzdění, vztek, řidičská dovednost, zrychlení, četnost chyb, zatáčky, přesnost stopy, najíždění zezadu, agresivita, odolnost proti policii); skriptované reakce na akce hráče (předjetí, blokování, troubení); gumička ×1,25…×0,82 podle vzdálenosti od hráče (±600 m); rozptyl tempa osobností 0,958–1,0; rozestupy v koloně A–F (90–470 m za vedoucím); obtížnost 0,8 / 0,975 / 1,03. |

Shrnutí: soupeř originálu je **„auto na kolejích“ s osobností**. Jede po předpočítané stopě, tempo mu určují tabulky a gumička ho drží poblíž hráče. Plnou fyziku dostane, až když ho něco vyhodí z kontroly. Na tehdejší procesory to bylo nutné a dávalo designérům přímou kontrolu nad průběhem závodu, ale soupeř nedělá stejné chyby jako hráč a gumička je znát.

Co ještě chybí ověřit v `Porsche.exe` (D-023): význam hodnot `.key`, tabulek `.ais` a rozdíl stop 0/1. Pro náš návrh to není blokující, stopy jsou ověřené.

## 2. Dnešní styly

| Hra / přístup | Jak řídí AI | Obtížnost a tempo | Poznámka |
| --- | --- | --- | --- |
| Assetto Corsa, ACC, rFactor 2 | Stejná fyzika jako hráč, spline stopy + rychlostní profil, regulátory volantu a pedálů | Posuvník síly AI v % a agresivity, bez gumičky | Férové, předvídatelné, laditelné jedním číslem |
| F1 (Codemasters) | Stejná fyzika, stopy pro předjíždění a obranu | Síla 0–110, volitelně adaptivní | Racecraft: souboj bok po boku, respekt prostoru |
| Forza Motorsport / Horizon | Stejná fyzika, Drivatar (profil podle chování skutečných hráčů) | Stupně obtížnosti, mírné dotahování v Horizonu | Osobnost z dat hráčů místo ručně psaných vlastností |
| Gran Turismo 7 (+ Sophy) | Klasická AI (často kritizovaná za „honičku“ ze zadu roštu); Sophy = posilované učení, jezdí na limitu a s etiketou | Sophy jen na vybraných tratích | RL je výborné, ale trénink je drahý a výsledek těžko laditelný |
| Need for Speed Heat / Unbound | Arkádová fyzika, silné dotahování (gumička) | Gumička skrytá v obtížnosti | Hráči ji kritizují: výsledek nezávisí na jízdě |
| Trackmania, Forza Rivals | Duchové (záznamy jízd) | Čas, který se dá porazit | Levné, férové, ale bez souboje |

Trendy: **stejná fyzika pro AI a hráče**, transparentní síla AI místo skryté gumičky, racecraft (soupeř nechá prostor, brání se, předjíždí po vnější i vnitřní), osobnost a rivalové jako vrstva nad řízením, ne jako „podvádění“ ve fyzice.

## 3. Možnosti Godotu 4.7 a našeho prototypu

- `Car` (`game/scripts/car.gd`) je `RigidBody3D` s raycast podvozkem, pneumatikami, převodovkou a poškozením. Převodovka je automatická. AI stačí dodat plyn, brzdu a volant: dnes je čte `_read_input` z `Input`, stačí oddělit zdroj vstupu.
- Kolize auto–auto, poškození a odpadající díly fungují pro každé `Car` samy (Jolt).
- Trať: řezy SimD v `_road.json` (pozice, směr, šířky, úseky a jejich napojení), `slice_ahead` v `main.gd`; ke každému řezu nově boční odchylka dvou stop v `<trať>_ai.json`. `Path3D`/`Curve3D` ani navigace Godotu nejsou potřeba.
- Výhled na ostatní auta: seznam aut seřazený podle řezu (levné), raycasty `PhysicsDirectSpaceState3D` jen na blízko.
- Výkon: fyzika auta je v GDScriptu, 120 Hz a 8 podkroků kol. 4–8 aut je třeba změřit dřív, než se postaví zbytek. Pojistky: méně podkroků u vzdálených aut; v krajním případě zjednodušený pohyb po stopě podle TRAFCFG pro auta daleko mimo záběr (jako originál).
- Bez placených doplňků (D-012). Godot RL Agents (MIT) je možnost na později, ne základ.

## 4. Srovnání a doporučení

| Oblast | Originál | Dnes | Stuttgart Speed |
| --- | --- | --- | --- |
| Fyzika AI | Regulátory polohy, plná fyzika až po kolizi | Stejná jako hráč | **Stejná `Car` fyzika**; zjednodušení jen jako LOD pro vzdálená auta, pokud to bude nutné kvůli FPS |
| Stopa | Předpočítané `.lsp` | Spline + optimalizace | `.lsp` z originálu v prototypu (D-009); pro vlastní tratě (fáze 3) stopu generovat z řezů (minimální křivost) |
| Rychlost | Tabulky `.ais`, `.key` | Profil z gripu a brzd | Rychlostní profil z dat našeho auta: v = √(μ·g·R) v zatáčkách, dopředný a zpětný průchod se zrychlením a `brake_decel_g`; `.ais` jen pro srovnání |
| Obtížnost | 3 stupně + gumička ±25 % | Síla AI v %, bez gumičky | Síla AI (podíl profilové rychlosti, přesnost stopy, rezerva brzdění) ve stupních 0,8 / 0,975 / 1,03 podle originálu; **gumička volitelná a mírná, ve výchozím stavu vypnutá** |
| Osobnost | 14 vlastností 0–3 | Agresivita, racecraft, Drivatar | Vlastnosti 0–3 převzaté jako parametry řidiče; reakce ze `SCRIPTS` později |
| Rozestupy | Kolona A–F kolem hráče | Volný závod | Volný závod; kolonu originálu ne (je to skrytá gumička) |

## 5. Plán implementace

Kroky jsou v [plan.md](plan.md) (fáze 1 data, fáze 4 soupeři).

**A. Data** – hotovo: `tools/ai_lines.py` (stopy a klíče), `tools/ais2json.py` (profily a TRAFCFG). Zbývá ověřit význam `.key`, `.ais` a stop 0/1 v exe.

**B. Řidič AI, jedno auto bez hráče** – hotovo 29. 10. 2026 (`game/scripts/ai_driver.gd`, výsledky v [game/README.md](../game/README.md)). Poznatky: samotný pure pursuit na limitu nedotáčí, pomohla zpětná vazba podle úhlové rychlosti; stopu `.lsp` nelze omezovat na šířku řezů, v Monte Carlu vede vedlejší ulicí až 26 m od nich. Při vyzkoušení ve hře se 356 v zatáčkách otáčela: brzdila v zatáčce a hned dávala plný plyn. Pomohlo brzdění plánované předem podle kruhu přilnavosti, brzda podle potřebného zpomalení a plyn omezený podle bočního zatížení a smyku. Test teď měří i doteky se zdmi (pod prahem poškození) a smyk. Stopa 0 v Monte Carlu vede u řezů 74–87 do zátarasu varianty monaco1, stopa 1 ne.
- `car.gd`: oddělit zdroj vstupu (`var driver`, `null` = hráč); AI zapisuje `throttle`, `brake`, `steer` přímo, bez klávesových ramp.
- `game/scripts/ai_driver.gd`: poloha na trati (sledování řezu dopředu, `slice_ahead` přesunout z `main.gd` do sdíleného skriptu silnice), pure pursuit na stopu s dohledem podle rychlosti, rychlostní profil z křivosti stopy, PI regulátor plynu a brzdy, zotavení (zaseknutí nebo mimo silnici → `reset_to` na nejbližší řez).
- Test `ai_drive_test`: 356 A dojede farmland od startu do cíle přes všechny kontrolní body bez resetu, 935 objede Monte Carlo.

**C. Závod se soupeři**
- Startovní rošt za startovní čárou (řezy za `start.slice`, střídavě vlevo a vpravo), stejné auto nebo výběr v menu. Hotovo 30. 10. 2026: stejné auto v jiných barvách palety, hráč startuje poslední; aby se auta na stejné stopě nesrážela, drží AI odstup od auta před sebou (jinak asi 18 doteků na auto za minutu).
- Pořadí podle postupu po řezech, cíl pro každé auto, pozice v HUD, výsledky. Hotovo 30. 10. 2026 jako samostatný `race_standings.gd` vedle `RaceTimer`: rozdíl v čase proti hráči podle okamžiku průjezdu stejným místem (jako časomíra), počítá i s koly okruhu.
- Zvuk motoru a světla soupeřů (stávající skripty jsou pro každé auto).
- **Brána:** FPS s 1 / 3 / 7 soupeři (okno, pohled za autem, stojící i v jízdě). Při poklesu LOD.

**D. Racecraft a osobnosti**
- Hotovo 30. 10. 2026: objetí pomalého nebo stojícího auta (hráč zastaví před soupeřem). Soupeř posune stopu na stranu s místem, objíždí těsně a smí se dotknout; bez místa auto opatrně vytlačí (o 1,5 m/s rychleji, pod prahem poškození). Podle přání hráče má být soupeř spíš agresivní, ale s ohledem na poškození. Po vyzkoušení ve hře (soupeři za stojícím hráčem zastavili nebo objížděli pozdě) se počítá velikost aut podle natočení, objíždí se po vlastní straně a začne se hned, když pomalé auto soupeře zdržuje.
- Hotovo 30. 10. 2026: 3 stálí soupeři s profilem (D-029), tedy jménem, jízdním stylem (podíl přilnavosti a brzd, odstup, ochota předjíždět) a barvou, která zůstává stejná napříč auty. Osobnosti z `prsonal` je později můžou nahradit nebo doplnit.
- Výhled na auta před sebou podle řezů, posun stopy při předjíždění (druhá stopa `.lsp`), nebrzdit „do auta“, ponechat prostor.
- Vlastnosti `prsonal.json` → parametry: dovednost a zatáčky → podíl profilové rychlosti a přesnost stopy; brzdění → rezerva brzdného bodu; kličkování → šum ve stopě; blokování a agresivita → bránění a kontakt; četnost chyb → občasné přebrzdění nebo smyk.

**E. Obtížnost**
- Síla AI ve stupních podle `tuning.json` + rozptyl osobností podle `SPREAD`, volba v menu (jako D-017).
- Gumička z `glue.json` jako volitelná položka, výchozí vypnutá; rozhodnout po hraní.

**F. Později**
Reakce ze `SCRIPTS`, provoz (TRAFCFG, `.edg`, `.jnc`), policie (`Cops/*.cop`, `hhglue`), postavy a dialogy přes LLM ([IDEA-002](../ideas/llm-opponent-personas.md)), posilované učení (Godot RL Agents).

## 6. Rizika

| Riziko | Dopad | Záložní plán |
| --- | --- | --- |
| Fyzika v GDScriptu na 8 aut nestačí | FPS | Méně podkroků kol u vzdálených aut, zjednodušený pohyb mimo záběr, nakonec přepis kola do C++ (GDExtension) |
| AI se stejnou fyzikou se vytáčí a padá z trati | hratelnost | Rezerva v profilu, kontrola trakce a ABS zapnuté pro AI, zotavení resetem |
| Stopy `.lsp` daleko od řezů (Monte Carlo až 26 m) | AI vyjede nebo se zastaví o zátaras | Ověřeno: stopa vede po skutečné trase varianty, proto se bere bez omezení; kontrola „mimo silnici“ se měří od stopy |
| Vlastní tratě nemají `.lsp` | fáze 3 | Generovat stopu z řezů; `.lsp` slouží jako reference, jak má vypadat |
