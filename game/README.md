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

Barvy laku pro menu (bez nich nabízí menu jen původní texturu):

```bash
python3 tools/car_colors.py sources/FEData/Data/nfs5.car decomposed/FEData/Data/car_colors.json
```

Díly aut pro přepínač Stock / Sport a volbu pneumatik (bez nich má menu jen Stock a sériové pneumatiky; potřebuje `cars.json` a `sources/Porsche.exe`):

```bash
python3 tools/parts.py sources/FEData decomposed/FEData/Data/parts.json
```

Druhé auto a trať pro srovnání (935 „Moby Dick“, Monte Carlo):

```bash
python3 tools/crp2gltf.py sources/GameData/CarModel/935.crp decomposed/GameData/CarModel/935/935.gltf
```

```bash
python3 tools/track2gltf.py sources/GameData/Track/monaco1.crp decomposed/GameData/Track/monaco1/monaco1.gltf
```

Světla tratí (D-021): `track2gltf.py` zapíše i `<trať>_lights.json`. Vzhled září a jejich textury (`GameData/Render/common/*.png` z `fsh2png.py sources decomposed`):

```bash
python3 tools/flare.py sources/GameData/Render/flare.dat decomposed/GameData/Render/flares.json
```

## Spuštění

Otevřít `game/project.godot` v Godotu 4.7 a spustit (F5). Fyzika Jolt, 120 Hz, renderer Forward+ přes Metal.

Hra začíná **hlavním menu** (`scenes/menu.tscn`): výběr auta (všech 85 variant z `.sim`, např. '65 911 Coupé, '73 911 Carrera RS 2.7, '96 911 Turbo (993), plus policejní auta a provoz) a trati (14 tratí originálu a testovací polygon `skidpad`, kde auto startuje na řezu 0) a tlačítko Play. Seznamy jsou v `main.gd` (`CARS` s názvem pro menu, modelem a klíčem fyziky `physics`; `MODELS` se sadou zvuku motoru modelu; `TRACKS`), další trať stačí přidat do `TRACKS`. Názvy variant a jejich modely jsou z `FEData/Data/nfs5.car` (Carrera RS 2.7 má model `f901`, 996 Turbo `f996`, Boxster 2.5 `fboxster`). Policejní auta jezdí s fyzikou svého silničního auta, provoz (`eas`, `eden`, `postship`) nemá vlastní `.sim` a jezdí s `default`. Sady zvuku motoru jsou u 356 A a 935 vybrané poslechem, u ostatních zatím odhadnuté podle pořadí sad. Mezi autem a barvou je přepínač **Stock / Sport** (D-024): Stock = sériové auto, Sport = nejlepší díly originálu, které auto může dostat (motor, brzdy, převodovka, podvozek, aerodynamika, lehčí karoserie). Pod tratí je volba **pneumatik**: sériové, slick, do deště (na suchém asfaltu slicky drží víc, pneumatiky do deště méně). Volby, které auto nemá, jsou neaktivní; 959, 928, GT2 a GT3 díly v originále ignorují. Bez menu: `-- --tune=sport --tyres=slick`. Pod volbou pneumatik a denní doby je řádek přepínačů: asistent řízení, ABS, kontrola trakce, zvuk a diagnostika (údaje telemetrie v HUD: přetížení, úhel řízení, zásah kontroly trakce, plnicí tlak turba, poškození). Asistenti (řízení, ABS, kontrola trakce) jsou ve výchozím stavu vypnutí (od 19. 10. 2026, auta s hodnotami z dat se chovají věrně originálu i bez nich), zvuk a diagnostika zapnuté. Vše se nastavuje jen v menu, při jízdě je změnit nejde. Položka, jejíž data v `decomposed/` chybí, je neaktivní s poznámkou „chybí data“. Výběr i přepínače předá autoload `GameSettings` (`scripts/game_settings.gd`) a uloží se do `user://settings.cfg`, příště jsou předvybrané. Testy spouštějí `main.tscn` přímo a dostanou výchozí hodnoty, uložené nastavení hráče je neovlivní. Ovládání menu: šipky / D-pad posouvají fokus, mezerník / A otevře seznam, Enter (kdekoli) nebo Start spustí hru, Esc hru ukončí. Esc při jízdě vrátí do menu.

Spuštění přímo `scenes/main.tscn` (F6 v editoru, testy) menu přeskočí: trať a auto pak určí výběr z menu, je-li v `GameSettings`, jinak argumenty a nastavení projektu níže.

Trať určuje nastavení projektu `stuttgart/track` (výchozí `farmland`), z příkazové řádky přepíše argument `-- --track=skidpad`. Argument `--slice=<n>` postaví auto na řez silnice n (kontrola konkrétního místa trati). Auto startuje na startovní čáře originálu (`start` v `_road.json`), na skidpadu na řezu 0.

**Závod** (D-025, `scripts/race_timer.gd`): na tratích se startem i cílem (`start` a `finish` v `_road.json`: farmland, alps, autobahn, canyon, castle, coastal, foothills, forest, industrial) jede závod od startu do cíle. Auto stojí 3 m za startovní čarou, odpočet 3-2-1 ho drží (brzdy, spojka sešlápnutá, plynem jde motor vytočit), stopky běží od GO. Startovní čára je bílý pruh přes silnici (originál ji nemá), cílová čára jsou šachovnicové dlaždice originálu (`FNSH`, skupina `gates`); obě jsou decaly (`scripts/race_lines.gd`), takže kopírují silnici a auto nepřebarví. Za cílem se stopky zastaví, klávesy (i R) přestanou platit a auto samo brzdí (brzda 0,6, asi 0,5 g) podél silnice až do zastavení, pak ho drží brzdy. Backspace, P a Esc fungují dál. Čas se počítá z kroků fyziky, pauza ho zastaví. Cíl platí po průjezdu kontrolních bodů (řez silnice každých 50 řezů, ~300 m, v okruhu 40 m), takže zkratka polem do cíle ani průjezd cílem pozpátku se nepočítají. Čas v cíli je dopočítaný na okamžik průjezdu čárou v rámci kroku. Stopky jsou vpravo nahoře, v cíli se ukáže výsledný čas a rozdíl proti nejlepšímu. Nejlepší čas pro trať a auto se ukládá do `user://records.cfg` (jen ve hře, ne v testech; testy mají odpočet 0). Se `--slice=<n>` se závod nespouští. Kamera při startu obletí auto zepředu dozadu (3 s, `FollowCamera.intro_duration`).

| Klávesa | Akce |
| --- | --- |
| W / S, šipky | plyn / brzda (při stání brzda = zpátečka) |
| A / D, šipky | řízení |
| mezerník | ruční brzda |
| R | návrat na nejbližší řez silnice (`SimD`); stopky běží dál (za cílem nefunguje) |
| Backspace | závod znovu: auto na start, oprava, nový odpočet |
| P | pauza / pokračovat; v pauze se levým tlačítkem myši otáčí kamera kolem auta, kolečkem přiblížení |
| F2 | záznam telemetrie do `user://telemetry_*.csv` (cesta se vypíše do konzole) |
| F5 | oprava auta (vynuluje poškození, prototyp) |
| F11 | celá obrazovka / okno |
| Esc | zpět do hlavního menu (v menu: ukončit hru) |

**Řidič AI** (D-026, `scripts/ai_driver.gd`, krok B soupeřů): argument `-- --ai=0` nebo `--ai=1` předá auto hráče řidiči AI, který jede po ideální stopě originálu 0 nebo 1 (`<trať>_ai.json` z `tools/ai_lines.py`) se stejnou fyzikou jako hráč. Ovládá jen plyn, brzdu a volant (`Car.auto_drive`, bez klávesových ramp), ABS a kontrolu trakce má zapnuté. Řízení: pure pursuit na bod stopy 0,7 s před autem (10–35 m) a zpětná vazba podle skutečné úhlové rychlosti (na limitu přilnavosti auto nedotáčí a samotný geometrický úhel kol nestačí). Rychlost: profil po celé stopě spočítaný předem – v zatáčce √(0,8 μ g R) z poloměru stopy (nejmenší z měření přes 2, 3 a 4 řezy), před zatáčkou brzdění s 80 % možného zpomalení, v zatáčce jen s tou částí, kterou boční síla nechá volnou (kruh přilnavosti). Pedály sledují profil 0,4 s před autem: brzda podle potřebného zpomalení plus P člen na rychlost, plyn podle chyby rychlosti. Plyn i brzdu omezuje využití přilnavosti v zatáčce (změřené z rychlosti stáčení) a ve smyku nad 4° se povolí (plyn zavřený při 10°, brzda na 30 %); jinak 356 v zatáčce na plný plyn nebo plnou brzdu přetáčí a otočí se. Uvízne-li (4 s pod 1 m/s), vyjede ze silnice (3 s) nebo leží na střeše (2 s), vrátí se na stopu. Stopa se bere bez omezení na šířku řezů: v Monte Carlu vede až 26 m od řezů SimD, protože varianta trati jede vedlejší ulicí a řezy tam končí v zátarasech. Za cílem auto zastaví jako u hráče. Hlavní scéna projektu je menu a jeho výběr (uložený v `user://settings.cfg`) má přednost před `--car` a `--track`; pro jízdu s argumenty se spouští přímo `res://scenes/main.tscn`. V Monte Carlu použijte stopu 1: stopa 0 vede u řezů 74–87 ulicí, kterou monaco1 uzavírá zátarasy. Například 935 v Monaku:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://scenes/main.tscn -- --windowed=1 --car=935race --track=monaco1 --ai=1
```

Samostatně spuštěná hra běží přes celou obrazovku (ne v náhledu editoru, ne v testech bez okna). Okno si vynutí argument `-- --windowed=1`. HUD se škáluje se zvětšením okna (základ 1152 × 648).

**Klávesnice** funguje jako v tehdejších arkádových hrách: klávesa je zapnuto/vypnuto, ale pedály a volant se pohybují postupně, dokud ji držíš. Plyn naběhne při rozjezdu na jedničku za 0,4 s, se stoupající rychlostí a stupněm rychleji (od 100 km/h nebo na nejvyšší stupeň 0,15 s), puštění 0,1 s, brzda za 0,6 s (0,15 s), takže ťuknutí jen lehce přibrzdí. Volant jde ze středu na doraz za 0,25 s v klidu až 0,8 s ve 150 km/h, zpět do středu za 0,2 s. Analogový vstup (`Car.digital_input = false`, testy fyziky, později gamepad) jde přímo.

**Kontrola trakce** (přepínač v menu, D-015) bere poháněnému kolu moment, když jeho kombinovaný skluz (podélný a boční dohromady, 1 = vrchol síly pneumatiky) překročí 0,8. Při 1,05 už kolo nedostává nic. Kolo se tak drží kolem vrcholu přilnavosti i v zatáčce. Působí v každém podkroku kola a na každé kolo zvlášť (jako brzdová kontrola trakce), na brzdění motorem ne.

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
| `scripts/game_settings.gd` | autoload `GameSettings`: výběr a přepínače z menu, poslední výběr v `user://settings.cfg` |
| `scripts/car_parts.gd` | díly originálu (D-024): sady Stock / Sport a pneumatiky z `parts.json` použité na hodnoty `.sim` podle vzorců z exe |
| `scenes/main.tscn` | scéna: prostředí, slunce, auto, kamera, HUD |
| `scripts/original_assets.gd` | načítání glTF a JSON z `decomposed/` |
| `scripts/car_style.gd` | `CarStyle`: varianta modelu auta (D-022) – odebere díly ostatních stylů a vymění atlasy podle `<model>_styles.json`, kabriolety se staženou střechou (`top_up` ji zvedne) |
| `scripts/main.gd` | načtení trati (kolize z mesh skupin `road`, `terrain`, `objects`), auta, start na řezu silnice, ovládání, záznam telemetrie |
| `scripts/car.gd` | auto: raycast podvozek nad `RigidBody3D` (D-003), motor a automatická převodovka z `cars.json`, model pneumatik (skluz, rotace kol, setrvačnost motoru), spojka při rozjezdu, turbo, samosvor, kontrola trakce a ABS |
| `scripts/follow_camera.gd`, `scripts/hud.gd` | kamera za autem (úvodní oblet, nevjíždí do trati, náklon `roll_degrees`), údaje o jízdě, stopky a odpočet |
| `scripts/road.gd` | `Road`: řezy silnice SimD z `_road.json` (polohy a báze řezů, napojení úseků, `ahead`, nejbližší řez, poloha auta na řezu); sdílí `main.gd` a `AIDriver` |
| `scripts/ai_driver.gd` | `AIDriver`: řidič soupeře (D-026) – ideální stopa originálu, pure pursuit se zpětnou vazbou úhlové rychlosti, rychlostní profil z přilnavosti a brzd (kruh přilnavosti), plyn ubíraný v zatáčce a ve smyku, návrat na stopu |
| `scripts/race_timer.gd` | `RaceTimer`: závod od startu do cíle (D-025) – odpočet, stopky, kontrolní body, průjezd cílovou čárou, nejlepší časy |
| `scripts/race_lines.gd` | startovní a cílová čára jako decaly: cíl z dlaždic originálu (skupina `gates`), start vlastní bílý pruh |
| `scripts/car_damage.gd` | poškození: impulsy kontaktů karoserie sečtené za prvních 0,1 s nárazu, nad prahem promáčknou zóny u bodu nárazu (blend shapes `dz0`–`dz9` z `<auto>_damage.json`); díly odpadají nebo visí na pantech (`HingeJoint3D`); následky čte `car.gd` |
| `scripts/car_audio.gd` | zvuk auta: smyčky motoru podle otáček (výška, prolínání dvou nejbližších) a plynu (load / coast), pískání pneumatik podle skluzu, vítr, drhnutí, nárazy a díly ze signálů `CarDamage`; sběrnice `Engine` a `Sfx` |
| `scripts/track_props.gd` | fyzika objektů kolem trati (skupina `props`, `<trať>_objects.json`): sražitelné jako `RigidBody3D` s původní hmotností, zmrazené, dokud se nepřiblíží pohyblivé těleso (1 m), ostatní statické; kolize z konvexního obalu, ploché jako kvádr 10 cm |
| `scripts/gauge.gd` | kulatý budík (otáčkoměr, rychloměr) kreslený v `_draw()`; stupnice nastaví `hud.gd` podle redline a převodů auta |
| `scripts/odometer.gd`, `scripts/odometer_logic.gd` | mechanické válečkové počitadlo v rychloměru (D-013); nájezd z poháněných kol, ukládaný pro každé auto do `user://odometer.cfg` (jen ve hře, ne v testech) |

Auto: nastavení projektu `stuttgart/car` nebo argument `-- --car=<klíč v cars.json>` (výchozí `356Acoupe16`, ověřené i `935race`). Model auta je v `CARS`, zvuková sada modelu v `MODELS` v `main.gd` (přiřazení sady k autu je v originále v programu, ne v datech). Například 935 v Monaku:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game -- --windowed=1 --car=935race --track=monaco1
```

**Nastavení odvozená z dat** (`Car.derive_from_data`, význam polí `.sim` z rozboru `Porsche.exe`, [docs/formats/sim.md](../docs/formats/sim.md)):

| Nastavení | Odvození | 356 A | 935 |
| --- | --- | --- | --- |
| odpor vzduchu Cd·A | při maximální rychlosti z dat pokryje nejvyšší výkon motoru odpor vzduchu a valení | 0,59 m² | 0,79 m² |
| brzdy | 0x104 je přímo zpomalení v m/s² (do 19. 10. 2026 0,8 g × 0x104 / 6,5) | 0,66 g | 1,17 g |
| podíl brzd vpředu | 0x108 / 100 (dřív pevně 0,58) | 0,60 | 0,60 |
| účinnost převodu | 0x058 / 100, násobí hnací sílu (dřív pevně 0,85; 0x058 se mylně brala jako setrvačnost motoru, ta je teď pevně 0,09 kg·m²) | 0,90 | 0,65 |
| brzdění motorem | 0x098 / 100 × moment při daných otáčkách (dřív 0,12 × max. moment × otáčky / omezovač) | 0,23 | 0,10 |
| doba řazení | 0,35 s × 0x054 / 8 | 0,35 s | 0,17 s |
| přítlak Cl·A vpředu / vzadu | (0x10C − 1) a (0x110 − 1) × 1,2 m² | 0 | 0,9 / 1,2 m² |
| pérování | 1,7 Hz × √(140 / 0x124 světlá výška mm); zdvih nahoru nejvýš 75 % světlé výšky; tlumení stlačení a odskoku zvlášť (`damping_bump`, `damping_rebound`, obojí 0,35 kritického) | 1,7 Hz, 8 cm | 2,6 Hz, 4,5 cm |
| setrvačnost kola | 1,2 kg·m² × (poloměr / 0,292)² × šířka / 145 | 1,2 | 2,8 |
| neodpružená hmota kola | 25 kg + 0,1 kg × (šířka pneumatiky − 145 mm) | 25 kg | 41 kg |
| zadní přilnavost | motor vpředu 1,0, jinak 1,12 | 1,12 | 1,12 |
| přilnavost μ | 0,444 + 0,353 × 0x0F4 | 0,85 | 1,34 |
| kolize karoserie | obal nezasahuje pod světlou výšku 0x124 | (obal od 0,19 m) | od 0,06 m |

## Testy

Automatický jízdní test (bez okna): auto plným plynem jede po skidpadu (nebo po trati z `-- --track=farmland`) podle řezů `SimD`. Před zatáčkami brzdí (dávkovaně), jen když by v nich potřebovalo víc než 0,55 g (plánuje se zpomalením 0,45 g a výhledem asi 240 m), změří 0–100 km/h, rychlost po 40 s, brzdnou dráhu ze 100 km/h a vypíše kontakty karoserie. Na horizontech měří skoky (doba ve vzduchu, výška, roztažené pérování, odskoky) a zatížení kol proti tomu, co dovoluje svislý poloměr silnice (1 − v²/(R·g)); `--time=<s>` prodlouží jízdu, `--corner-g=<g>` zrychlí řidiče (výchozí 0,55). `--set=vlastnost:hodnota` nastaví vlastnost auta (např. `--set=damping_rebound:0.7`). Údaje o horizontech se počítají jen do první nehody. Výsledky z 20. 10. 2026 jsou v [docs/driving-model.md](../docs/driving-model.md#měření-horizontů-20-10-2026).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn
```

Brzdění v zatáčce (bez okna): na skidpadu auto jede po kruhu do 100 km/h (`--entry=`), pak 3 s drží řízení do zatáčky a brzdu; vypíše rychlost stáčení a úhel smyku karoserie (beta). Měření končí prvním nárazem do čehokoli kromě silnice. Brzda a řízení se drží jako klávesy (s náběhem), `--keyboard=0` je dá přímo. Volby `--car=`, `--turn=left|right` (jinak podle rozjezdu), `--brake=0..1`, `--steer=0..1`, `--abs=0`, `--set=vlastnost:hodnota` (ladění parametrů `Car`, nastaví se až po sestavení auta, takže přepínače čtené při sestavení jako `balance_from_data` nepůsobí). Se `--brake=0` měří nedotáčivost při plném rejdu (D-026).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/brake_turn_test.tscn -- --brake=1 --steer=1
```

Tabulka níže je ze 17. 10. 2026 a už neplatí (kola s hmotou, rejd podle rychlosti). Dnes auto ze 100 km/h vyjede z kruhu a narazí, viz [driving-model.md](../docs/driving-model.md#rejd-řízení-podle-rychlosti-29-10-2026).

| 17. 10. 2026, 100 km/h, klávesnice | Úhel smyku max | Otočení za 3 s |
| --- | --- | --- |
| jen plné řízení | 7,7° | 58° |
| plná brzda rovně | 1,4° | 0° |
| plná brzda + 10 % řízení | 24° | 77° |
| plná brzda + plné řízení | 48° | 98° |
| plná brzda + plné řízení, přímý vstup | 62° | 113° |
| plná brzda + plné řízení, bez ABS | 7,7° (přední kola se po náběhu brzdy zablokují) | 15° |
| poloviční brzda + plné řízení, bez ABS | 8,2° | 51° |

Samotný náběh brzdy chování originálu nevyvolá, bez ABS přední kola po 0,6 s zablokují. ABS proto bylo výchozí. Od 19. 10. 2026 je výchozí vypnuté (D-017), protože jízda s brzdami podle dat (0x104, 0x108) se bez asistentů chová věrně originálu.

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

Závod (bez okna): na farmlandu ověří, že odpočet drží auto na místě (29. 10. 2026: posun 4 cm usazením na svahu, motor do 5 800 ot/min), GO po 3 s, že zkratka do cíle bez kontrolních bodů a průjezd cílem pozpátku neplatí, po průjezdu všech 30 kontrolních bodů a cílem ve 30 m/s se stopky zastaví na okamžiku průjezdu (odchylka 8 ms), za cílem auto s drženým plným plynem a volantem samo zastaví na silnici (29. 10. 2026: ze 30 m/s za 6,4 s, 2,8 m od středu silnice; brzda a volant za cílem jdou bez klávesových ramp, dřív 6,1 s a 1,5 m) a stopky se nezmění, a Backspace začne nový odpočet za startovní čarou.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/race_test.tscn
```

Řidič AI (bez okna, `--fixed-fps 120` = simulace tak rychle, jak stačí procesor): auto řízené `AIDriver` musí bez návratu na stopu dojet závod do cíle přes všechny kontrolní body (farmland, výchozí), na okruhu bez startu a cíle ujet jedno kolo (`lap` v `_road.json`, `--laps=n` více kol). Nesmí se karoserií dotknout zdi, svodidel ani objektu (doteky s normálou do strany, `Car.side_contacts`; odření je pod prahem poškození, proto se počítá zvlášť) a smyk (úhel mezi směrem auta a pohybu nad 10 m/s) nesmí přesáhnout 12°. Vypíše čas, průměrnou a nejvyšší rychlost, nejvyšší překročení cílové rychlosti, poškození, doteky (s názvem objektu) a největší smyk; `--trace=od:do` vypisuje stav řidiče každých 0,25 s.

Výsledky 29. 10. 2026 (po úpravě brzdění a plynu a omezení brzdy v zatáčce; 356 B se Sport a slicky předtím v Monte Carlu při plné brzdě v zatáčce sklouzla o 25°; předchozí verze se 356 na farmlandu otočila o 91° a 935 se v Monte Carlu dotkla zdi, testy to tehdy neměřily):

| Auto, trať | Stopa | Čas | Průměr | Nejvýš | Doteky | Největší smyk |
| --- | --- | --- | --- | --- | --- | --- |
| 356 A, farmland (závod 9,2 km) | 0 | 5:56,72 | 93 km/h | 128 km/h | 0 | 6,0° |
| 935, Monte Carlo, 2 kola | 1 | 3:47,69 | 117 km/h | 198 km/h | 0 | 3,3° |
| 935, Monte Carlo, 2 kola | 0 | 3:44,97 | 119 km/h | 214 km/h | 1 (zátaras, řez 81) | 3,2° |
| 356 A, Monte Carlo, 2 kola | 1 | 5:12,40 | 86 km/h | 133 km/h | 0 | 7,8° |
| 356 A, Monte Carlo, 2 kola | 0 | 5:10,44 | 86 km/h | 138 km/h | 3 (zátaras, řez 81) | 4,8° |
| 356 B Carrera 2, Sport, slicky, farmland | 0 | 4:58,99 | 111 km/h | 152 km/h | 0 | 6,8° |
| 356 B Carrera 2, Sport, slicky, Monte Carlo, 2 kola | 1 | 4:21,70 | 102 km/h | 163 km/h | 0 | 9,8° |

Stopa 0 v Monte Carlu proto test nesplní, dokud se nevyjasní, ke které variantě trati patří (D-023).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 120 --path game res://tests/ai_drive_test.tscn
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 120 --path game res://tests/ai_drive_test.tscn -- --track=monaco1 --car=935race --line=1 --laps=2
```

Počitadlo kilometrů: bez okna ověří polohy válečků a přenos (např. 999,95 → tři válečky v půlce přenosu). S oknem (bez `--headless`) pak 6 s ukazuje rychloměry všech tří ér s přetočením 99 999,5 → 100 000,5 km, ve druhé polovině s chvěním válečků. Jízdní test navíc porovnává počitadlo s ujetou dráhou (17. 10. 2026: +0,9 %, rozdíl dělá prokluz kol).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/odometer_test.tscn
```

Den a noc: bez okna ověří hledání HDRI (monaco1–5 → monaco), náhradní procedurální oblohu bez HDRI, slunce nad obzorem ve směru nejjasnějšího místa HDRI a v noci dva reflektory se stíny a zadní světla, která zesílí při brzdění.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/lighting_test.tscn
```

Světla trati (bez okna): na monaco1 v noci ověří, že jsou rozmístěné všechny záře z `monaco1_lights.json` (144), světla 12 koz visí na jejich tělesech 1,12 m nahoře a blikají jednou za sekundu, `wrna` a `wrnb` se střídají, šipky `arwa`–`arwe` se rozsvěcují postupně, pouliční lampy svítí stále, skupina `OmniLight3D` je u kamery a okna a neony svítí. Lampy Monaka mají v noci vlastní světla a svítící sklo, čočky koz blikají se zářemi. Ve dne skupina světel chybí.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/track_lights_test.tscn
```

Hlavní menu: bez okna ověří, že seznamy odpovídají `CARS`, `TRACKS` a `TIMES` (denní doba za tratí), položky s daty jsou aktivní a předvybrané a chybějící data položku jen zneaktivní. Vedle auta je výběr barvy: první „Původní“ (textura beze změny), pak paleta auta s tovární barvou; při změně auta zůstane barva, kterou má i nové auto.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/menu_test.tscn
```

Díly (bez okna): díly z továrny nechají hodnoty `.sim` všech aut beze změny, Sport udělá 356 A 1600 lehčí, silnější, s lepšími brzdami a přilnavostí, slicky přidají a pneumatiky do deště uberou přilnavost na suchu, GT3 zůstane sériová a menu má Stock / Sport mezi autem a barvou a pneumatiky pod tratí. Srovnání v jízdě: `drive_test` s `-- --tune=sport` nebo `-- --tyres=slick` (356 A 1600 na skidpadu: 0–100 km/h 14,4 → 9,9 s, brzdná dráha 60 → 50 m).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/parts_test.tscn
```

Barva laku (bez okna): 356 A a 935 nabarví na červeno. Průměr texelů laku (alfa 204) i zón pruhů a prahů (77, 153, 166, 179, 230) musí být červený, ostatní texely atlasu, chrom a světla beze změny. Ve hře jde barvu zadat i jako `--color=#rrggbb`.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/paint_test.tscn
```

Kontrola modelů aut (s oknem): každý model v každém stylu (D-022) stojí na startu skidpadu, každá pneumatika na povrchu silnice (start skidpadu je klopený, ač řez SimD říká vodorovně: auto postavené jen na výšku řezu mělo kola na jedné straně 9 cm v silnici; test vypíše největší odchylku pneumatiky, 19. 10. 2026 do 2 mm), kamera ho obletí (8 pohledů kolem dokola, shora a zespodu) a uloží `<model>_style<n>.png` s deseti pohledy. Jen zvenku, kokpit se v této fázi neověřuje. `--model=`, `--style=` omezí výběr, `--color=#rrggbb` nabarví lak, `--hide=HoodIn,…` odebere díly podle začátku jména (hledání, který díl dělá chybu), `--top_up=1` zvedne střechu kabrioletů. Okno zůstává navrchu, zakryté okno se na macOS nepřekresluje a snímek, který se nezměnil, se pořídí znovu. Všech 113 kombinací trvá asi minutu. Výsledek 19. 10. 2026: [docs/model-check.md](../docs/model-check.md#styly-a-překryvy-dílů).

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/car_orbit_test.tscn -- /cesta/ke/složce
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
| 19. 10. 2026, brzdy, účinnost a brzdění motorem z `.sim` (exe) | | | | |
| 356 A 1.6 | 14,2 s | – | 145 km/h | – / 58 m |
| 993 Turbo (skutečnost 4,5 s, 290 km/h) | 4,5 s (dřív 4,7 s) | 14,9 s (15,7 s) | 284 km/h | 145 / 37 m (129 / 33 m) |
| 944 Turbo | 7,4 s (7,6 s) | 27,5 s (28,9 s) | 235 km/h | 194 / 51 m (166 / 43 m) |
| 935 Moby Dick | 4,0 s | 10,8 s | 300 km/h | 133 / 34 m |

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

- Pérování (`car.gd`, od 29. 10. 2026): kolo s neodpruženou hmotou (25–41 kg podle pneumatiky) na pružné pneumatice (200 kN/m). Pružina, tlumič (stlačení a odskok zvlášť), tlumený doraz a stabilizátor působí mezi kolem a karoserií, zatížení pro přilnavost dává jen pneumatika. `unsprung_model = false` vrátí dřívější model, kde kolo sedělo přímo na silnici (paprsek) ([docs/driving-model.md](../docs/driving-model.md#neodpružená-hmota-29-10-2026)).
- Model pneumatik (`car.gd`): každé kolo má vlastní rotaci se setrvačností 1,2 kg·m², poháněná kola navíc setrvačnost motoru přes převod (pevně 0,09 kg·m², v datech není). Podélný skluz a úhel skluzu tvoří jeden normovaný vektor skluzu. Síla roste k vrcholu (délka 1), pak klesá na 75 % (smyk). Vrchol: skluz 0,12, úhel 3° + 0,08° × profilové číslo (356: 8,6°). Přilnavost μ = 0,444 + 0,353 × `.sim` 0x0F4 (356: 0,85, hypotéza), citlivost na zatížení 10 %, valivý odpor 0,015. Kola se integrují v 8 podkrocích. Brzdy působí momentem (zpomalení 0x104 v m/s², 356: 0,66 g, podíl vpředu 0x108, 356: 60 %), bez ABS mohou kola zablokovat. Zadní pneumatiky mají 1,12× přilnavost předních (geometrie zadní nápravy, tlaky): bez brzdy je auto mírně nedotáčivé, při brzdění se zatížení přesune dopředu a záď ztratí rezervu. Se stejnou přilnavostí se auto se 56 % váhy vzadu roztočilo už při plném řízení bez brzdy, motor brzdí podílem 0x098 momentu při daných otáčkách (356: 23 %). Převodovka řadí nahoru, když vyšší stupeň dá na kolech víc síly. Ladění proti originálu přes Wine zbývá.
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

Materiály modelů nastavuje `scripts/materials.gd`: u auta podle stránky `.tpg` (lak s clearcoatem, chrom, světla, sklo s průhlednou tabulí, interiér, kola s chromem nebo gumou podle jasu textury), odrazy okolí v laku a sklech z `ReflectionProbe`, který jede s autem (auto na vizuální vrstvě 2, sklo s premultiplied alpha, D-018), slunce s plnou silou odlesků (`light_specular` 1,0 místo výchozích 0,5 Godotu, nízké slunce se leskne na silnici), u trati anizotropní filtrování a procedurální detailní šum (triplanárně na UV2) na silnici a terénu; má-li trať vedle glTF složku `advanced/` s mapami `<textura>_normal|ambient|specular|displacement.png` (vlastní, dělané k původním texturám, jen lokálně v `decomposed/`), přidají se k materiálům se stejnou základní texturou: normálová mapa (OpenGL, síla 0,5; materiál s ní nemá procedurální detailní šum, protože detailní vrstva Godotu normálovou mapu přepíše plochou), ambientní okluze, spekulár převedený na drsnost (lineárně 0 → 0,9, 1 → 0,4; silnice bez spekulární mapy ho berou z jasu své základní textury) a výšková mapa jako jednoduchá paralaxa (hloubka 0,3 % dlaždice). Každá mapa je volitelná, velikost libovolná. Prostředí: obloha z HDRI podle trati a denní doby (viz níže, bez HDRI `PhysicalSkyMaterial`), AgX, SSAO, glow, výšková mlha se sun scatter, slunce ze směru slunce v HDRI s PSSM 4 do 500 m a měkkými stíny.

### Den a noc (D-019)

V menu se vedle auta a trati volí **denní doba** (Den / Noc), ukládá se do `user://settings.cfg` s ostatním nastavením. Bez menu: `-- --time=night` nebo nastavení projektu `stuttgart/time`.

- **Obloha:** `scripts/sky_lighting.gd` načte za běhu HDRI `assets/hdri/<trať>_<day|night>.hdr` (složka v `.gitignore`, nastavení `stuttgart/hdri_root`). Trať bez číslice na konci: monaco1–5 sdílí `monaco_*`. Když vlastní soubor chybí, zkusí oblohu z Poly Haven podle `data/hdri.json` (`tools/fetch_hdri.py`). Obloha je `PanoramaSkyMaterial` a dává i okolní světlo a odrazy. Když HDRI chybí, zůstane procedurální obloha a v logu je hláška; hra nepadá.
- **Slunce:** nejjasnější místo HDRI (na kopii širokou 256 px, zpřesněné v plném rozlišení) určí směr `DirectionalLight3D`, takže stíny sedí se sluncem na obloze. Výsledek se ukládá do `user://hdri_sun.cfg` (klíč: velikost a čas souboru). Slunce v těchto HDRI je oříznuté (≈ 20 proti obloze ≈ 1), proto má světlo pevnou energii 1,5 a obloha se přepočítá tak, aby její osvětlení vodorovné plochy byla třetina slunce. Špička mnohem jasnější než obloha (neoříznuté slunce, měsíc) se kolem sebe ořízne na 50× průměr oblohy, jinak by svítila do stínů podruhé přes okolní světlo.
- **Noc:** slabé studené měsíční světlo (energie 0,1, stíny zapnuté) ze směru měsíce v HDRI, pokud je výš než 8°, jinak z pevného směru; obloha ztlumená na pevnou úroveň, expozice 1,0 místo 1,3, silnější glow.
- **Světla auta:** `scripts/car_lights.gd` podle dílů `Light*` modelu (vpředu = −Z). V noci dva `SpotLight3D` se stíny (jeden na stranu, energie 17, dosah 200 m, útlum 1,0, sklon −2°: na silnici svítí asi 2× dál než první verze s energií 8, dosahem 90 m a sklonem −3°, spočteno podle útlumu světla v Godotu; 3–4× bylo moc). Stíny reflektorů mají větší bias (0,15, normálový 3,0), jinak téměř vodorovný paprsek kreslil na hrubém terénu ostré tmavé pruhy, a měkké okraje PCSS (`light_size` 0,2 m); obojí bez měřitelného rozdílu FPS a svítící skla předních světel; zadní světla svítí v noci a víc při brzdění (i ve dne), s malým červeným `OmniLight3D` na stranu. Světla auta nesvítí na vlastní vizuální vrstvu auta.
- HDRI farmland a monaco jsou celá prostředí (stromy, domy), ne jen obloha: dole a mezi domy trati je vidět jejich fotka. Čistá obloha (`*_puresky` v `data/hdri.json`) by to nedělala.

Snímky a FPS (okno, dva pohledy za autem, kokpit se v této fázi neměří, vsync vypnutý, `--time=day|night`, `--env|--sky|--sun|--vp|--head=vlastnost:hodnota` pro pokusy, `--head` nastaví oba reflektory):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/graphics_test.tscn -- /cesta/ke/složce --slice=1284
```

| 17. 10. 2026, M1 Pro, 3600 × 2260, farmland řez 1284 | Za autem | Kokpit | Jízda |
| --- | --- | --- | --- |
| před (Filmic, ProceduralSky, stíny 250 m) | 85 | 80 | 85 |
| po, plná kvalita (filtr stínů vysoký, nativní rozlišení) | 35 | 27 | 34 |
| po, výchozí (filtr střední, MetalFX spatial 0,75) | 56 | 47 | 55 |
| 18. 10.: + sonda odrazů na autě (D-018) | 50 | 41 | 51 |

| 20. 10. 2026, M1 Pro, 3600 × 2260, farmland řez 1284, mapy z `advanced/` | Za autem | Jízda |
| --- | --- | --- |
| bez map | 51,6 | 50,4 |
| normála, AO, drsnost, bez výšky | 48,4 | 47,5 |
| + jednoduchá paralaxa (výchozí) | 46,7 | 46,0 |
| + hluboká paralaxa (4–12 vrstev) | 41,8 | 40,6 |

Hluboká paralaxa se zezadu od jednoduché nedá rozeznat. Načtení map farmlandu (47 materiálů, 180 souborů) trvá ≈ 0,9 s. Snímky v `decomposed/screenshots/advanced_*`.

| 18. 10. 2026, M1 Pro, 3600 × 2260 | Za autem | Jízda |
| --- | --- | --- |
| farmland řez 1284, procedurální obloha (před D-019) | 48 | 49 |
| farmland, HDRI den | 49 | 47 |
| farmland, HDRI noc (2 reflektory se stíny) | 47 | 47 |
| monaco1, procedurální obloha (před D-019) | 51 | 51 |
| monaco1, HDRI den | 52 | 53 |
| monaco1, HDRI noc | 48 | 43 |

HDRI obloha FPS nemění, noc stojí 2–8 FPS (stíny reflektorů). Načtení HDRI 4k trvá ≈ 0,2 s. Snímky v `decomposed/screenshots/hdri_before|hdri_after`. (První měření monaco1 před změnou ukázalo 126 FPS za autem, opakované jen 51, šlo o odlehlou hodnotu.)
