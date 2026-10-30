---
type: file-format
format: crp
game: "NFS5 (Porsche 2000 / Porsche Unleashed), PC"
location: ["GameData/CarModel/*.crp", "GameData/Track/*.crp", "FEData/Models/*.crp"]
compression: "EA RefPack (QFS), magic 0x10FB"
status: "komprese, kontejner a geometrie aut hotové; tratě: skidpad"
tool: ["tools/archives.py", "tools/crp.py", "tools/crp2gltf.py", "tools/track2gltf.py"]
updated: 2026-10-30
---

# Formát `.crp` – modely aut a tratí

## 1. Komprese (hotovo)

Soubor začíná `10 FB` + 3 B velikost rozbalených dat (big-endian), následuje proud RefPack.
`tools/archives.py refpack` rozbalí auto (`356a.crp`: 3 764 224 B) i trať (`alps.crp`: 6 168 576 B) s přesnou shodou deklarované velikosti.

## 2. Kontejner (hotovo pro auta)

Little-endian. Struktura podle CrpLib z [LibOpenNFS](https://github.com/OpenNFS/LibOpenNFS) (MIT), ověřená na všech 44 autech.

### Hlavička souboru

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | char[4] | `" raC"` (auto) nebo `"karT"` (trať), tj. obráceně `Car ` / `Trak` |
| 0x04 | u32 | bity 0–4 příznaky (0x1A), bity 5+ počet článků (356 A: 181) |
| 0x08 | u32 | počet položek „misc“ (356 A: 87) |
| 0x0C | u32 | offset tabulky článků v jednotkách 16 B (1 → 0x10) |

Za tabulkou článků následují rovnou položky misc.

### Položka (16 B)

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u32 | když příznak & 1: horních 16 bitů ID (2 znaky), dolních 16 index; jinak celé ID (4 znaky) |
| 0x04 | u32 | bity 0–7 příznaky, bity 8+ délka dat v bajtech |
| 0x08 | i32 | počet prvků |
| 0x0C | u32 | offset **relativně k začátku položky**; když je délka 0, jde o seznam podpoložek a offset je v jednotkách 16 B |

### Článek (`Arti`) = jedna část auta

| ID | Index | Obsah |
| --- | --- | --- |
| `Name` | 0 | jméno části (`Body`, `HoodOut`, `WheelFront` ...) |
| `Base` | 0 | 0x0C počet úrovní; 0x44 info (GeomIndex, TypeIndex ... LevelIndex na +10); 0x64 seznam úrovní po 12 B (úroveň na +8) |
| `vt` | úroveň \| animace << 4 \| 0x8000 poškozené | vrcholy x, y, z, 1 (f32 ×4); s 0x8000 **posuny** vrcholů pro plně poškozené auto (x, y, z, 0), viz [Poškození](#poškození) |
| `nm` | dtto | normály (f32 ×4) |
| `uv` | úroveň | texturové souřadnice (f32 ×2) |
| `pr` | úroveň << 12 \| číslo dílu | díl (trojúhelníky jednoho materiálu) |
| `tr` | úroveň | matice 4×4 (f32, Direct3D, řádky = osy, posun ve floatech 12–14); u aut jen posun (dveře, kapota, kola), u objektů tratí úplné umístění (rotace, měřítko, poloha) |
| `$n` | úroveň | culling |
| `dz` | úroveň | zóny poškození: které vrcholy patří do které zóny, viz [Poškození](#poškození) |
| `ef` | | efekt (světlo, odlesk) – nemá geometrii |

Úrovně: 1–2 model do menu („fe“), 3–7 herní LOD („ig1–ig5“). GeomIndex je slot dílu, TypeIndex jeho varianta; kterou variantu slotu auto ukazuje, určuje styl z `.tpg` (viz [Styly](#styly-varianty-modelu)). LevelIndex >> 4 & 8 je řidič.

### Díl (`pr`)

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u16 | typ primitivy: 3 = seznam trojúhelníků, 1 = pruh (triangle strip), 4 = seznam čtyřúhelníků |
| 0x02 | i16 | 0x200 textura, \| 1 okno |
| 0x04 | i16 | index materiálu (`mt` v misc) |
| 0x08 | f32[4] | obalová koule |
| 0x28 | i32, i32 | počet info řádků, počet indexových řádků |
| 0x30 | 16 B × n | info: RMOffs, offset (B), délka (B), typ (0 vrcholy, 1 normály, 2 UV, 0x246E culling), úroveň, ref |
| … | 8 B × m | indexový řádek: index, typ (`vI` 0x4976 vrcholy, `uI` 0x4975 UV), offset do pole indexů |
| … | u8 × m × počet | indexy (1 bajt!) |

Index vrcholu = bajt + (offset info řádku typu 0) / 16, index UV = bajt + (offset typu 2) / 8. U typu 3 tvoří každé 3 indexy trojúhelník. U pruhu (typ 1) tvoří trojúhelník každá trojice sousedních indexů, liché trojúhelníky mají prohozené první dva vrcholy (stejné pořadí oběhu) a trojúhelníky s opakovaným vrcholem se zahazují. Auta mají jen typ 3. Tratě mají pruhy v terénu: farmland 72 dílů, skidpad 13, často s počtem indexů nedělitelným třemi. Dokud se četly jako seznam, posunuly všechny další trojúhelníky téhož materiálu a v terénu byly díry a rubové plochy (ověřeno snímkem u řezu 1284). Pruh potvrzuje orientace: 91 % jeho trojúhelníků míří nahoru, při čtení jako seznam 50 %.

Typ 4 je seznam čtyřúhelníků: každé 4 po sobě jdoucí rohy jsou jeden čtyřúhelník (v rovině: odchylka 0–0,03 proti 0,22 u posunutých čtveřic), převádí se na trojúhelníky (a, b, c) a (a, c, d). Mají ho hlavně objekty knihovny (desky dopravních značek, krabice, postava, vrtulník v alps), farmland 28 dílů.

**Pořadí vrcholů (orientace) není v originále spolehlivé.** Originál kreslí oboustranně, takže mu to nevadí: u 356 A má 4 % trojúhelníků pořadí v rozporu s uloženými normálami (`nm`), polovina `HoodIn` a `TrunkIn`, části `Decal` a `Body`. Napříč všemi 44 auty je to 2 590 z 89 557 trojúhelníků (2,9 %). Normály jsou konzistentní (u `HoodIn` všechny nahoru), pořadí se střídá i uvnitř dílu. Převodník (`crp.article_mesh`) proto trojúhelník, jehož pořadí nesouhlasí se součtem normál jeho vrcholů, otočí. Terén tratí (`CNK…`, `WOBJ … _SECONDARY`) normály nemá a ve farmlandu mířilo dolů 28 % jeho trojúhelníků, a to i v seznamech (typ 3), nejen v pruzích. Díly skupin `road` a `terrain` se otáčejí nahoru (`orient_up`). Svislé stěny (|n.y| < 0,02) přebírají orientaci souseda přes společnou hranu (sousedé se stejnou orientací ji procházejí opačně). Dopočtené normály se nevyhlazují přes hranu ostřejší než 60° (útesy), jinak by stěna dostala normálu od plochy z druhé strany hrany. Výsledky kontroly jsou v [model-check.md](../model-check.md).

**Díly bez indexových řádků** (typ 3 i 4, délka položky jen 0x30 + 4 info řádky): vrcholy a UV jdou za sebou od offsetů v info řádcích 0 a 2 (např. `Sweeper`, typ 3, 252 + 240 vrcholů). Auto 356 má takové 2 trojúhelníky. Levá a pravá polovina dílu bývají dva díly se stejnými UV, ale jiným materiálem.

### Misc

| ID | Obsah |
| --- | --- |
| `mt` | materiál: 0x10 jméno render metody (`CarExt`, `CarExtEnv`, `CarInt`, `CarWheel`, `CarWindow`), 0x28 index texturové stránky (od 0) |
| `sf` | vložený archiv SHPI ([fsh.md](fsh.md)), index = pořadí souboru v `.tpg` (od 0) |
| `RMth`, `BndP`, `Wndo` | render metody, ohraničující roviny, okna – nepoužito |

## 3. Textury aut

`<auto>.tpg` (INI) obsahuje `fileN=exterior.fsh ...` a sekce `[tpageN.details]` (šířka, výška, `sourcetpage`, `mirrortpage`). Stránky se číslují postupně, stránka se `sourcetpage` nemá vlastní soubor a je kopií zdrojové (u 356 A tpage2 = kopie tpage1 pro pravou stranu, kvůli vlastnímu poškození). Ostatní stránky berou soubory v pořadí.

Stránka je atlas 256×256 (nebo podle `.tpg`) složený z položek SHPI na jejich pozici (pole „pozice“ v hlavičce záznamu). Více položek na stejném místě jsou alternativy, které vybírá styl (sekce `[fileN.<položka>]`, viz níže). Soubory, které nejsou v `.crp` (`Suit`, `Head`, `Cabrio`), leží jako `.fsh` vedle něj.

### Styly (varianty modelu)

Rozluštěno 19. 10. 2026. Originál staví všechny varianty jednoho modelu (kupé, kabriolet, speedster, targa, turbo, Carrera RS) z jednoho `.crp`. Varianta = **styl** v `.tpg`; který styl má auto z menu, říká bajt 0x1C0 v `nfs5.car` ([car.md](car.md)).

- `numstyles=N` a sekce `[styleN]` (**nejsou v pořadí čísel**): `name=`, `count=`, pak dvojice `geometryK=<slot>` / `typeK=<typ>` (slot ukazuje díly s TypeIndex = typ; slot, který styl neuvádí, ukazuje typ 0; typ, pro který model díl nemá, slot vyprázdní – např. střecha `Roof` u kabrioletu) a `textureK=<texturový slot>` / `typeK=<typ>` (výchozí typ 0).
- `[fileN.<položka>]` (N = soubor v `[header]`, od 1; jména se opakují a slučují): podmínky alternativní položky SHPI. `count=` dvojic `geometryK`/`typeK` nebo `textureK`/`typeK` – položka platí, když aktivní typ slotu odpovídá aspoň jedné dvojici (např. 356 A `top`, `top1`, `top2` podle typu střechy, `rea`/`rea1` podle zádi, `dec6`/`dec7` podle texturového slotu 31). `frontend=0/1` a `testdrive=0/1` vybírají textury pro menu a jízdu (kola `whf` = menu, `whg` = hra, `faf`/`fag` rozmazaná kola pro testovací jízdu; sklo `glai`/`glat`). Dál `license=1` (značka), `racedecal=1` (číslo závodního auta), `rotate=1`, `tint=0` a sekce řidiče (`helm`, `fac*`, `suit`, `cas*` na stránkách `suit` a `head`). Položka bez sekce platí vždy.
- Převodník (`crp2gltf.py`) dá do glTF díly všech stylů (jméno uzlu `<díl>_<slot>_<typ>`) a zapíše `<auto>_styles.json`: pro každý styl `hide` (uzly ostatních stylů), `textures` (atlasy odlišné od výchozích, např. `356a_tpage1_style5.png`; stejné atlasy se sdílí) a u kabrioletů `top_up`. Výchozí styl glTF je styl prvního záznamu modelu v `nfs5.car`. Atlasy berou `frontend=1`, `testdrive=0`; stránky řidiče mají jeden atlas. Hra styl použije přes `CarStyle` ([game/README.md](../../game/README.md)).
- **Střecha kabrioletů:** sloty 37 (`Cabrio*`) a 41 (`CabrioUp*` / `CabrioDown*`) jsou celá záď se střechou nahoře a dole a styl uvádí oba. Hra ukazuje jen jeden: nižší (stažená střecha), `top_up` je vymění. Kde mají oba stejnou výšku (356, 356 B, 993, 996: obě zvednuté, stažená existuje jen v LOD), druhý se vynechá.
- **Sloučení modelů není potřeba.** `gt2.crp` je bajtově shodný s `993.crp` (i `gt2D.fsh`), liší se jen `gt2.tpg` (jeden styl „GT2 Racecar“ = style8 993, jiný typ kol). `f901`, `f996` a `fboxster` jsou zmenšené kopie 901, 996 a boxster s vlastním lakem, ne rozdílové modely; `cop*` jsou úplné modely. Varianty jedné řady už jsou v jednom souboru jako styly.
- `packages.ini` (`bandG=T`) zapisuje tuningové balíčky stejně (slot/typ); `nfs5.car` od 0x330 jsou výkonové díly `nfs5.prt`, ne vzhled. Zatím nepoužito.

Textury karoserie jsou šedé a barva laku se v originále dobarvuje. Palety barev jsou v `FEData/Data/nfs5.car` ([car.md](car.md)), `.clr` obsahují jen barvy pruhů.

**Alfa atlasů není průhlednost.** Na stránkách s render metodou `CarExtEnv` odpovídá síle odlesku: lak 204 (pruhy 153, 166, 179, 230, viz [car.md](car.md)), lišty a prahy 77, u 356 A interiér 50, u 935 podvozek 0. Ořez alfou (glTF `MASK`, práh 0,5) proto vyřízl díry: u 935 6 % karoserie, 18 % dveří, pruhy na střeše a víku motoru a 92 % podvozku, u 356 A celá sedadla a 83 % interiéru (ověřeno vzorkováním textury na trojúhelnících, 18. 10. 2026). Skutečný ořez potřebují jen obtisky (`Decal*`, alfa 0 mimo obtisk). Hra proto kreslí lak, chrom, interiér a podvozek neprůhledně (`game/scripts/materials.gd`), světla mají ořez zatím ponechaný (12–39 % plochy, neověřeno).

**Překryvy ploch.** Strop interiéru 935 (`Interior`, normály dolů) leží přesně v rovině střechy (`Body`, y ≈ 1,06 m). Oboustranný materiál zezhora ukazoval rub stropu přes střechu (z-fighting), a protože zóna střechy promáčkne karoserii až o 0,20 m a strop méně, při poškození strop střechu prorazí (66 protnutých dvojic trojúhelníků). Interiér se proto kreslí jen z lícové strany. Ostatní protnutí na obou autech jsou modelovaná (pneumatika v kole, zrcátka ve dveřích, křídlo 935 v karoserii). Vnitřní panely víek (356 A `HoodIn`, `TrunkIn`) mají v originále normály vnějšího panelu a pořadí vrcholů smíšené; převodník je otáčí od vnějšího panelu (viz převod níže).

### Poškození

Každý díl auta má ke každé úrovni dvě položky:

- `vt` s indexem `0x8000 | úroveň`: posun každého vrcholu pro plně poškozené auto (stejný počet jako `vt` úrovně, w = 0, u 356 A 0–0,29 m; některé vrcholy 0). Nejsou to polohy.
- `dz` s indexem úrovně: přiřazení vrcholů do zón.

| Offset | Typ | Obsah |
| --- | --- | --- |
| 0x00 | u32 | počet zón v dílu (n) |
| 0x04 | n × (i32, i32, i32) | zóna, počet vrcholů, začátek v seznamu níže |
| 0x04 + 12 n | u32 × … | indexy vrcholů seskupené podle zón |

Délka = 4 + 12 n + 4 × počet vrcholů dílu (ověřeno na všech dílech 356 A). Poškozená poloha = vrchol + d(zóna) × posun, d ∈ ⟨0, 1⟩.

Zóny na 356 A (těžiště v glTF, předek −Z, vpravo +X); posuny míří dovnitř auta (71–100 % vrcholů zóny):

| Zóna | Místo | Těžiště (m) | Max. posun |
| --- | --- | --- | --- |
| 0 | předek vlevo | (−0,53; 0,49; −1,59) | 0,28 |
| 1 | předek uprostřed (kapota) | (−0,05; 0,61; −0,61) | 0,14 |
| 2 | předek vpravo | (0,54; 0,49; −1,59) | 0,29 |
| 3 | pravý bok | (0,62; 0,64; −0,18) | 0,16 |
| 4 | záď vpravo | (0,49; 0,50; 1,53) | 0,14 |
| 5 | záď uprostřed | (0,00; 0,61; 1,20) | 0,18 |
| 6 | záď vlevo | (−0,49; 0,50; 1,53) | 0,24 |
| 7 | levý bok | (−0,53; 0,68; −0,23) | 0,16 |
| 8 | střecha | (−0,16; 0,98; −0,12) | 0,07 |
| 9 | spodek | (0,00; 0,20; 0,08) | 0,18 |

Textury poškození jsou v FSH jako alternativní obrázky na stejném místě atlasu (zatím se nepoužívají).

## 4. Převod do glTF (hotovo pro auta)

```
python3 tools/crp2gltf.py sources/GameData/CarModel/356a.crp decomposed/GameData/CarModel/356a/356a.gltf
```

- Výstup: `.gltf` + `.bin` + `<auto>_tpageN.png`, jeden uzel na část, primitiva podle texturové stránky. Poškození: každý díl má morph target `dz<zóna>` pro každou svou zónu (posuny jen u vrcholů zóny, `mesh.extras.targetNames`, v Godotu blend shapes). `<auto>_damage.json`: zóny s těžištěm, počtem vrcholů a max. posunem a odpojitelné sestavy. 356 A: 51 z 64 uzlů má targety.
- Odpojitelné sestavy (`detachable` v `_damage.json`): kapota (`HoodOut`, `HoodIn`, `DecalHood`), víko motoru (`TrunkOut`, `TrunkIn`, `DecalTrunk`), dveře se zrcátkem po stranách (díly se stejným pivotem `tr`), poznávací značka a díly, které originál modeluje jako jeden mesh pro obě strany (`Light1` světla, `Light3` blinkry, `Light2` zadní světla, `SkirtF`, `SkirtR`, `Exhaust`). Ty se při exportu dělí podle strany trojúhelníku na uzly `_L` / `_R`. Sestava patří do zóny, ve které má nejvíc vrcholů; hmotnost je odhad. Levé a pravé kopie dílů se stejným jménem (dveře, kola) dostanou příponu `_L` / `_R`, aby byla jména uzlů unikátní.
- Jednotky jsou metry, osa Y nahoru, **předek auta je −Z** (stejně jako „dopředu“ v Godotu).
- **Souřadnice originálu jsou levotočivé (Direct3D).** Převod do glTF zrcadlí osu X (`crp.to_gltf`), tím se zároveň otočí pořadí vrcholů trojúhelníků na správnou stranu. Ověřeno: 96–99 % trojúhelníků aut souhlasí s uloženými normálami (před opravou 4 %), volant 356 A je vlevo (−0,29 m), všechny normály silnice skidpadu míří nahoru, vektor „doprava“ v `SimD` = dopředu × nahoru. Bez opravy byly modely zrcadlené (pravostranné řízení) a kolize trati v Godotu nefungovala (paprsek trefil rub trojúhelníku).
- Výchozí úroveň 1 (model do menu, cca 3 000 trojúhelníků), `--level 3` herní LOD, `--all` i nepoužité varianty a řidič.
- Díl bez požadované úrovně se bere z méně podrobné. Některé takové díly jsou jen hrubší kopií něčeho, co úroveň 1 už má, a kreslily by se přes sebe: vynechají se, když jejich slot má díl požadované úrovně se stejnými stránkami (935, 964, GT1 `SideMirrorLeft/Right` vedle `SideMirror`/`GtMirror`, Boxster `SpoilerDown`), nebo když 80 % jejich trojúhelníků leží do 1 cm na dílech požadované úrovně (křídlo `Spoiler` 935 a GT1 je v `Body`, 356 B `InteriorRoof`, fboxster `SkirtF1`). Stejně se vynechá díl požadované úrovně, který je kopií jiného dílu na stejných stránkách (95 % do 1 cm, podobný počet trojúhelníků): `SpoilerW` 964, 993, 996 a Boxster (= `SpoilerDown`), 944 druhé levé zrcátko, 356 A plexi speedsteru. Ostatní díly jen z LOD zůstávají (f901 střecha, běhouny pneumatik, policejní a tovární modely).
- Vnitřní panely víek (`HoodIn`, `TrunkIn`, `MoveSpoilerIn` a jejich varianty `TrunkIn1` ...) leží v rovině vnějších a jejich trojúhelníky míří půl ven, půl dovnitř. Převodník je otočí od vnějšího panelu a přepočítá jim normály, hra je kreslí jen z lícové strany (`materials.gd`, druh `inner`). Dřív u 901 a 914 prosvítala textura zavazadlového prostoru skrz přední víko (z-fighting).
- Vrstvené díly (`Light*`, `HeadLight`, `Decal*`, `License`, `Handle`, `Wiper*`, `WheelShadow*` …) leží v originále v rovině podkladu, často jako kopie jeho trojúhelníků s jinou texturou (944: pruh zadních světel `Light4` = šest trojúhelníků `Body`, karoserie má pod ním lak). Originál je kreslí až po podkladu, ve hře blikaly. Převodník zvedne každý jejich roh, který leží do 1 mm nad podkladem nebo nejvýš 0,5 mm pod ním, na 1 mm po normále podkladu (rovnoběžnost se posuzuje podle ploch u rohu, ne podle vyhlazené normály). Trojúhelník se zapuštěným rohem zůstane, jinak by se naklonil skrz podklad. Cíle poškození jsou posuny, takže se nemění.
  - Vnější panel se hledá podle jména bez čísla varianty a podle jeho začátku (`TrunkIn1` k `TrunkOut`, `TrunkOut1`, `TrunkOut2`). Víko motoru f996 nemá `TrunkOut`, vnějším panelem je křídlo `SpoilerDown`.
  - Otáčí se celý souvislý kus panelu najednou (sousedé přes společnou hranu se svary do 1 mm). Každý trojúhelník do 5 cm od vnějšího panelu hlasuje pro stranu odvrácenou od nejbližšího vnějšího trojúhelníku, s váhou podle plochy a rovnoběžnosti obou trojúhelníků. Při otáčení po jednotlivých trojúhelnících se v ohybu na okraji víka trojúhelník řídil vnějším trojúhelníkem přes ohyb: 356 A měla 32 hran `HoodIn` a 20 hran `TrunkIn` s opačným pořadím sousedů, a uvolněné nebo utržené víko (D-010) mělo zespodu v rozích díry.
- Ověřeno: všech 44 aut se převede bez chyby; 356 A a 996 zkontrolované vizuálně v three.js (tvar, kola, světla, textury vlevo i vpravo sedí).
- Známé nedostatky: lak se barví až ve hře podle zvolené barvy ([car.md](car.md)), textury poškození a animace (výsuvný spoiler `SpoilerUp`, střecha) se neexportují, styly 2–4 `cop356` mají v datech neúplnou záď (viz [model-check.md](../model-check.md#styly-a-překryvy-dílů)).

## 5. Tratě (ověřeno zatím jen na `skidpad`)

Stejný kontejner (`"karT"`), stejné články `Arti` s `Name`, `Base`, `vt`, `uv`, `pr`, `tr`. Parser je společný v `tools/crp.py`.

### Rozdíly proti autům

| Co | Auta | Tratě |
| --- | --- | --- |
| Úrovně detailu | 1–2 menu, 3–7 hra | 0–3, **0 = nejdetailnější** |
| `vt` index | úroveň \| animace << 4 \| 0x8000 | úroveň \| snímek animace << 4 (animované objekty mají až 46 snímků) |
| Normály `nm` | ano | **ne** – dopočítávají se |
| Materiál `mt` +0x28 | index texturové stránky | **4znakové jméno textury** v `<trať>.fsh` (skidpad 107/107, alps 203/204) |
| Render metody | `CarExt`, `CarInt` … | `Opaque`, `Normal`, `FakeSort`, `NormMatState`, `FullAmbMatState` |
| Textury | atlasy | jednotlivé obrázky, opakují se (tiling) |
| `df` | – | 4 B na index dílu, význam neznámý (příznaky / povrch?) |

### Články

Podle jména: `RD…` silnice, `CNK…` krajina po úsecích (v závorce obsah, např. `GRDRAILNPOST_LOD0`, `TREE11_LOD0`), `MESH`, `FARMMID`, `HILL` terén, `tree`, `OAK`, `SHRUB(S)`, `TREEWALL` vegetace, ostatní objekty.

Jméno ale o kolizi nerozhoduje. **Keře** poznáme podle značky v `Base` 0x44: `BUSH` má v `animdefs.txt` `drivethrough=1` a je to jediná průjezdná značka. Jména keřů jsou různá: `SHRUBBYO12`, `SHRABB`, `OBJECT01`, `MESH416`, `CNK0128L (1 BUSH02_LOD0)`, `OBJ0743L (1 BUSHSMALL_RIGID2)`. Podle jména by tak velká část keřů spadla do terénu nebo objektů (canyon 495 `MESH#` v terénu, castle a foothills `CNK… (BUSH…)`). Všechny články `BUSH` mají příznaky 0x0601, zemní terén 0x0611.

Některé kopie téhož modelu knihovny značku nemají (farmland 3 ze 4 `BUSHSMALL_RIGID2`, castle 36 `BUSHMED_RIGID`, foothills 7). Model je jméno v závorce bez čísla kopie a `_LOD#`. Pokud mají všechny označené kopie modelu stejnou značku a příznaky `Base` a neoznačená kopie stejné příznaky, převezme značku od nich (`tag_from_model`). Generická jména bez závorky (`MESH01`, `OBJECT01`) se nedědí, protože se pod nimi míchají keře s terénem. Keře beze značky i bez označeného souseda zůstávají pevné: coastal `Bush`, canyon `CUTELITTLEBUSH`, castle `BUSHY#`. Jestli originál neoznačené kopie srážel, neověřeno (Wine). Hlavička `animdefs.txt` říká, že popisuje jen označené objekty.

Články s `tr` jsou **objekty** s vlastní maticí; vrcholy mají v lokálních souřadnicích. Odpovídají jim cesty v misc `Desc` (`I:\NFS5Tracks\ModelLibrary\Objects\Smackable\…`). Jsou dvojího druhu:

- **Rozmístěné**: `tr` nese skutečnou polohu na trati (vodorovně dál než 50 m od počátku). Farmland 72: 66 dopravních značek (`OBJ0048R (1 curveleft_Rigid1_SGN)` …, značka SIGN), 4 ležící sloupy (`COLUMN_HORIZONTAL`, CLMH) a 2 animované „sweepery“ (SWEE, `Anim`/`Anqt`).
- **Předlohy**: v počátku, jen s malým posunem pivotu (úlomky bedny ±0,7 m, šipky 13 m nahoře). Kužel, auta provozu, nákladní auta, lidé, bedny, šipky, cílová čára, hydrant … Rozmisťují je úlohy (`GEOM_ELEMENT` v `<trať>_st*.scn`, [scn.md](scn.md)) a nejspíš provoz. Farmland 70, skidpad 70 (rozmístěné nemá žádné).

### `Base` článku (trať, 112 B; silnice 136 B)

| Offset | Typ | Význam | Příklad |
| --- | --- | --- | --- |
| 0x00 | u16 | příznaky: 0x0601 objekt, 0x0610 animovaný objekt, 0x0611 terén, 0x8601/0x8610 předloha | |
| 0x0C | i32 | počet úrovní detailu | silnice 3, ostatní 1 |
| 0x14 | f32[3] | obalový kvádr min | |
| 0x20 | f32[3] | obalový kvádr max | |
| 0x2C | f32[3] | střed | |
| 0x38 | f32 | 1.0 | |
| 0x3C, 0x40 | f32 | poloměr obalové koule (2×) | značka 1,94 m |
| 0x44 | char[4] | **značka objektu** = klíč do `animdefs.txt` (kolize, hmotnost, zvuk) a do `GEOM_ELEMENT` v `.scn` | `SIGN`, `CONE`, `SWEE`, `FNSH`, `CLMH`, `BUS` |

Terén a silnice mají značku prázdnou.

### Misc

| ID | Obsah |
| --- | --- |
| `SimD` | řezy silnice po ~6 m, 80 B na řez (tabulka níže) |
| `SimT` | skidpad 1 × u32 (234 = počet řezů?), alps 4 položky |
| `Vis ` | boxy viditelnosti (alps 275 × 24 B) |
| `CmAn` | kamery (`camera00` …), 6340 B |
| `Desc` | cesty ke zdrojovým modelům knihovny objektů |
| `sn` | jméno souboru textur (`skidpad.fsh`) |

### Efekty (`ef` článku)

Podpoložka `ef` článku (stejně jako `Base`, `tr` …) popisuje světla a efekty. Jeden článek jich může mít několik. Převádí `article_effects` v `tools/crp.py`, `track2gltf.py` je zapíše do `<trať>_lights.json`.

| Offset | Typ | Význam |
| --- | --- | --- |
| 0x00 | u32 | druh: **2 = světelná záře** (flare, 44 B), 3 = zdroj částic (56 B), 4 = stín (`Shadow#` na farmlandu, zatím nerozluštěno) |
| 0x08 | f32[3] | poloha; u článku s `tr` lokální (sleduje objekt), jinak ve světě. Zrcadlí se X jako vrcholy |
| druh 2: 0x14 | f32[3] | směr? Skoro vždy (0, 0, 1) |
| druh 2: 0x24 | char[4] | **ID záře pozpátku** (`anrw` = `wrna`), klíč do `GameData/Render/flare.dat` ([flare.md](flare.md)) |
| druh 2: 0x28 | u32 | náhodné hodnoty, nejspíš nevyplněno |
| druh 3: 0x14 | f32 + f32[3] × 2 | 1,0 a dva řádky báze: 0x18 `direction` (v rovině plochy, ze které částice vznikají), 0x24 `up` (směr, kterým částice letí: rychlost `emit.y` systému; vodopády ven a dolů, mlha `WF08` vodorovně, fontány nahoru). Třetí řádek není, na 0x30 už je značka. Obě zapisuje `tools/emitters.py` ([water.md](../water.md#ve-hře-d-033)) |
| druh 3: 0x30 | char[4] | značka zdroje částic **v normálním pořadí**: `HYDR`, `HYDB`, `HYDM` (hydrant), `CSF1`/`CSF2` (fontána u kasina), `BEXP`, `BEXO`, `BPST`, `TRSH` (úlomky) – nejspíš `GameData/Render/particle.ini` |

Ověřeno: světové záře leží u vrcholů svého článku (medián 0,3–0,7 m na monaco1, monaco3, autobahn), záře na `tr` objektech jsou lokální (kozy `SAWH` ±0,44 m vlevo/vpravo, 1,12 m nahoře). Tunelová světla monaco3 jsou ve dvou řadách 6 m nad silnicí, 6,7 m od středu. Někdy záři nese jiný článek, než je lampa (silnice `RD… PRIMARY`, tunel), proto až 20 m od jeho vrcholů.

Záře (druh 2) podle tratí, bez předloh. Navíc každá trať má předlohy `SawHorse_RIGID*` (2× `wrna`), `Pilon` (`wrna`) a `EndWall` (`arwa`–`arwe`) pro rozestavení úloh. `ambient` je z `<trať>.map` (~0,3 = tma):

| Trať | ambient | Září | Hlavní ID (nositel) |
| --- | --- | --- | --- |
| monaco1–5 | 0,30 | 139–241 | `wrna` 14–42 (rozmístěné kozy), `arwa`–`arwe` (`FLASHERS##`, `R_ARROW#`), `strg`/`stry` (lampy `MNCOLAMPPOST`, `BLD_LIGHT`), `lamp` (`LAMP##`, kasino; monaco5 ne), `lmpy` (`HANGLAMP`), `tunb` 40 (tunel, jen monaco3–5) |
| autobahn | 0,30 | 463 | `tuno` 198 (`SUPERTUNNEL`, silnice), `stry` 153 (`ABLAMPPOST`), `helw` 74 (`TUNNEL#B`), `wrna` 31 (kužely, kozy), `arw*` (`CRASHLIGHTS`) |
| canyon | 0,30 | 119 | `cant` (`DOME_LITE`) |
| foothills | 0,29 | 8 | `bldy` (zámek) |
| forest | 0,29 | 0 | jen předlohy |
| industrial | 0,73 | 700 | `bldy` 225, `strg`/`stry`/`strb`/`strr`, `lpol` 97 (`LIGHTPOLE`), `tunb` 37, `nred` 36 (kontejnery, jeřáby), `fred` 10 (blikající na jeřábu), `wrnb` 10 (`FLASHINGSIGN`), `wrna` 11 |
| castle | 0,52 | 291 | `lmpy` 270 (`LAMPWALL`), `swht` 18 a `helr` 3 (tunely) |
| alps | 1,23 | 82 | `tuny` 56 (silnice), `tunb` 20 (tunel), `helf`/`helr`/`helw` (`RESCUEHELI`), `swht` 3 |
| coastal | 0,99 | 29 | `bldy` (`DOME_LITE`) |
| farmland, skidpad | 0,70 / 0,57 | 0 | jen předlohy |

Tunel monaco1 a monaco2 (`MONTUNCEN*`) záře nemá. Lampy jsou namalované v textuře stěny (`ttm1`–`ttm4`). Noční textury Monaka mají i rozsvícená okna (`win*`) a neony (`neo*`).

### `SimD` – řez silnice (80 B)

| Offset | Typ | Význam | Skidpad |
| --- | --- | --- | --- |
| 0x00 | i32 | ? | 0 |
| 0x04 | f32[3] | pozice středu silnice (m) | kružnice r = 223,4 m |
| 0x10 | f32[3] | vektor nahoru | (0, 1, 0) |
| 0x1C | f32[3] | vektor dopředu (směr jízdy) | |
| 0x28 | f32[3] | vektor doprava | |
| 0x34 | i32[3] | příznaky | 98304, 1, 1 |
| 0x40 | f32[4] | šířky (m) | 10, 10, 10, 10 |

**Úseky:** `SimD` není vždy jedna souvislá silnice. Na farmlandu (Normandie) je nejdřív hlavní trasa (řezy 0–1671, 10,0 km), za ní 9 krátkých úseků (48–810 m), nejspíš alternativní cesty a zkratky. Hranici poznáme podle skoku mezi sousedními řezy (> 30 m, běžně ~6 m). Jak se úseky napojují, nejspíš popisuje `.jnc` (zatím nerozluštěno).

Ověřeno na skidpadu: střed řezů leží na středu asfaltu (geometrie `RD` má poloměr 215–232 m, tedy 17 m široký asfalt se středem 223 m), délka 234 řezů = 1 398 m = 2π · 223 m. Čtyři šířky jsou na skidpadu stejné (±10 m = sjízdná plocha včetně krajnic?), na farmlandu většinou 6 m, místy nesymetrické (např. 6; 6,29; 6; 3,15). Význam zatím neurčen.

### Start a cíl – `<trať>_fstart.scn`, `<trať>_bstart.scn`

Textové soubory s bloky `TRIGGER_ELEMENT` (a `GEOM_ELEMENT`, např. startovní brána). `fstart` platí pro jízdu dopředu, `bstart` pro jízdu pozpátku (start a cíl prohozené). Blok `TRIGGER_ELEMENT 5` má řádky:

| Řádek | Obsah |
| --- | --- |
| 1 | pozice (x, y, z) |
| 2 | báze, 9 čísel: dopředu, nahoru, doprava |
| 3 | parametry, první číslo je typ: 2 = start, 1 = cíl; čtvrté číslo je polovina šířky čáry? (farmland 19,2 / 23,9) |
| 4 | dva krajní body čáry (6 čísel) |
| 5 | ? (nuly) |

Farmland dopředu: start u řezu 56, cíl u řezu 1601, závod tedy vede po hlavní trase ve směru řezů (~9,3 km). Skidpad soubor `fstart` nemá.

Směr báze neodpovídá vždy směru jízdy (ověřeno 30. 10. 2026 proti směru řezu u triggeru): cíl coastal a castle míří dozadu (proti jízdě), start autobahn je otočený o 90° a jeho čára (3 m) vede podél silnice. Starty coastal a castle mají čáru jen 3 m, ostatní 19–52 m přes silnici. `track2gltf.py` proto vezme směr řezu (vodorovně), když se směr triggeru liší o víc než 45°, a čáru, která nevede přes silnici, sestaví ze šířek řezu; nahrazené položky jsou v `_road.json` v `fixed`. Hra sčítá průjezd cílem jen ve směru `forward`, takže na coastal a castle se cíl dřív nezapočítal.

### Převod do glTF

```
python3 tools/track2gltf.py sources/GameData/Track/skidpad.crp decomposed/GameData/Track/skidpad/skidpad.gltf
```

- Výstup: `.gltf` + `.bin` + `<trať>_road.json` (všechny řezy `SimD`, `segments` = úseky `{first, last, length_m, closed}`, `start`/`finish` z `_fstart.scn` s nejbližším řezem); textury jsou PNG z `fsh2png` ve stejné složce (chybí-li `index.json`, převedou se).
- Uzly ve skupinách `road`, `terrain`, `vegetation`, `objects`, `drivethrough` (keře: články se značkou, která má v `animdefs.txt` `drivethrough=1`, ať jsou pojmenované jakkoli; mají přednost před skupinou podle jména), `props` (rozmístěné objekty s maticí `tr`, jméno uzlu začíná pořadím `000 …`), `gates` (předlohy, které rozmisťuje `_fstart.scn`: dlaždice cílové čáry `FNSH 0`, `FNSH 1` …, [scn.md](scn.md#umístění-předlohy)), `simd` (červený poloprůhledný pás podle `SimD` pro kontrolu), s `--library` i `library` (předlohy v řadě na z = −60 m).
- `<trať>_objects.json`: pro každý uzel `props` jméno, značka, typ kolize (`smackable`, `box`, `cylinder`, `none`, `static`), hmotnost a průjezdnost z `animdefs.txt`, poloha. V `drivethrough` seznam dílů ve skupině `drivethrough` (jméno, značka, `tag_from_model` u převzaté značky). Průjezdných dílů je na farmlandu 222 (3 se značkou převzatou), alps 195, canyon 550, castle 245 (36), foothills 402 (7), forest 146, coastal 0.
- Matice `tr` se zrcadlí stejně jako vrcholy: S·M·S se S = diag(−1, 1, 1, 1), tedy změna znaménka u prvků 1, 2, 3, 4, 8, 12. Těch 16 floatů čtených po sloupcích je přímo matice glTF.
- `--level` 0–3 (skidpad: 7 314 / 2 636 trojúhelníků pro úroveň 0 / 2).
- Metry, osa Y nahoru, osa X zrcadlená z levotočivých dat (viz výše, týká se i vektorů `SimD`). `Opaque` → neprůhledné, ostatní render metody → alpha MASK.
- Zkontrolováno renderem v Blenderu (pohled shora a zblízka): trať, pneumatikové zdi, pole, stromy, budovy i textury sedí.
- Farmland (Normandie, „French Farmland“): silnice 239, terén 367, vegetace 216 (dnes `drivethrough` 222 včetně 6 keřů z objektů), objekty 175, rozmístěné objekty 72, předlohy 70; 66 538 trojúhelníků, 244/245 textur, 1 995 řezů v 10 úsecích. Ve hře (Godot) ověřeno jízdou, snímky a nárazem do dopravní značky.
- Trojúhelníky otočené dolů (18 % vodorovných v terénu) jsou koruny stromů nad silnicí a střechy (materiály `cbb`, `shrb`, 3 m a víc nad silnicí), jsou tedy správně. Materiály jsou oboustranné.
- Navazující úseky: úsek pokračuje do úseku, jehož začátek je do 20 m od jeho konce se stejným směrem (`next` v `segments`). Okruh z úseku 0 je v `lap` (segments, length_m). Monte Carlo má trasy uložené mimo pořadí: `monaco1` = úseky 0 → 2 → 1 → 3 → 0, 3 713 m. Monaco nemá `_fstart.scn` (start a cíl). `track2gltf.py` mu proto zapíše vlastní `start` = `finish` s `"source": "lap"` (pravidlo v D-025: rovinka nejblíž řezu 0, kde obě stopy `.lsp` vedou do 3 m od středu řezů).
- Ověřené tratě: skidpad, farmland, monaco1 (také monaco2–5 se převedou, okruhy 3,6–5,0 km).
- `<trať>_lights.json`: záře `world` (ve světě, s článkem), `props` (lokální, podle uzlu ve skupině props), `library` (lokální, podle značky předlohy), `emitters` (zdroje částic). Viz [Efekty](#efekty-ef-článku).
- Zbývá: ostatní tratě, význam `df`, šířek a příznaků `SimD`, stíny `ef` druhu 4, animace (`Anim`, `Anqt`, snímky `vt` s indexem animace), předlohy z úloh (`.scn`), `Vis`, `CmAn`.
