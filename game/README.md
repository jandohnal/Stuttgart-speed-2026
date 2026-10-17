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

## Spuštění

Otevřít `game/project.godot` v Godotu 4.7 a spustit (F5). Fyzika Jolt, 120 Hz, renderer Forward+ přes Metal.

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
| F11 | celá obrazovka / okno |

Samostatně spuštěná hra běží přes celou obrazovku (ne v náhledu editoru, ne v testech bez okna). Okno si vynutí argument `-- --windowed=1`. HUD se škáluje se zvětšením okna (základ 1152 × 648).

**Klávesnice** funguje jako v tehdejších arkádových hrách: klávesa je zapnuto/vypnuto, ale pedály a volant se pohybují postupně, dokud ji držíš. Plyn naběhne za 0,3 s (puštění 0,1 s), brzda za 0,6 s (0,15 s), takže ťuknutí jen lehce přibrzdí. Volant jde ze středu na doraz za 0,25 s v klidu až 0,8 s ve 150 km/h, zpět do středu za 0,2 s. Analogový vstup (`Car.digital_input = false`, testy fyziky, později gamepad) jde přímo.

**Asistent řízení** omezuje natočení předních kol na 1,1× vrchol úhlu skluzu pneumatiky (356: 8,6°) kolem směru, kterým se přední náprava skutečně pohybuje. Plné řízení z klávesnice tak znamená „zatáčej, jak nejvíc to jde“, ne „natoč kola na doraz“ (přední kola by skluzovala a auto by nedotáčelo). Ve smyku zadní nápravy dovolí kontrovat. Pod 2 m/s nepůsobí, do 6 m/s se postupně zapíná. Vypnutý = jen mechanický doraz 30°.

**ABS** (brzdový asistent) nedovolí předním kolům zablokovat se: v každém podkroku kola uvolní brzdu, když skluz překročí 0,8× vrcholu, takže auto při brzdění zatáčí. Zadní kola mohou skluzovat až do 1,2× vrcholu: při prudkém brzdění v zatáčce odlehčená záď uteče a auto jde do smyku jako v originále (hlášení z ruční jízdy 17. 10. 2026). Ruční brzda zadní kola zablokuje vždy. Vypnuté ABS = kola se zablokují (při plné brzdě přední), auto v zatáčce plave rovně.

## Struktura

| Soubor | Obsah |
| --- | --- |
| `scenes/main.tscn` | scéna: prostředí, slunce, auto, kamera, HUD |
| `scripts/original_assets.gd` | načítání glTF a JSON z `decomposed/` |
| `scripts/main.gd` | načtení trati (kolize z mesh skupin `road`, `terrain`, `objects`), auta, start na řezu silnice, ovládání, záznam telemetrie |
| `scripts/car.gd` | auto: raycast podvozek nad `RigidBody3D` (D-003), motor a automatická převodovka z `cars.json`, model pneumatik (skluz, rotace kol, setrvačnost motoru) |
| `scripts/follow_camera.gd`, `scripts/hud.gd` | kamera za autem, údaje o jízdě |
| `scripts/car_damage.gd` | poškození: impulsy kontaktů karoserie sečtené za prvních 0,1 s nárazu, nad prahem promáčknou zóny u bodu nárazu (blend shapes `dz0`–`dz9` z `<auto>_damage.json`); díly odpadají nebo visí na pantech (`HingeJoint3D`); následky čte `car.gd` |
| `scripts/track_props.gd` | fyzika objektů kolem trati (skupina `props`, `<trať>_objects.json`): sražitelné jako `RigidBody3D` s původní hmotností, zmrazené, dokud se nepřiblíží pohyblivé těleso (1 m), ostatní statické; kolize z konvexního obalu, ploché jako kvádr 10 cm |
| `scripts/gauge.gd` | kulatý budík (otáčkoměr, rychloměr) kreslený v `_draw()`; stupnice nastaví `hud.gd` podle redline a převodů auta |

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

Náraz do objektu (bez okna): auto se rozjede na první dopravní značku na farmlandu a vypíše rychlost nárazu a kam značka odletěla. 16. 10. 2026: náraz 44 km/h, značka (80 kg) odletěla o 9,2 m.

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/prop_test.tscn
```

Snímky obrazovky (otevře okno na pár sekund, PNG uloží do zadané složky):

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --path game res://tests/screenshot.tscn -- /tmp --track=farmland --slice=1284
```

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
- Parametry z `.sim`: hmotnost, převody, stálý převod, křivka momentu, otáčky omezovače, rozměr pneumatik, rozdělení pohonu, poloha motoru (posun těžiště). Hypotézy: přilnavost (0x0F4), setrvačnost motoru (0x058). Odhadem: odpor vzduchu (Cd·A 0,6), pérování (vlastní frekvence 1,7 Hz, zdvih 8 cm nahoru a 10 cm dolů od výšky modelu), stabilizátory, dorazy.
- Vestavěné tlumení `RigidBody3D` je vypnuté (výchozích 0,1 bralo autu ~1 600 N), odpory se modelují explicitně.
- Pružiny mají předpětí: v klidu nesou čtvrtinu váhy přesně ve výšce modelu (spodek karoserie 0,19 m nad silnicí, kola v podbězích jako v originálu). Dřív byla pružina v klidu stlačená o celý zdvih 12 cm a karoserie si sedala.
- Paprsky kol se počítají v každém kroku znovu (`force_raycast_update`). Výsledek uzlu `RayCast3D` byl o dva kroky fyziky starý: při 120 km/h ležel bod dotyku 0,57 m za kolem, podvozek se zdál natažený a karoserie klesala až k silnici, kola mizela v podbězích.
- Kolize karoserie je konvexní obal jejích meshů bez kol (zaoblené rohy, skutečný práh 0,19 m). Box přes celou šířku zavadil předním rohem o klopenou silnici.
- Objekty kolem trati (farmland 66 značek, 4 sloupy) kolidují, značky jdou srazit. Terén a silnice mají oboustrannou kolizi (`backface_collision`), jinak jimi objekty propadaly. Animované objekty („sweepery“) stojí, předlohy z úloh (kužely, šipky) se zatím nerozmisťují.
- Poškození zatím bez textur (odřený lak). Nárazníky a blatníky jsou součástí meshe karoserie a neodpadávají (potřebují vlastní modely, [IDEA-006](../ideas/severe-damage-wheel-loss.md)). Bez zvuku.
