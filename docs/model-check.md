# Kontrola modelů z originálu

Výsledky `tools/mesh_check.py` z 18. 10. 2026, auta 19. 10. 2026 (D-016, D-022), jen čísla, žádná data originálu. Opakuje se po každém převodu (příkazy v [tools/README.md](../tools/README.md#pořadí-pro-hru)). Proč a jak převodník trojúhelníky otáčí: [formats/crp.md](formats/crp.md#díl-pr).

**Sloupce:** *otočeno* = trojúhelníky, které převodník otočil (auta podle uložených normál, tratě nahoru nebo podle sousední plochy); *proti normálám* = trojúhelníky, které po převodu nesouhlasí s normálami (práh 0,5 %); *zahozeno* = trojúhelníky s indexem mimo rozsah (musí být 0); *dolů* = plochy silnice a terénu s normálou y < −0,1; *díry* = paprsky přes šířku silnice hlavní trasy bez čehokoli pod sebou (musí být 0); *spáry* = prázdno užší než 0,3 m nebo v krajních 0,25 m šířky SimD; *mimo* = minutí na vedlejších úsecích, na koncích úseků (5 řezů) nebo s povrchem víc než 5 m od výšky řezu.

## Auta (úroveň 1)

Stav 19. 10. 2026 po zavedení stylů (D-022): glTF obsahuje díly všech stylů modelu, kontrola překryvů a otevřených hran běží pro každý styl zvlášť jen s díly, které styl ukazuje. 39 OK, 5 WARN, žádný FAIL. Celkem 112 222 trojúhelníků ve všech stylech, převodník jich 3 432 otočil podle normál.

**Sloupce navíc:** *styly* = počet `[styleN]` (– = model bez stylů); *otevřené hrany* = délka hran jen s jedním trojúhelníkem (svary do 1 mm), rozsah přes styly – karoserie originálu jsou z panelů, takže nula není cíl, ale styly jednoho modelu by se měly lišit jen svými díly; *překryvy* = dvojice dílů se 10 a více trojúhelníky ve stejné rovině a stejném směru (z-fighting), kromě dílů položených na jiné záměrně (obtisky, světla, značky, kliky, stěrače, stíny kol, vnitřní a vnější panel víka). *Proti normálám* jsou teď jen vnitřní panely víek na ohnutém okraji (61 trojúhelníků ve všech autech): převodník jim normály přepočítá z ploch a na ostré hraně vyhlazená normála nesouhlasí; ovlivní jen stínování panelu zespodu.

| Auto | Trojúhelníky | Styly | Otočeno | Proti normálám | Zahozeno | Otevřené hrany (m) | Překryvy | Stav |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 356_1 | 3602 | 2 | 130 | 10 | 0 | 144–145 | – | OK |
| 356a | 6795 | 12 | 201 | 6 | 0 | 128–143 | – | OK |
| 356b | 6127 | 13 | 134 | 8 | 0 | 129–149 | – | OK |
| 550 | 2985 | 1 | 47 | 0 | 0 | 67–67 | – | OK |
| 901 | 4695 | 7 | 98 | 0 | 0 | 123–135 | – | OK |
| 914 | 2828 | 3 | 20 | 2 | 0 | 125–125 | – | OK |
| 928 | 3410 | 1 | 11 | 2 | 0 | 90–90 | – | OK |
| 930 | 2963 | 2 | 79 | 0 | 0 | 128–128 | – | OK |
| 935 | 2963 | – | 6 | 0 | 0 | 137–137 | – | OK |
| 944 | 4150 | 8 | 298 | 4 | 0 | 103–106 | Body/Engine | WARN |
| 959 | 3016 | 1 | 13 | 0 | 0 | 121–121 | – | OK |
| 964 | 4729 | 8 | 228 | 3 | 0 | 130–133 | – | OK |
| 993 | 4689 | 9 | 196 | 0 | 0 | 122–128 | – | OK |
| 996 | 5010 | 5 | 243 | 0 | 0 | 160–164 | Body/SkirtS, Body1/SkirtS | WARN |
| boxster | 3216 | 3 | 179 | 4 | 0 | 136–140 | – | OK |
| cop356 | 5612 | 4 | 155 | 8 | 0 | 144–161 | Interior1/InteriorRoof1 | WARN |
| cop356_german | 6110 | 4 | 155 | 8 | 0 | 138–158 | – | OK |
| cop930 | 3067 | – | 91 | 0 | 0 | 132–132 | – | OK |
| cop930_german | 3075 | 1 | 91 | 0 | 0 | 138–138 | – | OK |
| cop993 | 2961 | 1 | 100 | 0 | 0 | 124–124 | – | OK |
| cop993_german | 2977 | 1 | 100 | 0 | 0 | 133–133 | – | OK |
| eas1 | 430 | – | 22 | 0 | 0 | 68–68 | – | OK |
| eas10 | 508 | – | 2 | 0 | 0 | 79–79 | – | OK |
| eas11 | 511 | – | 32 | 0 | 0 | 77–77 | – | OK |
| eas2 | 561 | – | 0 | 0 | 0 | 101–101 | – | OK |
| eas3 | 484 | – | 0 | 0 | 0 | 140–140 | – | OK |
| eas4 | 503 | – | 0 | 0 | 0 | 103–103 | – | OK |
| eas5 | 440 | – | 0 | 0 | 0 | 73–73 | – | OK |
| eas6 | 468 | – | 8 | 0 | 0 | 68–68 | – | OK |
| eas7 | 468 | – | 0 | 0 | 0 | 73–73 | – | OK |
| eas8 | 460 | – | 2 | 0 | 0 | 71–71 | – | OK |
| eas9 | 489 | – | 0 | 0 | 0 | 93–93 | – | OK |
| eden1 | 450 | – | 6 | 0 | 0 | 46–46 | – | OK |
| eden2 | 428 | – | 8 | 0 | 0 | 49–49 | – | OK |
| eden3 | 428 | – | 10 | 0 | 0 | 52–52 | – | OK |
| eden4 | 390 | – | 14 | 0 | 0 | 49–49 | – | OK |
| eden5 | 412 | – | 10 | 0 | 0 | 72–72 | – | OK |
| f901 | 3114 | 1 | 83 | 0 | 0 | 132–132 | – | OK |
| f996 | 3172 | 1 | 150 | 2 | 0 | 155–155 | SpoilerDown/TrunkIn | WARN |
| fboxster | 2982 | 3 | 153 | 4 | 0 | 141–141 | – | OK |
| gt1 | 3040 | 1 | 161 | 0 | 0 | 98–98 | DoorIn/Interior | WARN |
| gt2 | 3023 | 1 | 114 | 0 | 0 | 124–124 | – | OK |
| gt3 | 3280 | 1 | 82 | 0 | 0 | 160–160 | – | OK |
| postship | 1201 | – | 0 | 0 | 0 | 34–34 | – | OK |

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

Zbývá (původní data, ne chyba převodu):

- `cop356` styly 2–4 (Hardtop, Speedster, Cabrio): záď za dveřmi existuje jen jako hrubý díl z LOD (`CabrioUp*` od z = 0,45 m) a `Roof1` nemá na úrovni 1 plech střechy, takže za dveřmi chybí boky a hardtop je bez střechy. `nfs5.car` používá pro policejní 356 jen style1 (Coupe), hra jiný nepoužije.
- WARN překryvy jsou jednotlivé díly položené na karoserii jinak, než je seznam záměrných: 996 a f996 boční prahy `SkirtS` na `Body` (16), 996 Turbo a f996 křídlo `SpoilerDown` na víku `TrunkIn` (16), 944 motor na `Body` (10), GT1 výplně dveří na interiéru (17), cop356 Hardtop strop na interiéru (12). Na snímcích nejsou vidět.
- 944 kabriolety (cabrioturbo, S2cabrio) mají za sedadly otevřenou vanu bez krytu složené střechy; v datech jiný díl není.
- Otevřené hrany se ve stylech jednoho modelu liší nejvýš o 26 m (cop356_german, cop356, 356 B: jiná záď kabrioletu); snímky děry neukázaly.

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
