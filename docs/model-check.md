# Kontrola modelů z originálu

Výsledky `tools/mesh_check.py` z 18. 10. 2026 (D-016), jen čísla, žádná data originálu. Opakuje se po každém převodu (příkazy v [tools/README.md](../tools/README.md#pořadí-pro-hru)). Proč a jak převodník trojúhelníky otáčí: [formats/crp.md](formats/crp.md#díl-pr).

**Sloupce:** *otočeno* = trojúhelníky, které převodník otočil (auta podle uložených normál, tratě nahoru nebo podle sousední plochy); *proti normálám* = trojúhelníky, které po převodu nesouhlasí s normálami (práh 0,5 %); *zahozeno* = trojúhelníky s indexem mimo rozsah (musí být 0); *dolů* = plochy silnice a terénu s normálou y < −0,1; *díry* = paprsky přes šířku silnice hlavní trasy bez čehokoli pod sebou (musí být 0); *spáry* = prázdno užší než 0,3 m nebo v krajních 0,25 m šířky SimD; *mimo* = minutí na vedlejších úsecích, na koncích úseků (5 řezů) nebo s povrchem víc než 5 m od výšky řezu.

## Auta (úroveň 1)

Všech 44 OK. Bez otočení by jich 2 590 z 89 557 trojúhelníků (2,9 %) mířilo opačně, než říkají normály.

| Auto | Trojúhelníky | Otočeno | Proti normálám | Zahozeno | Stav |
| --- | --- | --- | --- | --- | --- |
| 356_1 | 2934 | 130 | 0 | 0 | OK |
| 356a | 3116 | 128 | 0 | 0 | OK |
| 356b | 3095 | 107 | 0 | 0 | OK |
| 550 | 2985 | 47 | 0 | 0 | OK |
| 901 | 3038 | 90 | 0 | 0 | OK |
| 914 | 2820 | 20 | 0 | 0 | OK |
| 928 | 3410 | 11 | 0 | 0 | OK |
| 930 | 2963 | 79 | 0 | 0 | OK |
| 935 | 3089 | 6 | 0 | 0 | OK |
| 944 | 3026 | 181 | 0 | 0 | OK |
| 959 | 3016 | 13 | 0 | 0 | OK |
| 964 | 3067 | 122 | 0 | 0 | OK |
| 993 | 2815 | 72 | 0 | 0 | OK |
| 996 | 3136 | 121 | 0 | 0 | OK |
| boxster | 2940 | 136 | 0 | 0 | OK |
| cop356 | 3214 | 119 | 0 | 0 | OK |
| cop356_german | 3218 | 119 | 0 | 0 | OK |
| cop930 | 3067 | 91 | 0 | 0 | OK |
| cop930_german | 3071 | 91 | 0 | 0 | OK |
| cop993 | 2940 | 92 | 0 | 0 | OK |
| cop993_german | 2962 | 92 | 0 | 0 | OK |
| eas1 | 430 | 22 | 0 | 0 | OK |
| eas10 | 508 | 2 | 0 | 0 | OK |
| eas11 | 511 | 32 | 0 | 0 | OK |
| eas2 | 561 | 0 | 0 | 0 | OK |
| eas3 | 484 | 0 | 0 | 0 | OK |
| eas4 | 503 | 0 | 0 | 0 | OK |
| eas5 | 440 | 0 | 0 | 0 | OK |
| eas6 | 468 | 8 | 0 | 0 | OK |
| eas7 | 468 | 0 | 0 | 0 | OK |
| eas8 | 460 | 2 | 0 | 0 | OK |
| eas9 | 489 | 0 | 0 | 0 | OK |
| eden1 | 450 | 6 | 0 | 0 | OK |
| eden2 | 428 | 8 | 0 | 0 | OK |
| eden3 | 428 | 10 | 0 | 0 | OK |
| eden4 | 390 | 14 | 0 | 0 | OK |
| eden5 | 412 | 10 | 0 | 0 | OK |
| f901 | 1770 | 81 | 0 | 0 | OK |
| f996 | 3064 | 80 | 0 | 0 | OK |
| fboxster | 2868 | 133 | 0 | 0 | OK |
| gt1 | 3183 | 161 | 0 | 0 | OK |
| gt2 | 2815 | 72 | 0 | 0 | OK |
| gt3 | 3304 | 82 | 0 | 0 | OK |
| postship | 1201 | 0 | 0 | 0 | OK |

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
