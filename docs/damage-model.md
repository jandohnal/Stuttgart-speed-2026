# Model poškození: náš prototyp vs. originál (NFS5)

Stav k 30. 10. 2026, po přiblížení originálu (D-010). Náš model je v `game/scripts/car_damage.gd`, následky v `game/scripts/car.gd` a vypnutí po cíli v `game/scripts/main.gd`. Originál vychází z rozboru `Porsche.exe` (D-023): funkce 0x494000–0x494DF0 (náraz → zóny) a 0x4938A0–0x493CF0 (zóny → díly). Dokument popisuje principy, žádný kód originálu.

## Shrnutí

- **Originál:**
  - Má 10 zón poškození 0–100 %, stejných jako zóny `dz` v modelu auta ([crp.md](formats/crp.md#poškození)).
  - Zónu vybere **směr** nárazu, ne místo dotyku. Síla je úměrná rychlosti do překážky. Zóna si pamatuje **nejtvrdší** náraz (maximum, nesčítá se).
  - Mechanické následky nejdou ze zón přímo. Každý namontovaný díl má masku zón, ze kterých se poškozuje (pole 0x48 v [prt.md](formats/prt.md)).
  - Z dílů vznikne 6 druhů poškození: motor, převodovka, brzdy, pneumatiky, podvozek a aerodynamika. Zhoršují jízdu, po závodě se uloží jako opotřebení a v kariéře se platí oprava.
- **Náš model:**
  - Sčítá impulzy kontaktů (Jolt) a převádí je na změnu rychlosti auta. Práh a měřítko má jako originál.
  - Zónu vybírá podle směru nárazu, stejně jako originál. Sousední zóny dostanou průměr svých sousedů.
  - Zóna si drží nejtvrdší náraz a menší nárazy k ní ještě přidají 30 % svého poškození.
  - Následky čte přímo ze zón. Brzdy a pneumatiky se řeší po rozích, motor a převodovka ze zón kolem motoru, přítlak z předku a zádi.
  - Navíc uvolňuje a odhazuje díly a kola, což originál nedělá. Rychlosti pro uvolnění a utržení se řídí maximální rychlostí auta.
- **Zbývající rozdíly:**
  - Malé nárazy, které se pořád trochu sčítají.
  - Spodek se poškodí při dosednutí (originál ho nepoškozuje nikdy).
  - Rozbíhavost a ztráta kol.
  - Následky po rozích místo průměru celého auta.
  - Žádné opotřebení mezi závody a žádná cena oprav (kariéra zatím není).

## Srovnání

U originálu je rychlost složka rychlosti kolmo do překážky. U nás je to změna rychlosti auta při nárazu. Ta je při čelním nárazu do zdi bez odrazu stejná jako rychlost nárazu: `damage_test` při 20 / 50 / 100 / 125 km/h naměřil 21 / 51 / 100 / 125 km/h.

| Oblast | Originál | Náš model |
| --- | --- | --- |
| Zapnutí | Volba Damage zap/vyp (vše, nebo nic). Poškozuje se jen během závodu, po projetí cílem už ne | Vždy zapnuto. Po projetí cílem se auto (hráč i soupeř) už nepoškozuje, nárazy jen zní. Restart poškození zase zapne |
| Zóny | 10 zón, 0–100 %: 0 předek vlevo, 1 předek, 2 předek vpravo, 3 pravý bok, 4 záď vpravo, 5 záď, 6 záď vlevo, 7 levý bok, 8 střecha, 9 spodek | Stejných 10 zón, 0–1 |
| Výběr zóny | Podle směru normály kontaktu v souřadnicích auta: 8 výsečí kolem auta (rohy, středy, boky). Střecha, když náraz přijde shora. Rozměry v `.tpg` `[damagezones]` exe nečte (řetězce v něm nejsou), jsou to zřejmě data editoru | Jako originál: podle směru nárazu (opačná normála kontaktu v souřadnicích auta), 8 výsečí s hranicí 0,1 příčně i podélně, střecha při nárazu shora (> 0,5). Místo dotyku nerozhoduje. `damage_test` ověřuje všech 10 směrů |
| Síla nárazu | 3 × rychlost do překážky. Tečný náraz (kolmá složka pod 1/8 rychlosti) počítá jen rychlost / 12, odřeniny tedy prakticky nepoškozují. Auto–auto ≈ 4 × rozdíl rychlostí, omezený poměrem hmotností | Změna rychlosti auta za prvních 12 tiků nárazu (0,1 s): součet impulzů / hmotnost. Kontakt s jiným autem se počítá dvakrát (rychlost proti sobě je zhruba dvojnásobek změny rychlosti každého auta). Odřeniny dávají malou změnu rychlosti, takže skoro nepoškozují |
| Práh | Síla nad 20 (zeď): ≈ 24 km/h do překážky. Auto–auto nad 10: ≈ 9 km/h rozdílu. První náraz nad prahem dá hned ≥ 10 % | 24 km/h změny rychlosti (`threshold_kmh`), auto–auto ≈ 24 km/h rozdílu u stejně těžkých aut. První náraz nad prahem dá hned 10 % |
| Plné poškození zóny | Poškození = ½ síly: 100 % při ≈ 240 km/h do zdi, auto–auto při ≈ 180 km/h rozdílu. Ve zvláštním režimu hry ×1,5 (100 % už při ≈ 80 km/h) | Poškození = změna rychlosti / 240 km/h (`full_kmh`). Naměřeno čelně: 30 km/h → předek 12 %, 50 km/h → 21 %, 100 km/h → 42 %, 122 km/h → 51 %, rohy předku vždy polovina |
| Hromadění | **Maximum** ze starého a nového: opakované nárazy stejnou silou poškození nezvětší | Maximum + 30 % menšího z obou (`accumulate`): drobné nárazy se dál sčítají, ale pomalu. Pět nárazů po 20 % dá 20 → 26 → 32 → 38 → 44 % |
| Šíření do sousedních zón | Po nárazu do zóny obvodu (0–7) dostanou sousední zóny aspoň průměr svých dvou sousedů. Střecha a spodek se nešíří | Jako originál: obě sousední zóny obvodu dostanou aspoň průměr svých dvou sousedů (čelní náraz 42 % → rohy předku 21 %). Střecha a spodek se nešíří |
| Střecha (8) | Náraz shora (kolmá složka shora > 0,5), nebo dvě auta zaklíněná do sebe ve vzduchu nad 54 km/h (střecha 50 %) | Náraz shora (směr nárazu nahoru > 0,5). Zaklínění dvou aut ve vzduchu chybí |
| Spodek (9) | Nárazem se nikdy nepoškodí | Náraz zespodu (směr dolů > 0,7, dosednutí) jen do spodku, s 0,2 změny rychlosti |
| Deformace | Posuny vrcholů `vt 0x8000` × poškození zóny. Volitelně textury poškození (volba „textured damage“) | Stejné posuny jako blend shapes `dz<zóna>`. Textury poškození nepoužívá |
| Díly mezi zónami a následky | Poškození dílu = průměr zón z jeho masky × (1,5 − odolnost dílu / 200) + opotřebení z minulých závodů. Odolnost (pole 0x60) je 70–100 %, sériový díl 100 % → ×1,0, nejméně odolný ×1,15 | Nemá díly, následky čte přímo ze zón |
| Motor | Maska podle uložení motoru (vzadu zóny 4–6, vpředu 0–2, uprostřed 3–7), v průměru je navíc vždy zóna 1. Moment × (1 − poškození / 300), tedy až −33 %. S pravděpodobností poškození / 300 v každém tiku otáčky nestoupnou (motor „škytá“) | Poškození motoru = max(střed, ½ roh) zón u motoru. Moment až −33 %. Výpadky po 0,1 s, kdy motor nedává moment a otáčky nestoupnou, až 33 % času (při 100 % poškození v průměru 3,3 výpadku za sekundu) |
| Převodovka | Maska jako motor. Hnací síla × (1 − poškození / 200), až −50 %. Brzdění motorem až ×3. S motorem dohromady tedy zbývá až **třetina** výkonu | Stejné poškození jako motor. Hnací síla až −50 %, brzdění motorem až ×3. Zadní zóny 356 A na 100 %: moment 67 %, převodovka 50 %, výpadky 33 % času |
| Brzdy | Maska 4 rohy (0, 2, 4, 6), průměr pro celé auto. Brzdná síla × (1 − poškození / 200), až −50 % | Po rozích: brzda kola × (1 − ½ poškození jeho rohu), až −50 %. Poškozený roh brzdí méně a auto při brzdění táhne na zdravou stranu |
| Pneumatiky | Maska 4 rohy, průměr pro celé auto. Přilnavost všech kol × (1 − poškození / 200), až −50 %. Od 30, 45 a 60 % jiný zvuk pneumatik | Po rozích: přilnavost kola × (1 − ½ poškození jeho rohu), až −50 %. Zvuk se nemění |
| Podvozek (pružiny, tlumiče, stabilizátory) | Průměr dílů z rohů. Náhodné cukání řízením až ±¼ poškození v jednotkách ±127 (při 100 % ≈ ±20 % rejdu), pod 54 km/h úměrně menší. Kola kmitají podle otáčení (nejspíš jen vizuálně, neověřeno) | Rozbíhavost až 3° na poškozeném rohu (auto táhne na stranu), házení kola až 8° od 50 % rohu |
| Řízení | Jen cukání z podvozku | Rejd −20 % podle zóny 1 |
| Aerodynamika | Jen u aut s díly aerodynamiky (spoiler zóna 5, zástěrky předek a záď). Přítlak × (1 − poškození / 200) | Přítlak vpředu × (1 − ½ zóny 1), vzadu × (1 − ½ zóny 5), až −50 %. Jen u aut s přítlakem v datech. Navíc odpor vzduchu +15 % × průměr všech zón |
| Odpadávání dílů a kol | Ne | Kapota, víko motoru a dveře se uvolní na pantech nad 50 % předku nebo zádi, nebo hned při nárazu z 80 km/h. Kapota a víko se utrhnou při nárazu ze 130 km/h. Obě rychlosti platí pro 356 A 1.6 (100 mph) a násobí se poměrem maximální rychlosti auta (`speed_factor`): 356 1.1 (87,5 mph) ×0,88, 550 Spyder (150 mph) ×1,5. Ostatní díly odpadnou při 100 % zóny. Kolo odpadne při 100 % rohu i boku |
| Vyřazení | Ve zvláštním režimu (×1,5) je auto vyřazené, když všech 8 zón obvodu přesáhne 30 %. Factory Driver má limit poškození | Ne |
| Trvalost a oprava | Po závodě se poškození dílů uloží jako opotřebení (nejvýš 100) a zóny se přenesou do dalšího závodu. Oprava v garáži po kategoriích: motor, brzdy, převodovka, zavěšení, tlumiče, karoserie, stabilizátory, pneumatiky, vzhled | `repair()` při restartu, bez ceny |
| Soupeři | Soupeř s poškozeným předkem (průměr zón 0 a 2) jede pomaleji: cílová rychlost ÷ (1 + poškození / 150), až −40 % | Stejné následky jako hráč, cílová rychlost řidiče se nemění |

## Co zbývá k ladění (D-010)

- **Ověření přes Wine:** změřit pár nárazů do zdi při 30, 60 a 120 km/h a srovnat poškození a ztrátu výkonu.
- **Úhel výsečí:** hranice 0,1 dělá z většiny šikmých nárazů rohy (už od ≈ 6° od přímého směru). Tak to má i originál, ale stojí za ověření přes Wine. Rozbíhavost, přilnavost a brzdy kol při čistě čelním nárazu dostanou jen polovinu poškození předku.
- **Pomalejší poškozený soupeř** z originálu chybí.
- **Opotřebení dílů a cena oprav** patří ke kariéře, která zatím není.

## Nejisté

- Význam zvláštního režimu s poškozením ×1,5 a vyřazením (globální příznak hry, pravděpodobně síťová hra nebo vyřazovací závod).
- Přesný vzorec síly při srážce dvou aut (omezení poměrem hmotností).
- Zda kmitání kol z poškozeného podvozku mění fyziku, nebo jen polohu kola v obraze.
- Časový krok originálu pro výpadky motoru: náš převod „poškození / 300 za tik“ na podíl času je odhad.
