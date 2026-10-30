# Kontrola modelů z originálu

Výsledky `tools/mesh_check.py` z 18. 10. 2026, auta 29. 10. 2026 (D-016, D-022), jen čísla, žádná data originálu. Opakuje se po každém převodu (příkazy v [tools/README.md](../tools/README.md#pořadí-pro-hru)). Proč a jak převodník trojúhelníky otáčí: [formats/crp.md](formats/crp.md#díl-pr).

**Sloupce:** *otočeno* = trojúhelníky, které převodník otočil (auta podle uložených normál, tratě nahoru nebo podle sousední plochy); *proti normálám* = trojúhelníky, které po převodu nesouhlasí s normálami (práh 0,5 %); *zahozeno* = trojúhelníky s indexem mimo rozsah (musí být 0); *dolů* = plochy silnice a terénu s normálou y < −0,1; *díry* = paprsky přes šířku silnice hlavní trasy bez čehokoli pod sebou (musí být 0); *spáry* = prázdno užší než 0,3 m nebo v krajních 0,25 m šířky SimD; *mimo* = minutí na vedlejších úsecích, na koncích úseků (5 řezů) nebo s povrchem víc než 5 m od výšky řezu.

## Auta (úroveň 1)

Stav 30. 10. 2026: kontrola měří i pořadí vrcholů dílů kreslených jen z lícové strany a odsazení vrstvených dílů (D-016). Převodník zvedá vrstvené díly 1 mm nad podklad (viz níže). 9 OK, 35 WARN, žádný FAIL. WARN dává hlavně pořadí vrcholů jednostranných dílů a překryvy dílů. Celkem 112 222 trojúhelníků ve všech stylech, převodník jich 3 432 otočil podle normál.

**Sloupce navíc:**
- *styly* = počet `[styleN]` (– = model bez stylů).
- *otevřené hrany* = délka hran jen s jedním trojúhelníkem (svary do 1 mm), rozsah přes styly. Vrstvené díly (světla, obtisky, stíny kol …) se nepočítají, leží nad podkladem s vlastním okrajem. Karoserie originálu jsou z panelů, takže nula není cíl, ale styly jednoho modelu by se měly lišit jen svými díly.
- *překryvy* = dvojice dílů se 10 a více trojúhelníky ve stejné rovině a stejném směru (z-fighting). Nepočítají se díly položené na jiné záměrně (obtisky, světla, značky, kliky, stěrače, stíny kol, vnitřní a vnější panel víka).
- *pořadí jednostranných* = sdílené hrany, na kterých dva sousední trojúhelníky nesouhlasí v pořadí vrcholů, a aspoň jeden z nich hra kreslí jen z lícové strany (vnitřní panely víek, interiér, sklo). Špatně otočený trojúhelník je pak díra.
- *vrstvy* = vrstvené díly bez odsazení (střed trojúhelníku do 0,2 mm od dílu pod ním, hra je kreslí ve stejné hloubce) / zapuštěné (aspoň 3 rohy víc než 0,5 mm pod dílem). Počet dvojic dílů přes všechny styly.

*Proti normálám* je teď 0 u všech aut. Dřív to bylo 61 trojúhelníků vnitřních panelů víek na ohnutém okraji. Převodník teď otáčí celý souvislý kus panelu najednou (viz níže), takže normály přepočítané z ploch souhlasí.

| Auto | Trojúhelníky | Styly | Otočeno | Proti normálám | Zahozeno | Otevřené hrany (m) | Překryvy | Pořadí jednostranných | Vrstvy bez odsazení / zapuštěné | Stav |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 356_1 | 3602 | 2 | 130 | 0 | 0 | 121–122 | – | 2 | 0 / 1 | WARN |
| 356a | 6795 | 12 | 201 | 0 | 0 | 90–115 | – | 12 | 0 / 4 | WARN |
| 356b | 6127 | 13 | 134 | 0 | 0 | 102–121 | – | 12 | 0 / 0 | WARN |
| 550 | 2985 | 1 | 47 | 0 | 0 | 55–55 | – | 3 | 0 / 0 | WARN |
| 901 | 4695 | 7 | 98 | 0 | 0 | 90–91 | – | 4 | 0 / 0 | WARN |
| 914 | 2828 | 3 | 20 | 0 | 0 | 104–104 | – | 4 | 0 / 0 | WARN |
| 928 | 3410 | 1 | 11 | 0 | 0 | 64–64 | – | 3 | 0 / 2 | WARN |
| 930 | 2963 | 2 | 79 | 0 | 0 | 103–103 | – | 7 | 1 / 0 | WARN |
| 935 | 2963 | – | 6 | 0 | 0 | 102–102 | – | 10 | 0 / 0 | WARN |
| 944 | 4150 | 8 | 298 | 0 | 0 | 75–77 | Body/Engine | 2 | 0 / 6 | WARN |
| 959 | 3016 | 1 | 13 | 0 | 0 | 89–89 | – | 6 | 0 / 1 | WARN |
| 964 | 4729 | 8 | 228 | 0 | 0 | 103–106 | – | 13 | 0 / 0 | WARN |
| 993 | 4689 | 9 | 196 | 0 | 0 | 94–100 | – | 18 | 0 / 0 | WARN |
| 996 | 5010 | 5 | 243 | 0 | 0 | 128–133 | Body/SkirtS | 22 | 0 / 0 | WARN |
| boxster | 3216 | 3 | 179 | 0 | 0 | 114–118 | – | 11 | 0 / 1 | WARN |
| cop356 | 5612 | 4 | 155 | 0 | 0 | 116–132 | Interior/InteriorRoof | 12 | 2 / 0 | WARN |
| cop356_german | 6110 | 4 | 155 | 0 | 0 | 108–125 | – | 12 | 0 / 0 | WARN |
| cop930 | 3067 | – | 91 | 0 | 0 | 107–107 | – | 7 | 1 / 0 | WARN |
| cop930_german | 3075 | 1 | 91 | 0 | 0 | 107–107 | – | 7 | 1 / 0 | WARN |
| cop993 | 2961 | 1 | 100 | 0 | 0 | 95–95 | – | 18 | 1 / 1 | WARN |
| cop993_german | 2977 | 1 | 100 | 0 | 0 | 98–98 | – | 18 | 1 / 1 | WARN |
| eas1 | 430 | – | 22 | 0 | 0 | 70–70 | – | 18 | 0 / 0 | WARN |
| eas10 | 508 | – | 2 | 0 | 0 | 83–83 | – | – | 0 / 0 | OK |
| eas11 | 511 | – | 32 | 0 | 0 | 78–78 | – | 28 | 0 / 0 | WARN |
| eas2 | 561 | – | 0 | 0 | 0 | 97–97 | – | – | 0 / 0 | OK |
| eas3 | 484 | – | 0 | 0 | 0 | 152–152 | – | – | 0 / 0 | OK |
| eas4 | 503 | – | 0 | 0 | 0 | 109–109 | – | – | 0 / 0 | OK |
| eas5 | 440 | – | 0 | 0 | 0 | 76–76 | – | – | 0 / 0 | OK |
| eas6 | 468 | – | 8 | 0 | 0 | 72–72 | – | 14 | 0 / 0 | WARN |
| eas7 | 468 | – | 0 | 0 | 0 | 77–77 | – | – | 0 / 0 | OK |
| eas8 | 460 | – | 2 | 0 | 0 | 73–73 | – | – | 0 / 0 | OK |
| eas9 | 489 | – | 0 | 0 | 0 | 95–95 | – | – | 0 / 0 | OK |
| eden1 | 450 | – | 6 | 0 | 0 | 49–49 | – | 14 | 0 / 0 | WARN |
| eden2 | 428 | – | 8 | 0 | 0 | 53–53 | – | 18 | 0 / 0 | WARN |
| eden3 | 428 | – | 10 | 0 | 0 | 57–57 | – | 16 | 0 / 0 | WARN |
| eden4 | 390 | – | 14 | 0 | 0 | 53–53 | – | 16 | 0 / 0 | WARN |
| eden5 | 412 | – | 10 | 0 | 0 | 71–71 | – | 16 | 0 / 0 | WARN |
| f901 | 3114 | 1 | 83 | 0 | 0 | 103–103 | – | 4 | 0 / 0 | WARN |
| f996 | 3172 | 1 | 150 | 0 | 0 | 119–119 | – | 8 | 0 / 0 | WARN |
| fboxster | 2982 | 3 | 153 | 0 | 0 | 114–120 | – | 8 | 0 / 1 | WARN |
| gt1 | 3040 | 1 | 161 | 0 | 0 | 67–67 | DoorIn/Interior | 13 | 0 / 0 | WARN |
| gt2 | 3023 | 1 | 114 | 0 | 0 | 95–95 | – | 16 | 0 / 0 | WARN |
| gt3 | 3280 | 1 | 82 | 0 | 0 | 131–131 | – | 8 | 0 / 0 | WARN |
| postship | 1201 | – | 0 | 0 | 0 | 31–31 | – | – | 0 / 0 | OK |

### Styly a překryvy dílů

Kontrola 19. 10. 2026: všech 44 modelů ve všech 113 stylech na skidpadu, kamera kolem auta (`game/tests/car_orbit_test.tscn`, 8 pohledů dokola, shora a zespodu), plus `mesh_check.py`. Co bylo špatně a jak je to opravené:

| Model | Chyba | Oprava |
| --- | --- | --- |
| všechny se styly | převodník bral jen díly typu 0, takže každý kabriolet, speedster, targa, turbo a GT2 vypadal jako kupé; u alternativních textur bral první položku | styly z `.tpg` (D-022), atlas pro každý styl |
| f901 (Carrera RS 2.7) | bez karoserie, spodku, kol a víka (jen 1 770 trojúhelníků): model nemá díly typu 0 | 3 114 trojúhelníků, celé auto v laku RS |
| 356 A, 964 kabriolety | dvě celé zádě přes sebe (střecha nahoře `Cabrio` a dole `CabrioDown`, 268 překrytých trojúhelníků) | jen stažená střecha, `top_up` ji zvedne |
| 356, 356 B, 993, 996 kabriolety, 356 B roadster | dvě stejné zádě se zvednutou střechou (`Cabrio` a `CabrioUp`) | druhá se vynechá |
| 964, 993, 996, Boxster (a f996, fboxster) | křídlo dvakrát (`SpoilerW` = `SpoilerDown`, až 134 trojúhelníků) | `SpoilerW` se vynechá |
| 935, 964, GT1, 944 | zrcátka dvakrát (hrubší `SideMirrorLeft/Right` z LOD přes `SideMirror` / `GtMirror`, u 944 druhá kopie) | vynechané |
| 935, GT1 | zadní křídlo z LOD (`Spoiler`) přes křídlo v `Body` | vynechané |
| 356 B, cop356, fboxster, Boxster, GT1, GT3 | další drobné kopie z LOD (`InteriorRoof`, `SkirtF1`, `Light4`, `Needle1`, `Cap`) | vynechané |
| 901, 914 (a všechna auta s víky) | vnitřní panel víka (`HoodIn`, `TrunkIn`) v rovině vnějšího: textura zavazadlového prostoru prosvítala přes přední víko | vnitřní panely otočené dovnitř, kreslené jen z lícové strany |
| všechna auta s víky (29. 10. 2026) | vnitřní panely se otáčely po jednotlivých trojúhelnících, v ohybu na okraji víka podle vnějšího trojúhelníku přes ohyb: 356 A `HoodIn` 32 a `TrunkIn` 20 hran s opačným pořadím, po uvolnění nebo utržení víka (D-010) díry v rozích zespodu | celý souvislý kus panelu se otočí podle hlasování všech jeho trojúhelníků |
| 356 B, 944, cop356, cop993, f901, GT2, f996 | vnitřní panel varianty (`TrunkIn1`) nebo vnější varianty (`TrunkOut1`, `TrunkOut2`, u f996 `SpoilerDown`) se jménem nepárovaly, panel se vůbec neotočil (f996: 16 trojúhelníků ve stejné rovině jako křídlo) | párování podle jména bez čísla varianty, vnější panel podle začátku jména |
| 944, 914, 935 a dalších 41 modelů (30. 10. 2026) | vrstvené díly (světla, obtisky, stíny kol, kliky) leží v rovině podkladu, originál je kreslí až po něm; ve hře mají vlastní transformaci uzlu a blikají (944: pruh zadních světel `Light4` je kopie šesti trojúhelníků `Body` s texturou světel, `Body` má pod ním lak) | rohy vrstvených dílů do 1 mm nad podkladem (a nejvýš 0,5 mm pod ním) se zvednou na 1 mm po normále podkladu; trojúhelníky se zapuštěným rohem zůstanou, cíle poškození jsou posuny, takže odsazení drží i po promáčknutí |

Zbývá (původní data, ne chyba převodu):

- `cop356` styly 2–4 (Hardtop, Speedster, Cabrio): záď za dveřmi existuje jen jako hrubý díl z LOD (`CabrioUp*` od z = 0,45 m) a `Roof1` nemá na úrovni 1 plech střechy, takže za dveřmi chybí boky a hardtop je bez střechy. `nfs5.car` používá pro policejní 356 jen style1 (Coupe), hra jiný nepoužije.
- WARN překryvy jsou jednotlivé díly položené na karoserii jinak, než je seznam záměrných: 996 boční prahy `SkirtS` na `Body1` (16), 944 motor na `Body` (10), GT1 výplně dveří na interiéru (17), cop356 Hardtop strop na interiéru (12). Na snímcích nejsou vidět.
- 944 kabriolety (cabrioturbo, S2cabrio) mají za sedadly otevřenou vanu bez krytu složené střechy; v datech jiný díl není.
- Otevřené hrany se ve stylech jednoho modelu liší nejvýš o 25 m (356 A, 356 B, cop356_german, cop356: jiná záď kabrioletu); snímky děry neukázaly.

### Pořadí vrcholů a vrstvy

Kontrola 29. 10. 2026 (první měření v Blenderu na 356 A coupe 1.6, pak `mesh_check.py` na všech autech). Vnitřní panely víek jsou opravené (tabulka výše). Zbývá, zatím neopraveno:

- **Pořadí vrcholů jednostranných dílů** (počet aut): motor `Engine` 17, zrcátko `SideMirror` 16 (část na stránce skla nebo interiéru), interiér `Interior` 12, `TrunkSpace` 6, sedadla 4, stěrač `Wiper1a` 4, palubní deska 2, ojediněle další. Vidět jsou jen z kokpitu, při otevřeném nebo utrženém víku (motor, zavazadlový prostor) a u zrcátek zblízka. Oprava: stejné otáčení po souvislých kusech jako u víek, s orientací ven od středu auta nebo podle uložených normál.
- **Vrstvy bez odsazení** (dvojice dílů): opraveno 30. 10. (tabulka výše), ze zhruba sta dvojic zbývá 7: obtisk na karoserii 930 a cop930 (0,03 mm), stěrač na karoserii cop993 (0,18 mm, zapuštěný) a zadní světla cop356 na zádi `CabrioUp1` ve stylech 2–4, které hra nepoužívá.
- **Zapuštěné vrstvy** (25 dvojic 29. 10., teď 18): obtisky na stažené střeše kabrioletů, kliky, stěrače, světla na prazích. Jejich část je schovaná pod podkladem.

## Tratě (úroveň 0)

Normály jsou v pořádku na všech tratích, pod silnicí hlavní trasy není nikde prázdno. Varování:

- **Spáry** mezi silnicí a terénem: v alps, industrial a foothills (změřeno) většinou široké do 2 cm, ve foothills až 26 cm, většinou v krajním paprsku šířky SimD. Jsou už v datech originálu. Castle (435) a industrial (301) zatím nikdo neprohlédl.
- **Mimo**: vedlejší úseky SimD, kde řez neleží na geometrii nebo je o několik metrů výš či níž (farmland: úsek 7 leží 5 m pod silnicí `RD0976C`; autobahn, castle a industrial jich mají stovky). Asi jde o trasy jiné verze trati nebo o rozcestí (`.jnc`). Hra jezdí po hlavní trase, takže to zatím nevadí.

| Trať | Trojúhelníky | Otočeno | Proti normálám | Dolů | Díry | Spáry | Mimo | Stav |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| alps | 62053 | 6083 | 0 | 0 | 0 | 18 | 36 | WARN |
| autobahn | 69906 | 10213 | 0 | 0 | 0 | 30 | 2632 | WARN |
| canyon | 61103 | 10543 | 0 | 0 | 0 | 5 | 23 | WARN |
| castle | 122451 | 23723 | 0 | 0 | 0 | 435 | 504 | WARN |
| coastal | 48050 | 8183 | 0 | 0 | 0 | 5 | 18 | WARN |
| farmland | 66538 | 11720 | 0 | 0 | 0 | 3 | 182 | WARN |
| foothills | 61311 | 8069 | 0 | 0 | 0 | 14 | 23 | WARN |
| forest | 67095 | 12608 | 0 | 0 | 0 | 3 | 233 | WARN |
| industrial | 93393 | 11213 | 0 | 0 | 0 | 301 | 1111 | WARN |
| monaco1 | 30321 | 4319 | 0 | 0 | 0 | 0 | 0 | OK |
| monaco2 | 32684 | 4456 | 0 | 0 | 0 | 0 | 0 | OK |
| monaco3 | 37932 | 6286 | 0 | 0 | 0 | 0 | 5 | WARN |
| monaco4 | 46147 | 7320 | 0 | 0 | 0 | 0 | 76 | WARN |
| monaco5 | 32124 | 6108 | 0 | 0 | 0 | 0 | 1 | WARN |
| skidpad | 7314 | 30 | 0 | 0 | 0 | 0 | 0 | OK |
