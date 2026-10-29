# Jízdní model: náš prototyp vs. originál (NFS5)

Stav k 19. 10. 2026. Náš model: `game/scripts/car.gd` (D-003, D-015, D-017). Originál: rozbor `Porsche.exe` (D-023, [formats/sim.md](formats/sim.md#analýza-porscheexe-ghidra)). Popis principů, žádný kód originálu.

## Shrnutí

- **Originál** je „přilnavostní“ model ve stylu NFS4. Zatížení kol se nepočítá z pružin. Je to statický podíl náprav (0x0F0), k němu přenos úměrný zrychlení (0x0F8 / tuhost 0x11C) a přítlak úměrný rychlosti. Každé kolo unese sílu do meze přilnavost × zatížení × povrch. Motor má otáčky měněné pevnými kroky za tik. Karoserie se jen vizuálně naklápí. Řízení je celé číslo ±127. Všechny hodnoty jsou ručně laděné koeficienty designérů a menu je mění díly a nastavením.
- **Náš model** je fyzikální simulace: odpružené těleso v Jolt na čtyřech paprscích, zatížení z pružin, tlumičů a stabilizátorů, pneumatiky se skluzem (poměr skluzu, směrový úhel, vrchol a pokles), rotace kol v podkrocích, motor svázaný s koly přes spojku. Navrch je vrstva asistentů, kterou originál takhle nemá.
- **Z toho plyne:** pole `.sim` s fyzikální jednotkou lze převzít přímo. Designérské koeficienty je potřeba převést (kalibrovat) na fyzikální parametry našeho modelu. Asistenti zůstávají jako samostatná vrstva a ladí se až nad zkalibrovanou fyzikou.

## Srovnání po oblastech

| Oblast | Originál (z exe) | Náš prototyp | Rozdíl / co s tím |
| --- | --- | --- | --- |
| Zatížení kol | statický podíl přední nápravy 0x0F0 + přenos = zrychlení / 9,8 × 0x0F8 × 0,2 / 0x11C (podélně i bočně, boční dělený mezi nápravy podle 0x130) + přítlak | z pružin a tlumičů (`ride_frequency` 1,7 Hz, `damping_ratio`), stabilizátory 1,0 / 0,3, těžiště posunuté podle polohy motoru | Náš přenos vzniká dynamicky a může kmitat. Statické rozložení odhadujeme z polohy motoru, originál ho má v datech (0x0F0). |
| Přilnavost | kapacita kola = zatížení × 0x0F4 × koeficient povrchu (tabulka 16 povrchů × 3 typy pneumatik: silniční, do deště, závodní; zvlášť sucho a mokro). Asfalt se silničními pneumatikami = 1,0, takže celkem ≈ 0x0F4 × g | μ = 0,444 + 0,353 × 0x0F4 (356 A 0,85, GT1 1,42), `rear_grip` 1,12 (motor vpředu 1,0), citlivost na zatížení, vrchol a pokles do smyku | Originál má rozsah 1,1–2,75 lineárně. My ho stlačujeme a vyvážení přední/zadní odhadujeme. Je potřeba změřit skutečné boční g originálu (Wine) a podle toho nastavit převod 0x0F4 → μ a 0x0F0 → `rear_grip`. |
| Pneumatika (tvar síly) | síla kola omezená kapacitou. Model skluzu jako NFS4 (boční síla z rychlosti kola, mez přilnavosti, pokles při ztrátě) | poměr skluzu a směrový úhel spojené do jednoho normovaného skluzu, vrchol `peak_slip_ratio` 0,12, úhel podle profilu pneumatiky, pokles na `slide_grip` 0,75 | Náš model je bohatší, to je výhoda. Data originálu pro tvar křivky nejsou, zůstává naše ladění. |
| Motor a převodovka | otáčky se mění pevnými kroky za tik (+250, −100, ±50), síla = moment × poměr rychlost/otáčky × účinnost 0x058 / hmotnost. Brzdění motorem = −moment × 0x098. Zpoždění řazení 0x054 (tiky) | otáčky svázané s koly, setrvačnost motoru = 0x058 / 1000 (**chybně**), účinnost pevně 0,85, brzdění motorem 0,12 × max. moment, doba řazení 0,35 s × 0x054 / 8, automat, spojka při rozjezdu, turbodíra | Opraveno 19. 10. 2026: 0x058 → účinnost převodu, 0x098 → brzdění motorem. Setrvačnost motoru je pevně 0,09 kg·m² (v datech není). |
| Brzdy | síla = pedál × 0x104 (m/s²) × (1 − poškození × 0,005), omezená úměrně rychlosti (kola se nikdy nezablokují), vpředu podíl 0x108 | `brake_decel_g` = 0,8 g × 0x104 / 6,5, `brake_front_bias` pevně 0,58, ABS jako asistent | Opraveno 19. 10. 2026: 0x104 přímo v m/s² (356 A 6,5 = 0,66 g), 0x108 → `brake_front_bias`. Originál kola nezamyká z principu, takže naše ABS (výchozí zapnuté) odpovídá originálu. |
| Aerodynamika | přítlak na nápravu = 0x10C / 0x110 × 0,001 × rychlost (lineárně), mají ho i silniční auta. Odpor ze vzorce: moment při vmax / v³ | přítlak ½ρv² × (0x10C − 1) × 1,2 m², silniční auta nulový. Odpor ½ρv²·CdA dopočítaný z vmax a výkonu | Opravit převod přítlaku: buď zachovat náš kvadratický tvar se stejnou silou při referenční rychlosti, nebo převzít lineární. Odpor máme ekvivalentní. |
| Řízení | vstup ±127 (+ sbíhavost 0x100) × faktor rozsahu 0x0FC, rozsah se mění s rychlostí. Poškozená kola stáčí řízení do strany s náhodným chvěním, boční sklon silnice táhne řízení | `max_steer_deg` 30°, od 29. 10. 2026 zmenšený s rychlostí (rozvor × μg / v² + vrchol směrového úhlu), `steer_rate` 4 rad/s, asistent řízení drží přední kola u vrcholu směrového úhlu, poškození: sbíhavost, chvění, menší rejd | Rozsah z 0x0FC zatím nepřevádět (jednotka nejistá). Tah sklonu silnice je námět, který nemáme. |
| Náběh kláves | NFS4: volant 16/32 (1/128 za tik, plný rejd 0,25 s, návrat 0,125 s), plyn 0,5 s, brzda progresivně. V NFS5 se vstup hráče zatím nenašel | plyn 0,4 → 0,15 s podle rychlosti, brzda 0,6 s lineárně, volant 0,25 → 0,8 s podle rychlosti, návrat 0,2 s | Jsme blízko NFS4. Jako další krok dohledat vstup hráče v exe NFS5. |
| Karoserie | jen vizuální naklopení / náklon (0x128 / 0x12C × zrychlení, meze 0x134 / 0x138, tlumení 0x114 / 0x118). Na fyziku vliv nemá | skutečný pohyb tělesa na pružinách | Náklon máme fyzikálně. Data originálu se dají použít ke kalibraci, kolik se karoserie má naklonit. |
| Díly a nastavení | díly a menu násobí koeficienty (brzdy 0x104, pneumatiky 0x0F4 / 0x0F0, pružiny 0x11C, přítlak, převody, světlá výška…) | nemáme | Až bude tuning ve hře, převzít princip „díl = násobitel parametru“. |
| Zjednodušený režim | rozvor ×0,8, tlumení karoserie ×0,83, přilnavost ×1,25 | – (asistenti v menu) | Originál zjednodušuje fyzikou, my asistenty. |

## Asistenti: náš navíc, nebo náhrada originálu?

| Asistent (D-015, D-017) | V originálu | Doporučení |
| --- | --- | --- |
| ABS (`brake_assist`) | Brzda je omezená úměrně rychlosti a kola se nikdy nezablokují. Je to vlastnost modelu, ne přepínač | Výchozí zapnuté = chování originálu. Vypnutí je naše rozšíření („simulace“). |
| Asistent řízení | Rozsah řízení se mění s rychlostí. Model skluzu nedovolí „přetočit“ přední kola tolik jako náš | Odpovídá principu originálu. Ponechat zapnutý jako výchozí. |
| Kontrola trakce | Prokluz hnacích kol omezuje pevný strop síly a model otáček. Asistent jako takový neexistuje | Naše rozšíření, potřebné kvůli klávesnici a fyzikálním pneumatikám. Ponechat. |
| Spojka při rozjezdu, turbodíra, samosvor | Nic takového, turbo je jen vyšší moment v křivce | Naše rozšíření pro charakter éry. Parametry nejsou z dat originálu. |
| Automatická převodovka | Originál má automat i manuál | Shoda. |
| Náběh kláves | NFS4 ano (ramp v carp.txt). NFS5 zatím nedohledáno | Shoda v principu. |

**Stav od 19. 10. 2026:** asistenti jsou ve výchozím stavu vypnutí (D-017). Po kroku 1 (brzdy, účinnost a brzdění motorem z dat) se auta podle jízdy uživatele chovají velmi věrně originálu i bez nich.

Asistenti tedy nejsou v rozporu s daty. Jsou to vrstvy, které u fyzikálních pneumatik nahrazují to, co originál dosahoval zjednodušeným modelem. Ladit je ale až po kalibraci fyziky.

## Jak zpracovat naměřená data

**1. Přímé převzetí (fyzikální jednotky, beze změny modelu).** Hotovo 19. 10. 2026 pro 0x104, 0x108, 0x058 a 0x098. V `_derive_from_data` se používá:
- 0x104 přímo jako zpomalení v m/s²;
- 0x108 jako `brake_front_bias`;
- 0x058 jako účinnost převodu místo pevných 0,85;
- 0x098 jako brzdění motorem (−moment při daných otáčkách × hodnota);
- 0x054 jako počet tiků (1/32 s?) pro dobu řazení;
- 0x124 jako světlou výšku (už teď).

Hmotnost, převody, moment, pneumatiky a vmax už se používají.

| Rovina, 0–100 / brzdění 100–0 | před | po |
| --- | --- | --- |
| 356 A 1.6 | 15,0 s / 51 m | 14,2 s / 58 m (0,66 g místo 0,80 g) |
| 993 Turbo | 4,7 s / 33 m | 4,5 s / 37 m (skutečnost 4,5 s) |
| 944 Turbo | 7,6 s / 43 m | 7,4 s / 51 m (podíl brzd vpředu jen 0,50) |
| 935 | 3,3 s / 30 m | 4,0 s / 34 m (účinnost 0,65) |

Účinnost převodu se promítá i do odporu vzduchu dopočítaného z maximální rychlosti, takže maxima se nezměnila. Z 0x054 se zatím bere doba řazení jako dřív (0,35 s × hodnota / 8), převod „tiky → sekundy“ zbývá ověřit. 356 A je teď asi o 2 s rychlejší než skutečnost (asi 16 s). Jednou z příčin je, že v originále se účinnost násobí v jeho vlastním modelu bez ztrát pneumatik.

**2. Převod designérských koeficientů na naše parametry (kalibrace).**
- **0x0F4 → μ:** nejdřív změřit maximální boční g originálu na skidpadu (Wine) pro dvě až tři auta (356 A, 993, GT1). Pak nastavit převod tak, aby náš skidpad dal stejné g se zapnutými i vypnutými asistenty.
- **0x0F0 → vyvážení:** místo heuristiky `rear_grip` podle polohy motoru odvodit poměr přilnavosti přední a zadní nápravy z 0x0F0. Pak zkontrolovat přetáčivost a nedotáčivost na skidpadu proti originálu.
- **0x0F8 / 0x11C / 0x130 → přenos zatížení:** nepřebírat vzorec, ale nastavit výšku těžiště, tuhost pružin a stabilizátorů tak, aby přenos při 1 g odpovídal originálu (zrychlení × 0x0F8 × 0,2 / 0x11C × zatížení).
- **0x10C / 0x110 → přítlak:** zvolit referenční rychlost (např. 200 km/h), spočítat sílu originálu a z ní naše Cl·A pro každou nápravu.
- **0x128 / 0x12C → náklon:** kalibrační cíl pro tuhost stabilizátorů (úhel náklonu při 1 g).

**3. Asistenti až nakonec.** Kalibrace se dělá s vypnutými asistenty (čistá fyzika proti cílovým číslům). Potom se asistenti zapnou a ověří se, že nemění maxima (boční g, brzdná dráha), jen ovladatelnost.

**4. Pro fiktivní auta (D-004).** Výsledkem kalibrace jsou převodní vztahy „hodnota `.sim` → parametr našeho modelu“. Fiktivní auta pak dostanou vlastní `.sim`-like data a projdou stejným převodem.

## Měření horizontů (20. 10. 2026)

Krok 1 postupu z rozhodnutí uživatele: jen měření, kód auta beze změny. `drive_test` na farmlandu, 120 s, rychlejší řidič (`--corner-g=0.9`), bez asistentů:

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game res://tests/drive_test.tscn -- --track=farmland --car=993Tcoupe36 --time=120 --corner-g=0.9
```

Test počítá svislý poloměr silnice R ze sklonu řezů `SimD`. v²/(R·g) ≥ 1 znamená, že i dokonale odpružené auto musí odlehnout. Zatížení pod 1 − v²/(R·g) znamená, že auto odlehčuje samo pérování.

| Auto | Max. rychlost | Max. v²/(R·g) | Skoky (všechny při v²/(R·g) < 1) | Ve vzduchu | Zatížení > 20 % váhy pod geometrií | Nejhorší případ |
| --- | --- | --- | --- | --- | --- | --- |
| 356 A | 131 km/h | 0,76 | 2 (1 odskok) | 0,26 s | 1,3 s | 115 km/h, v²/(R·g) 0,26: dovoleno 0,74, skutečně 0,33 |
| 993 Turbo | 164 km/h | 0,98 | 4 (1 odskok) | 0,26 s | 1,8 s | 97 km/h, 0,24: dovoleno 0,76, skutečně 0,22 |
| 944 Turbo | 147 km/h | 0,82 | 2 (1 odskok) | 0,28 s | 1,5 s | 125 km/h, 0,26: dovoleno 0,74, skutečně 0,26 |
| 935 | 169 km/h | 0,98 | (jen po nehodách) | – | 1,3 s | 101 km/h, 0,24: dovoleno 0,76, skutečně 0,06 |

Závěry:
- **Nadskakování způsobuje pérování, ne geometrie trati.** Všechny skoky přišly při v²/(R·g) pod 1 (0,72–0,96). Před každým byly pružiny úplně roztažené. Polovinu skoků následoval druhý odskok do 1 s. Výška nad silnicí byla 0,10–0,15 m a čas ve vzduchu 0,1–0,2 s.
- **Odlehčení je výrazné i na mírných horizontech.** Při v²/(R·g) jen 0,24–0,26 kleslo zatížení na 6–33 % váhy, ačkoli geometrie dovoluje asi 75 %. Pružina auto po stlačení před horizontem „vystřelí“ nahoru a tlumení (`damping_ratio` 0,35, stejné pro stlačení i odskok) ho nezabrzdí.
- **Krok 2 tedy dává smysl:** tlumiče se silnějším odskokem než stlačením, pak měření zopakovat.
- **Vedlejší nález, 935:** karoserie od rozjezdu opakovaně drhne o silnici (kontakty s `road`, doraz pérování 9,4 s ze 120 s). Má zdvih jen 4 cm a velký přítlak (0,9 / 1,2 m²). Patří ke kroku 3 (přítlak).
- Řidič s 0,9 g je pro farmland příliš odvážný. Všechna auta měla nehodu (kontakty s terénem, nesmyslná boční g při nárazu). Údaje po nehodě (993 a 935 na konci jízdy) nejsou čisté. Pro srovnání před a po kroku 2 stačí stejné nastavení, ale porovnávat jen skoky a zatížení před první nehodou.

## Krok 2: tlumiče (29. 10. 2026)

Tlumení v `car.gd` je rozdělené na stlačení (`damping_bump`) a odskok (`damping_rebound`), obojí jako podíl kritického tlumení. Výchozí hodnoty zůstávají 0,35 / 0,35, takže se chování nezměnilo. `drive_test` má volbu `--set=vlastnost:hodnota`. Údaje o horizontech počítá jen do první nehody (náraz do terénu nebo objektů, drhnutí karoserie o silnici se nepočítá).

Farmland, 120 s, řidič 0,9 g. Varianty: A = 0,35 / 0,35 (dosavadní), B = 0,35 / 0,7, C = 0,25 / 0,7.

| Auto (jízda do nehody) | Varianta | Skoky (odskoky) | Doraz | Zatížení > 20 % váhy pod geometrií | Nejhorší zatížení (geometrie dovoluje ~0,75) |
| --- | --- | --- | --- | --- | --- |
| 993 Turbo (114–118 s) | A | 3 (1) | 3,9 s | 1,75 s | 0,22 |
| | B | 2 (0) | 5,5 s | 2,14 s | 0,02 |
| | C | 1 (0) | 6,6 s | 2,12 s | 0,01 |
| 356 A (36 s) | A / B / C | 0 | 1,3 / 2,0 / 2,4 s | 0,19 / 0,33 / 0,34 s | 0,39 / 0,19 / 0,22 |
| 944 Turbo (35 s) | A / B / C | 0 | 1,0 / 1,6 / 2,0 s | 0,49 / 0,58 / 0,52 s | 0,26 / 0,13 / 0,12 |
| 935 (14–17 s) | A / B / C | 0 | 1,1 / 1,9 / 2,1 s | 0,18 / 0,24 / 0,23 s | 0,06 / 0,00 / 0,00 |

Závěry:
- **Tužší odskok skoky a odskoky trochu ubral (993: 3 → 1), ale odlehčení kol zhoršil.** Zatížení na horizontu klesá hlouběji (993: 0,22 → 0,01 váhy) a déle, auta jsou déle na dorazu. Proto výchozí hodnoty zůstávají 0,35 / 0,35.
- **Příčina je v modelu, ne v hodnotách.** Kolo je jen paprsek bez vlastní hmoty, takže tlumič působí přímo mezi karoserií a silnicí. Když silnice za horizontem „uteče“, rychlost roztažení dává tlumič odskoku a ta se přímo odečte od síly pneumatiky. Skutečné kolo (neodpružená hmota asi 30–40 kg) následuje silnici pružinou a tlumič brzdí jen pohyb karoserie vůči kolu. Pneumatika ztratí zatížení teprve tehdy, když kolo silnici nestačí sledovat.
- **Další podezřelý je doraz pérování.** Je čistě pružný (10× tužší) a auta na něm stráví 1–7 s. Uloženou energii pak vrací a hází karoserii nahoru.
- **Řidič s 0,9 g na farmlandu brzy havaruje** (356 A a 944 už po 35 s). Pro další srovnání použít mírnějšího řidiče (např. `--corner-g=0.75`).

Navržený další krok: **kolo s neodpruženou hmotou** (pro každé kolo svislá poloha a rychlost, pružnost pneumatiky, tlumič mezi kolem a karoserií) a tlumení dorazu. Je to větší změna modelu pérování. Odstraní ale příčinu, kterou samotné ladění tlumičů obejít nejde.

## Neodpružená hmota (29. 10. 2026)

Kolo už není jen paprsek. Každé kolo má vlastní hmotu (`unsprung_mass` podle šířky pneumatiky: 356 25 kg, 993 Turbo 39 kg) a svislou polohu a rychlost vůči karoserii (`travel`), integrované v podkrocích. Pružina, tlumič, doraz a stabilizátor působí mezi kolem a karoserií. Pružina jen tlačí, tlumič může i táhnout. Pneumatika je tuhá pružina mezi kolem a silnicí (`tyre_rate` 200 kN/m, `tyre_damping` 0,05). Jen ona dává zatížení pro přilnavost a kolo může ztratit kontakt samo.

Celková hmotnost auta kola obsahuje, takže pružiny jsou předepnuté jen vahou karoserie a váha kola přechází na karoserii, jen když pneumatika stojí na silnici. Statické stlačení pneumatiky je započtené, výška karoserie je tedy stejná jako dřív. Část reakce silnice napříč osou karoserie (auto naklopené proti silnici) jde na karoserii v místě styku jako přes ramena nápravy. Doraz má vlastní tlumení (`bump_stop_damping` 1,0 kritického). Přepínač `unsprung_model` vrátí původní model.

Ověření, že se jinde nic nezměnilo (starý / nový model):

| Test | 356 A | 993 Turbo | 935 |
| --- | --- | --- | --- |
| drive_test skidpad: 0–100, brzdění 100–0 | 14,4 s / 60,2 m → 14,4 s / 60,1 m | – | – |
| straight_test: 0–100, maximum, brzdění 100–0 | – | 5,5 s, 284 km/h, 37 m → beze změny | 4,0 s, 300 km/h, 34 m → beze změny |

Horizonty (farmland, 120 s, řidič 0,75 g). Celých 120 s bez nehody ujela jen 993. Ostatní auta havarují kolem 38 s ve stejné zatáčce (935 už po 15–18 s), u nich je údajů málo:

| 993 Turbo | Zatížení > 20 % váhy pod geometrií | Čas pod 50 % váhy | Nejhorší zatížení (dovoleno ~0,8) | Skoky (všechna 4 kola bez zatížení) | Doraz |
| --- | --- | --- | --- | --- | --- |
| starý model | 1,82 s | 4,42 s | 0,28 | 0 (počítáno podle paprsku, kolo vždy „na silnici“) | 2,7 s |
| kolo s hmotou, doraz bez tlumení | 1,27 s | 3,73 s | 0,33 | 3, 0,03–0,06 s, 7–10 cm | 3,8 s |
| kolo s hmotou + tlumený doraz (výchozí) | 1,23 s | 3,72 s | 0,33 | 3, 0,03–0,06 s, 7–10 cm | 4,3 s |

Závěry:
- **Kolo s vlastní hmotou odlehčení na horizontech zmenšilo:** o třetinu kratší doba s velkým odlehčením (1,82 → 1,23 s), čas pod polovinou váhy o 16 % kratší. Úplně ho ale neodstranilo.
- **Skoky jsou krátké a nízké** (do 0,06 s, do 10 cm). Ve starém modelu se úplné odlehčení jako skok nepočítalo, protože paprsek byl vždy na silnici. Pneumatika ale nenesla nic stejně.
- **Tlumení dorazu nemá měřitelný vliv.** Auta jsou na dorazu déle (2,7 → 4,3 s), protože kolo s hmotou do něj přejede setrvačností.
- **U 356 A, 944 a 935 jsou rozdíly v šumu** (málo horizontů do první nehody).
- **Před každým skokem jsou pružiny úplně roztažené.** Karoserie tedy dál dostává impuls nahoru ze stlačení v prohlubni před horizontem. Další kandidáti: tužší tlumení stlačení s neodpruženou hmotou (dřív testované jen na starém modelu), tužší pružiny vůči zdvihu (doraz 4 s ze 120 s je hodně) a mírnější řidič na farmlandu.

## Rejd řízení podle rychlosti (29. 10. 2026)

Rozbor nedotáčivosti ukázal, že s klávesnicí je hlavní příčinou pevný rejd 30° v jakékoli rychlosti. Plný rejd přetáhne přední pneumatiky daleko za vrchol směrového úhlu (356 A 8,6°, 993 Turbo 5,4°), síla spadne na `slide_grip` a auto jede rovně. Originál zmenšuje rozsah řízení s rychlostí (0x0FC, [formats/sim.md](formats/sim.md)), přední kola tedy za jízdy „nepřetočí“.

Nově (`speed_sensitive_steering`, výchozí zapnuto, D-026) je rejd na každou stranu omezený na **rozvor × μ·g / v² + `steer_lock_margin` × vrchol směrového úhlu** a nikdy víc než `max_steer_deg`. První člen je úhel pro nejmenší kruh, který přilnavost dovolí, druhý rezerva pro směrový úhel pneumatik. Při nízké rychlosti tak zůstává plný rejd, při 100 km/h je to u 356 A asi 10°. Ke straně, kam se pohybuje přední náprava (smyk), smí kola až do směru pohybu plus stejná rezerva, takže kontrování funguje. Omezení platí pro všechny vstupy. Jednotku 0x0FC jsme zatím nepřevedli, vzorec vychází z fyziky.

`brake_turn_test` na skidpadu, klávesnice, plné řízení bez brzdy a bez plynu, průměr 0,7–2 s po zatočení. Volby testu: `--car=`, `--entry=` (km/h). Test končí prvním nárazem.

| Auto, vstup | Rejd | Směrový úhel vpředu / vzadu | Boční zrychlení | Konec |
| --- | --- | --- | --- | --- |
| 356 A, 60 km/h, dřív | 30° | 30° / 3° | 0,55 g | |
| 356 A, 60 km/h, rezerva 1,0 | 13° | 14° / 5° | 0,76 g | |
| 356 A, 120 km/h, dřív | 30° | 32° / 3° | 0,48 g | vyjede z kruhu |
| 356 A, 120 km/h, rezerva 1,0 | 9,6° | 14° / 5° | ≈ 0,8 g | 3 s po kruhu, otočení 49° |
| 993 Turbo, 60 km/h, dřív | 30° | 26° / 2° | 0,67 g | |
| 993 Turbo, 60 km/h, rezerva 1,0 | 14° | 10° / 4° | 0,97 g | |
| 993 Turbo, 150 km/h, dřív | 30° | 31° / 2° | 0,72 g | vyjede z kruhu |
| 993 Turbo, 150 km/h, rezerva 1,0 | 6,4° | 9° / 3° | ≈ 1,1 g | 3 s po kruhu, otočení 52° |

Rezerva 1,5 dala 0,69 / 0,88 g při 60 km/h a 2,0 dala 0,62 / 0,80 g. Výchozí je proto 1,0. `drive_test` na farmlandu (993 Turbo, 120 s, řidič 0,75 g) je s omezením i bez něj stejný, robot rejd nikdy nepotřebuje.

Závěry:
- **Přední náprava zůstává blízko vrcholu** a boční zrychlení vzrostlo o 40–60 %. Auto už při plném rejdu z klávesnice nevyjede z kruhu.
- **Nedotáčivost ale úplně nezmizela.** Zadní směrový úhel (3–5°) je pořád pod vrcholem, takže mez drží přední náprava. Další na řadě je vyvážení z 0x0F0 místo pevného `rear_grip` 1,12.
- **Brzdění v zatáčce** (`--brake=1 --steer=1`) zatím porovnat nejde. Ze 100 km/h obě varianty po 2,1–2,6 s vyjedou z kruhu a narazí. Tabulka ze 17. 10. v `game/README.md` už neplatí (od té doby přibyla kola s hmotou a další změny) a je potřeba ji změřit znovu, nejlépe na delší rovné ploše.
- Při ustálené rychlosti a pevném natočení kmitá stáčení (např. 4–40 °/s s periodou asi 1 s). Podezřelá je hrbolatost skidpadu nebo pérování, zatím neřešeno.

## Otevřené otázky

- Jednotka 0x0FC (rozsah řízení) a náběh kláves v NFS5: dohledat vstup hráče v exe.
- Tvar křivky pneumatiky v originálu (funkce sil kola 0x4A20D0): zda jde o lineární omezení jako v NFS4, nebo o vrchol a pokles.
- Skutečné maximální boční zrychlení originálu: změřit přes Wine, protože z exe plyne jen kapacita ≈ 0x0F4 × g na suchém asfaltu.
