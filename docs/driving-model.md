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
| Řízení | vstup ±127 (+ sbíhavost 0x100) × faktor rozsahu 0x0FC, rozsah se mění s rychlostí. Poškozená kola stáčí řízení do strany s náhodným chvěním, boční sklon silnice táhne řízení | `max_steer_deg` 30°, `steer_rate` 4 rad/s, asistent řízení drží přední kola u vrcholu směrového úhlu, poškození: sbíhavost, chvění, menší rejd | Rozsah z 0x0FC zatím nepřevádět (jednotka nejistá). Tah sklonu silnice je námět, který nemáme. |
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

## Otevřené otázky

- Jednotka 0x0FC (rozsah řízení) a náběh kláves v NFS5: dohledat vstup hráče v exe.
- Tvar křivky pneumatiky v originálu (funkce sil kola 0x4A20D0): zda jde o lineární omezení jako v NFS4, nebo o vrchol a pokles.
- Skutečné maximální boční zrychlení originálu: změřit přes Wine, protože z exe plyne jen kapacita ≈ 0x0F4 × g na suchém asfaltu.
