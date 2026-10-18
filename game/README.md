# Prototyp jízdy (fáze 2)

Godot 4.7 projekt pro milník fáze 2 (D-009): původní **356 A coupe 1.6** na původní trati **farmland** (Normandie), případně na **skidpadu**.

## Data originálu

Projekt nic z originální hry neobsahuje ani neimportuje. Auto a trať se načítají **za běhu** (`GLTFDocument`, `JSON`) ze složky `../decomposed` (nastavení projektu `stuttgart/data_root`). Do gitu tak nemůže nic z originálu přijít (D-008).

Potřebné soubory vytvoří nástroje z `tools/` (spouštět z kořene repozitáře):

```bash
python3 tools/sim_dump.py sources/GameData/Simulation/CarData > decomposed/GameData/Simulation/cars.json
```

```bash
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/farmland.crp decomposed/GameData/Track/farmland/farmland.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
```

Zvuk (zatím zvuky originálu, D-011):

```bash
python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds
```

Druhé auto a trať pro srovnání (935 „Moby Dick“, Monte Carlo):

```bash
python3 tools/crp2gltf.py sources/GameData/CarModel/935.crp decomposed/GameData/CarModel/935/935.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/monaco1.crp decomposed/GameData/Track/monaco1/monaco1.gltf
```

## Spuštění

Otevřít `game/project.godot` v Godotu 4.7 a spustit (F5). Fyzika Jolt, 120 Hz, renderer Forward+ přes Metal.

Hra začíná **hlavním menu** (`scenes/menu.tscn`): výběr auta (356 A coupe 1.6, 935 Moby Dick) a trati (Farmland = Normandie, Monaco) a tlačítko Play. Seznamy jsou v `main.gd` (`CARS` s názvem pro menu, `TRACKS`), další trať stačí přidat do `TRACKS`. Položka, jejíž data v `decomposed/` chybí, je neaktivní s poznámkou „chybí data“. Výběr předá autoload `GameSettings` (`scripts/game_settings.gd`) a uloží se do `user://settings.cfg`, příště je předvybraný. Ovládání menu: šipky / D-pad posouvají fokus, mezerník / A otevře seznam, Enter (kdekoli) nebo Start spustí hru, Esc hru ukončí. Esc při jízdě vrátí do menu.

Spuštění přímo `scenes/main.tscn` (F6 v editoru, testy) menu přeskočí: trať a auto pak určí výběr z menu, je-li v `GameSettings`, jinak argumenty a nastavení projektu níže.

Trať určuje nastavení projektu `stuttgart/track` (výchozí `farmland`), z příkazové řádky přepíše argument `-- --track=skidpad`. Argument `--slice=<n>` postaví auto na řez silnice n (kontrola konkrétního místa trati). Auto startuje na startovní čáře originálu (`start` v `_road.json`), na skidpadu na řezu 0.

| Klávesa | Akce |
| --- | --- |
| W / S, šipky | plyn / brzda (při stání brzda = zpátečka) |
| A / D, šipky | řízení |
| mezerník | ruční brzda |
| R | návrat na nejbližší řez silnice (`SimD`) |
| F2 | záznam telemetrie do `user://telemetry_*.csv` (cesta se vypíše do konzole) |
| F3 | asistent řízení zapnout / vypnout (stav je v HUD, výchozí zapnuto) |
| F4 | ABS zapnout / vypnout (stav je v HUD, výchozí zapnuto) |
| F5 | oprava auta (vynuluje poškození, prototyp) |
| F6 | kontrola trakce zapnout / vypnout (stav v HUD, při zásahu i podíl ubraného momentu, výchozí zapnuto) |
| T | vynulovat denní počitadlo (trip), válečky dojedou zpět na nulu |
| M | zvuk vypnout / zapnout (stav v HUD) |
| F11 | celá obrazovka / okno |
| Esc | zpět do hlavního menu (v menu: ukončit hru) |

Samostatně spuštěná hra běží přes celou obrazovku (ne v náhledu editoru, ne v testech bez okna). Okno si vynutí argument `-- --windowed=1`. HUD se škáluje se zvětšením okna (základ 1152 × 648).

**Klávesnice** funguje jako v tehdejších arkádových hrách: klávesa je zapnuto/vypnuto, ale pedály a volant se pohybují postupně, dokud ji držíš. Plyn naběhne při rozjezdu na jedničku za 0,4 s, se stoupající rychlostí a stupněm rychleji (od 100 km/h nebo na nejvyšší stupeň 0,15 s), puštění 0,1 s, brzda za 0,6 s (0,15 s), takže ťuknutí jen lehce přibrzdí. Volant jde ze středu na doraz za 0,25 s v klidu až 0,8 s ve 150 km/h, zpět do středu za 0,2 s. Analogový vstup (`Car.digital_input = false`, testy fyziky, později gamepad) jde přímo.

**Kontrola trakce** (F6, D-015) bere poháněnému kolu moment, když jeho kombinovaný skluz (podélný a boční dohromady, 1 = vrchol síly pneumatiky) překročí 0,8. Při 1,05 už kolo nedostává nic. Kolo se tak drží kolem vrcholu přilnavosti i v zatáčce. Působí v každém podkroku kola a na každé kolo zvlášť (jako brzdová kontrola trakce), na brzdění motorem ne.

**Rozjezd a pohon** (`Car`, skupina „Driver aids and drivetrain“):

- **Spojka při rozjezdu**: na jedničku a zpátečku řidič vytočí motor až na 40 % omezovače (podle plynu, 356: 2 320 ot/min, 935: 3 200 ot/min) a pouští spojku, dokud ho kola nedoženou. Bez plynu je spojka sešlápnutá (motor nebrzdí). Dřív motor stál při rozjezdu na volnoběhu.
- **Turbo** (`.sim` 0x04C): křivka `.sim` je moment s plným tlakem. Tlak se k úrovni pro dané otáčky (plný od otáček, kde křivka dosáhne 90 % maxima, 935: 5 000 ot/min) blíží s časovou konstantou podle éry: do roku 1979 0,8 s, do 1994 0,5 s, později 0,3 s. Pod plnými otáčkami pomaleji (až 3×). Bez plynu a při řazení klesá za 0,3 s. Bez tlaku dává motor 50 / 60 / 65 % momentu podle éry, závodní auta o 10 % méně. U 930 a 935 je tak výrazná turbodíra. HUD ukazuje tlak v procentech.
- **Samosvorný diferenciál** u závodních aut (`.sim` 0x10C ≥ 1,3: 935, GT1, GT2, GT3): rychlejší kolo nápravy předá pomalejšímu až 60 % momentu nápravy. Ostatní auta mají otevřený diferenciál.

**Asistent řízení** omezuje natočení předních kol na 1,1× vrchol úhlu skluzu pneumatiky (356: 8,6°) kolem směru, kterým se přední náprava skutečně pohybuje. Plné řízení z klávesnice tak znamená „zatáčej, jak nejvíc to jde“, ne „natoč kola na doraz“ (přední kola by skluzovala a auto by nedotáčelo). Ve smyku zadní nápravy dovolí kontrovat. Pod 2 m/s nepůsobí, do 6 m/s se postupně zapíná. Vypnutý = jen mechanický doraz 30°.

**ABS** (brzdový asistent) nedovolí předním kolům zablokovat se: v každém podkroku kola uvolní brzdu, když skluz překročí 0,8× vrcholu, takže auto při brzdění zatáčí. Zadní kola mohou skluzovat až do 1,2× vrcholu: při prudkém brzdění v zatáčce odlehčená záď uteče a auto jde do smyku jako v originále (hlášení z ruční jízdy 17. 10. 2026). Ruční brzda zadní kola zablokuje vždy. Vypnuté ABS = kola se zablokují (při plné brzdě přední), auto v zatáčce plave rovně.

## Struktura

| Soubor | Obsah |
| --- | --- |
| `scenes/menu.tscn`, `scripts/menu.gd` | hlavní menu: výběr auta a trati, Play (hlavní scéna projektu) |
| `scripts/game_settings.gd` | autoload `GameSettings`: výběr z menu, poslední výběr v `user://settings.cfg` |
| `scenes/main.tscn` | scéna: prostředí, slunce, auto, kamera, HUD |
| `scripts/original_assets.gd` | načítání glTF a JSON z `decomposed/` |
| `scripts/main.gd` | načtení trati (kolize z mesh skupin `road`, `terrain`, `objects`), auta, start na řezu silnice, ovládání, záznam telemetrie |
| `scripts/car.gd` | auto: raycast podvozek nad `RigidBody3D` (D-003), motor a automatická převodovka z `cars.json`, model pneumatik (skluz, rotace kol, setrvačnost motoru), spojka při rozjezdu, turbo, samosvor, kontrola trakce a ABS |
| `scripts/follow_camera.gd`, `scripts/hud.gd` | kamera za autem, údaje o jízdě |
| `scripts/car_damage.gd` | poškození: impulsy kontaktů karoserie sečtené za prvních 0,1 s nárazu, nad prahem promáčknou zóny u bodu nárazu (blend shapes `dz0`–`dz9` z `<auto>_damage.json`); díly odpadají nebo visí na pantech (`HingeJoint3D`); následky čte `car.gd` |
| `scripts/car_audio.gd` | zvuk auta: smyčky motoru podle otáček (výška, prolínání dvou nejbližších) a plynu (load / coast), pískání pneumatik podle skluzu, vítr, drhnutí, nárazy a díly ze signálů `CarDamage`; sběrnice `Engine` a `Sfx` |
| `scripts/track_props.gd` | fyzika objektů kolem trati (skupina `props`, `<trať>_objects.json`): sražitelné jako `RigidBody3D` s původní hmotností, zmrazené, dokud se nepřiblíží pohyblivé těleso (1 m), ostatní statické; kolize z konvexního obalu, ploché jako kvádr 10 cm |
| `scripts/gauge.gd` | kulatý budík (otáčkoměr, rychloměr) kreslený v `_draw()`; stupnice nastaví `hud.gd` podle redline a převodů auta |
| `scripts/odometer.gd`, `scripts/odometer_logic.gd` | mechanické válečkové počitadlo v rychloměru (D-013); nájezd z poháněných kol, ukládaný pro každé auto do `user://odometer.cfg` (jen ve hře, ne v testech) |

Auto: nastavení projektu `stuttgart/car` nebo argument `-- --car=<klíč v cars.json>` (výchozí `356Acoupe16`, ověřené i `935race`). Model a zvuková sada auta jsou v `CARS` v `main.gd` (přiřazení sady k autu je v originále v programu, ne v datech). Například 935 v Monaku:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game -- --windowed=1 --car=935race --track=monaco1
```

**Nastavení odvozená z dat** (`Car.derive_from_data`, hypotézy pro neznámá pole `.sim`):

| Nastavení | Odvození | 356 A | 935 |
| --- | --- | --- | --- |
| odpor vzduchu Cd·A | při maximální rychlosti z dat pokryje nejvyšší výkon motoru odpor vzduchu a valení | 0,59 m² | 0,79 m² |
| brzdy | 0,8 g × 0x104 / 6,5 | 0,80 g | 1,42 g |
| doba řazení | 0,35 s × 0x054 / 8 | 0,35 s | 0,17 s |
| přítlak Cl·A vpředu / vzadu | (0x10C − 1) a (0x110 − 1) × 1,2 m² | 0 | 0,9 / 1,2 m² |
| pérování | 1,7 Hz × √(140 / 0x124 světlá výška mm); zdvih nahoru nejvýš 75 % světlé výšky | 1,7 Hz, 8 cm | 2,6 Hz, 4,5 cm |
| setrvačnost kola | 1,2 kg·m² × (poloměr / 0,292)² × šířka / 145 | 1,2 | 2,8 |
| zadní přilnavost | motor vpředu 1,0, jinak 1,12 | 1,12 | 1,12 |
| přilnavost μ | 0,444 + 0,353 × 0x0F4 | 0,85 | 1,34 |
| kolize karoserie | obal nezasahuje pod světlou výšku 0x124 | (obal od 0,19 m) | od 0,06 m |

## Testy

Automatický jízdní test (bez okna): auto plným plynem jede po skidpadu (nebo po trati z `-- --track=farmland`) podle řezů `SimD`. Před zatáčkami brzdí (dávkovaně), jen když by v nich potřebovalo víc než 0,55 g (plánuje se zpomalením 0,45 g a výhledem asi 240 m), změří 0–100 km/h, rychlost po 40 s, brzdnou dráhu ze 100 km/h a vypíše kontakty karoserie.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn
```

Brzdění v zatáčce (bez okna): na skidpadu auto jede po kruhu do 100 km/h, pak 3 s drží řízení do zatáčky a brzdu; vypíše rychlost stáčení a úhel smyku karoserie (beta). Brzda a řízení se drží jako klávesy (s náběhem), `--keyboard=0` je dá přímo. Volby `--brake=0..1`, `--steer=0..1`, `--abs=0`, `--set=vlastnost:hodnota` (ladění parametrů `Car`).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/brake_turn_test.tscn -- --brake=1 --steer=1
```

| 17. 10. 2026, 100 km/h, klávesnice | Úhel smyku max | Otočení za 3 s |
| --- | --- | --- |
| jen plné řízení | 7,7° | 58° |
| plná brzda rovně | 1,4° | 0° |
| plná brzda + 10 % řízení | 24° | 77° |
| plná brzda + plné řízení | 48° | 98° |
| plná brzda + plné řízení, přímý vstup | 62° | 113° |
| plná brzda + plné řízení, bez ABS | 7,7° (přední kola se po náběhu brzdy zablokují) | 15° |
| poloviční brzda + plné řízení, bez ABS | 8,2° | 51° |

Samotný náběh brzdy chování originálu nevyvolá, bez ABS přední kola po 0,6 s zablokují. ABS proto zůstává výchozí; jak to dělal originál, ukáže až srovnání přes Wine.

**Poškození.** Náraz se měří součtem impulsů kontaktů karoserie za prvních 0,1 s (další náraz se počítá až po odlepení od překážky). Nad prahem 1 500 N·s promáčkne zóny do 1,5 m od bodu nárazu: nejbližší plně, ostatní poměrně. Přírůstek = (impuls − 1 500) / 15 000. Lehké značky ani drhnutí podvozkem auto nepoškodí. Následky (parametry `Car`, skupina „Damage consequences“, při plném poškození):

- kolo na poškozeném rohu: rozbíhavost 3° (auto táhne na stranu poškozeného předku), přilnavost −15 %,
- motor (356: zóny zádě): moment −35 %,
- průměrné poškození: odpor vzduchu +15 %,
- předek uprostřed: rejstřík řízení −20 %,
- **odpadající díly**: světla, blinkry, zástěry, výfuk a značka odpadnou při 100 % své zóny (nejvíc vrcholů v ní). Letí s pohybem auta a 1,5 m/s od něj,
- **díly na pantech**: kapota (panty vzadu u čelního skla) se uvolní při poškození předku nad 50 % a volně se pohybuje (`RigidBody3D` na `HingeJoint3D`, 0–80°). Kryt motoru (panty nahoře u zadního okna) totéž při poškození zádi nad 50 % (0–70°). Tvrdý náraz z 100 km/h a víc (rychlost auta ve směru normály kontaktu těsně před nárazem) utrhne kapotu (náraz předkem) nebo kryt motoru (náraz zádí). Dveře (panty vpředu) se uvolní při poškození předku nebo zádi nad 50 % nebo po tvrdém nárazu a v zatáčkách se odstředivou silou otevírají a zavírají (0–70°). Utrhnou se při 100 % svého boku,
- **kola**: od 50 % poškození rohu se kolo viklá a hází (náklon osy obíhá s otáčením, 8° při 100 %, kmitá i sbíhavost a auto se třese). Při 100 % rohu a zároveň 100 % příslušného boku kolo upadne a auto si sedne na roh karoserie. Upadlé poháněné kolo nedostává moment, druhé kolo nápravy pohání dál (zjednodušení).

F5 vrátí všechny díly a kola na místo.

Test nárazu do zdi (bez okna) na vlastní ploše 500 m pod skidpadem, volby `--speed=km/h`, `--rear` (couvání), `--damage=zóna:hodnota,…` (nastaví poškození přímo, bez zdi, pak 4 s rozjezd a 6 s slalom s výpisem otevření dílů na pantech), `--hard=front|rear` (k tomu tvrdý náraz), v okně `--shot=<složka>` uloží snímek poškozeného auta. Bez okna nakonec zkusí opravu (F5) a ověří, že nic nezůstalo odpojené:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/damage_test.tscn -- --speed=50
```

| 17. 10. 2026 | Impuls | Poškození | Následky |
| --- | --- | --- | --- |
| čelně 20 km/h | 6 600 N·s | předek 0,34 | rozbíhavost do 1° |
| čelně 50 km/h | 12 600 N·s | předek 0,74, kapota 0,16 | rozbíhavost 2,2°, přilnavost −11 % |
| čelně 100 km/h | 23 900 N·s | předek 1,0 | rozbíhavost 3°, přilnavost −15 % |
| couvání 30 km/h | 7 700 N·s | záď 0,41 | motor −10 % |

| čelně 100 km/h | | předek 1,0 | odpadnou světla, blinkry a přední zástěry na obou stranách, přední kola se viklají 8° |
| `--damage=0:1,7:1` | | levý přední roh + levý bok | odpadnou levé dveře, levé přední díly a levé přední kolo, auto se nakloní o 3° a jede dál |
| `--damage=1:0.6` | | předek 60 % | kapota a obě dveře na pantech; ve slalomu (4 s rozjezd, pak střídavě plné řízení) dveře 0–71°, kapota 0–24° |
| `--damage=1:0.6 --hard=front` | | předek 60 % + tvrdý náraz | kapota utržená, dveře na pantech |
| `--damage=5:0.6 --hard=rear` | | záď 60 % + tvrdý náraz | kryt motoru utržený, dveře na pantech |
| čelně 110 km/h | 26 300 N·s | předek 1,0 | kapota utržená, dveře na pantech, světla a zástěry pryč |
| `--damage=3:1,4:1,5:1,6:1` | | záď + pravý bok | odpadne víko motoru, výfuky, značka, zadní světla a zástěry, pravé dveře a pravé zadní kolo, motor 65 % |

Jízdní testy na obou tratích a náraz do značky (80 kg, 44 km/h) končí bez poškození.

Zvuk (bez okna, tichý ovladač): auto na skidpadu projede převody s plným plynem a vypíše hlasitost a výšku smyček motoru po 1000 ot/min, pak ubere plyn a dostane smyk. Kontroly: stálá hlasitost při prolínání, výška 0,5–2, po ubrání plynu hrají smyčky bez plynu, pneumatiky pískají jen ve smyku. 17. 10. 2026: OK, pískání rovně 0, ve smyku 0,63.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/audio_test.tscn
```

Náraz do objektu (bez okna): auto se rozjede na první dopravní značku na farmlandu a vypíše rychlost nárazu a kam značka odletěla. 16. 10. 2026: náraz 44 km/h, značka (80 kg) odletěla o 9,2 m.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/prop_test.tscn
```

Počitadlo kilometrů: bez okna ověří polohy válečků a přenos (např. 999,95 → tři válečky v půlce přenosu). S oknem (bez `--headless`) pak 6 s ukazuje rychloměry všech tří ér s přetočením 99 999,5 → 100 000,5 km, ve druhé polovině s chvěním válečků. Jízdní test navíc porovnává počitadlo s ujetou dráhou (17. 10. 2026: +0,9 %, rozdíl dělá prokluz kol) a ověří nulování tripu klávesou T.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/odometer_test.tscn
```

Hlavní menu: bez okna ověří, že seznamy odpovídají `CARS` a `TRACKS`, položky s daty jsou aktivní a předvybrané a chybějící data položku jen zneaktivní.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/menu_test.tscn
```

Rozjezd z místa (bez okna): plný plyn klávesou (s náběhem, `--keyboard=0` přímo) na rovině pod skidpadem, po 0,1 s vypíše poměr prokluzu a úhel skluzu každého kola, moment motoru a zatížení náprav, nakonec 0–50 … 0–200 km/h a jak dlouho byla poháněná kola za vrcholem prokluzu. Volby `--turn=0..1` (rozjezd do zatáčky), `--set=vlastnost:hodnota` (např. `traction_control:false`). Telemetrie F2 zapisuje stejné údaje (`slip_*`, `angle_*`, `engine_nm`, `load_f`, `load_r`, `tc_cut`, `boost`, `clutch_slip`).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/launch_test.tscn -- --car=935race
```

| 18. 10. 2026, rozjezd klávesou | 0–50 | 0–100 | Kola za vrcholem | Max. poměr prokluzu |
| --- | --- | --- | --- | --- |
| 935, před změnou (náběh 0,3 s, bez spojky, turba a TC) | 2,19 s | 4,28 s | 1,38 s | 1,60 |
| 935, kontrola trakce zapnutá | 1,72 s | 3,43 s | 0 s | 0,10 |
| 935, kontrola trakce vypnutá | 1,72 s | 3,49 s | 0,28 s | 0,35 |
| 935, přímý vstup, bez TC | 1,57 s | 3,35 s | 0,28 s | 0,33 |
| 935, do zatáčky (`--turn=0.6`), TC, samosvor | 2,08 s | 4,50 s | 0 s | 0,11 (rozdíl zadních kol 0,06) |
| 935, do zatáčky, TC, otevřený diferenciál | 1,95 s | 4,72 s | 0 s | 0,10 (rozdíl 0,08) |
| 935, do zatáčky, bez TC | – | – | roztočí se | 14 |
| 356 A 1.6, před změnou | 5,29 s | 15,67 s | 0 s | 0,06 |
| 356 A 1.6, nyní (s TC i bez) | 4,81 s | 15,18 s | 0 s | 0,07 |

Diagnostika před změnou: poměr prokluzu se nedělí nulou (jmenovatel je nejméně 2 m/s, úhel skluzu nejméně 3 m/s), přenos hmotnosti vzniká z pérování (935 při rozjezdu 73–82 % zatížení vzadu proti 58 % v klidu). 935 se rozjížděla na volnoběh (bez spojky), kolem 30 km/h moment vyskočil na 550–690 Nm, zadní náprava dostala 16,5 kN síly proti 11,6 kN, které unese, a kola se protočila až na poměr prokluzu 1,5. Protočená kola mají jen 75 % síly, takže motor ve dvojce došel do omezovače. 356 je pod vrcholem i s plným plynem. V zatáčce s otevřeným diferenciálem se vnitřní kolo 935 protáčelo dvakrát víc než vnější.

Snímky obrazovky (otevře okno na pár sekund, PNG uloží do zadané složky):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/screenshot.tscn -- /tmp --track=farmland --slice=1284
```

Test na rovině (bez okna): 8 km dlouhá plocha 500 m pod skidpadem, plný plyn 60 s s držením směru, pak plná brzda. Vypíše odvozená nastavení, 0–100, 0–200 a 0–300 km/h, maximální rychlost a brzdné dráhy.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/straight_test.tscn -- --car=935race
```

| 17. 10. 2026 | 0–100 | 0–200 | Maximum | Brzdění 200–0 / 100–0 |
| --- | --- | --- | --- | --- |
| 356 A 1.6 (skutečnost ~16 s, 160 km/h) | 15,5 s | – | 145 km/h po 60 s, ještě stoupá | – / 51 m |
| 935 Moby Dick (data 354 km/h) | 4,1 s | 9,1 s | 299 km/h, omezovač na 4. stupeň | 113 / 30 m |
| 18. 10. 2026, spojka, turbo, TC, samosvor | | | | |
| 356 A 1.6 | 15,0 s | – | 145 km/h | – / 51 m |
| 935 Moby Dick | 3,3 s | 8,8 s | 299 km/h | 113 / 30 m |

356 je teď o 0,5 s rychlejší, než bylo, a asi o 1 s rychlejší než skutečnost: rozjezd se spojkou na 2 300 ot/min dá od začátku 107 Nm místo 78 Nm na volnoběhu. Zbytek rozdílu je ve zbytku zrychlení (odpor, převody), ne v rozjezdu. Pro závodní 935/78 oficiální 0–100 neexistuje, pro srovnání sériová 930 Turbo 3.3 (1 300 kg, 221 kW) uvádí 5,4 s.

935 na nejvyšší stupeň při 8 000 ot/min dosáhne jen 304 km/h, data uvádějí 354 km/h. Převody jsou krátké nebo zadní kola větší, než udává `.sim` (285/40 R16 odpovídá spíš přední pneumatice, přední kola modelu mají střed ve 0,28 m, zadní 0,31 m).

Monte Carlo (`monaco1`, okruh 3,7 km ze 4 úseků): 935 v jízdním testu (`-- --track=monaco1 --car=935race`) zrychlí na 100 km/h za 4,0 s (18. 10. 2026 s TC 3,2 s) a řadí 15×, na dnech sjezdů drhne spodkem zádi (6 cm nad zemí, bez poškození, výpis `--log-impacts`). Po 22 s narazí do svodidla, protože testovací řidič vyjíždí ze zatáček s plným plynem, což s 689 Nm na zadních kolech nejde. S kontrolou trakce (18. 10. 2026) naráží na stejném místě ve 22 s, ale pak se kola o svodidlo neprotáčejí (počitadlo +6 % proti +273 %). Náraz tedy nezpůsobuje prokluz, ale rychlost řidiče v zatáčce. Zvuk 935 je sada `sdxc` pro šestiválec do 8 000 ot/min.

Výsledky (Godot 4.7.2, Apple M1 Pro), reálná 356 A 1600 pro srovnání: 0–100 km/h asi 16 s, maximum 160 km/h.

| Datum | Model | Trať | 0–100 km/h | Po 40 s | Brzdění 100–0 |
| --- | --- | --- | --- | --- | --- |
| 15. 10. 2026 | zástupné pneumatiky | skidpad | 12,7 s | 139 km/h, 0,67 g | 49 m |
| 16. 10. 2026 | pneumatiky, asistent, brzdy 0,8 g, stabilizátor hlavně vpředu | skidpad | 15,9 s | 133 km/h, 0,67 g | 51,0 m |
| 16. 10. 2026 | + pérování s předpětím, aktuální paprsky, obal karoserie | skidpad | 15,8 s | 126 km/h (řidič brzdí na 0,55 g), 0,64 g | 56,6 m |
| 16. 10. 2026 | totéž | farmland | 26,5 s | 71 km/h, max 0,94 g, karoserie bez kontaktu se silnicí | – |
| 17. 10. 2026 | + ABS, zadní přilnavost 1,12 | skidpad | 15,8 s | 126 km/h, 0,64 g | 51,5 m |
| 16. 10. 2026 | totéž | farmland | 26,6 s (zatáčky) | 61 km/h, brzdění v zatáčkách 11,9 s, max 0,83 g | – |

Na farmlandu auto 40 s jede po silnici z kopce bez kolize. Odvážnější řidič (0,7 g / 0,6 g) se ale ve 37. s roztočí. Brzdí na horizontu v klesající zatáčce, kde auto nese jen asi 60 % váhy a zadní vnitřní kolo skoro nic (46–122 N), takže záď se zadním motorem uteče. Je to typická přetáčivost 356 při brzdění. Míru je potřeba porovnat s originálem.

## Stav a známá omezení

- Model pneumatik (`car.gd`): každé kolo má vlastní rotaci se setrvačností 1,2 kg·m², poháněná kola navíc setrvačnost motoru přes převod (0x058 / 1000 kg·m², hypotéza). Podélný skluz a úhel skluzu tvoří jeden normovaný vektor skluzu. Síla roste k vrcholu (délka 1), pak klesá na 75 % (smyk). Vrchol: skluz 0,12, úhel 3° + 0,08° × profilové číslo (356: 8,6°). Přilnavost μ = 0,444 + 0,353 × `.sim` 0x0F4 (356: 0,85, hypotéza), citlivost na zatížení 10 %, valivý odpor 0,015. Kola se integrují v 8 podkrocích. Brzdy působí momentem (max. 0,8 g jako bubnové brzdy, 58 % vpředu), bez ABS mohou kola zablokovat. Zadní pneumatiky mají 1,12× přilnavost předních (geometrie zadní nápravy, tlaky): bez brzdy je auto mírně nedotáčivé, při brzdění se zatížení přesune dopředu a záď ztratí rezervu. Se stejnou přilnavostí se auto se 56 % váhy vzadu roztočilo už při plném řízení bez brzdy, motor brzdí 12 % maximálního momentu. Převodovka řadí nahoru, když vyšší stupeň dá na kolech víc síly. Ladění proti originálu přes Wine zbývá.
- Stabilizátory: vpředu 1,0 × tuhost pružiny, vzadu 0,3 (356 měla stabilizátor jen vpředu). Se stejně tuhým vzadu se zadní vnitřní kolo při brzdění v zatáčce odlehčovalo a auto se roztáčelo.
- Kamera je 6 m za autem a 2,4 m nad ním.
- Parametry z `.sim`: hmotnost, převody, stálý převod, křivka momentu, otáčky omezovače, rozměr pneumatik, rozdělení pohonu, poloha motoru (posun těžiště). Hypotézy: přilnavost (0x0F4), setrvačnost motoru (0x058). Odvozené z dat (tabulka výše): odpor vzduchu, brzdy, řazení, přítlak, pérování, setrvačnost kol. Odhadem: stabilizátory, dorazy, zdvih dolů 10 cm.
- Vestavěné tlumení `RigidBody3D` je vypnuté (výchozích 0,1 bralo autu ~1 600 N), odpory se modelují explicitně.
- Pružiny mají předpětí: v klidu nesou čtvrtinu váhy přesně ve výšce modelu (spodek karoserie 0,19 m nad silnicí, kola v podbězích jako v originálu). Dřív byla pružina v klidu stlačená o celý zdvih 12 cm a karoserie si sedala.
- Paprsky kol se počítají v každém kroku znovu (`force_raycast_update`). Výsledek uzlu `RayCast3D` byl o dva kroky fyziky starý: při 120 km/h ležel bod dotyku 0,57 m za kolem, podvozek se zdál natažený a karoserie klesala až k silnici, kola mizela v podbězích.
- Kolize karoserie je konvexní obal jejích meshů bez kol (zaoblené rohy, skutečný práh 0,19 m). Box přes celou šířku zavadil předním rohem o klopenou silnici.
- Objekty kolem trati (farmland 66 značek, 4 sloupy) kolidují, značky jdou srazit. Terén a silnice mají oboustrannou kolizi (`backface_collision`), jinak jimi objekty propadaly. Animované objekty („sweepery“) stojí, předlohy z úloh (kužely, šipky) se zatím nerozmisťují.
- Poškození zatím bez textur (odřený lak). Nárazníky a blatníky jsou součástí meshe karoserie a neodpadávají (potřebují vlastní modely, [IDEA-006](../ideas/severe-damage-wheel-loss.md)). Zvuk motoru zatím bez prolínací mřížky originálu (jen dvě nejbližší smyčky), zvuky v `SND_coll.bnk` jsou vybrané podle signálu a potvrzené poslechem, okolí tratí zatím bez zvuku.

## Grafika (IDEA-009)

Materiály modelů nastavuje `scripts/materials.gd`: u auta podle stránky `.tpg` (lak s clearcoatem, chrom, světla, sklo s průhlednou tabulí, interiér, kola s chromem nebo gumou podle jasu textury), u trati anizotropní filtrování a procedurální detailní šum (triplanárně na UV2) na silnici a terénu. Prostředí: `PhysicalSkyMaterial`, AgX, SSAO, glow, výšková mlha se sun scatter, slunce pozdního odpoledne s PSSM 4 do 500 m a měkkými stíny.

Snímky a FPS (okno, tři pohledy, vsync vypnutý, `--env|--sky|--sun|--vp=vlastnost:hodnota` pro pokusy):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/graphics_test.tscn -- /cesta/ke/složce --slice=1284
```

| 17. 10. 2026, M1 Pro, 3600 × 2260, farmland řez 1284 | Za autem | Kokpit | Jízda |
| --- | --- | --- | --- |
| před (Filmic, ProceduralSky, stíny 250 m) | 85 | 80 | 85 |
| po, plná kvalita (filtr stínů vysoký, nativní rozlišení) | 35 | 27 | 34 |
| po, výchozí (filtr střední, MetalFX spatial 0,75) | 56 | 47 | 55 |
