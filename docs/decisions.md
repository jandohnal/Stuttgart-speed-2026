---
type: decisions
updated: 2026-10-19
format: "Každé rozhodnutí má ID, stav (accepted | proposed | superseded), kontext a důsledky."
---

# Rozhodnutí

## D-001 Duchovní nástupce, ne kopie
- **Stav:** accepted
- **Rozhodnutí:** Hra bude mít vlastní název (Stuttgart Speed). Zachovává hratelnost a atmosféru originálu, nekopíruje jeho obsah.
- **Důsledky:** Nepoužívají se loga, názvy ani tvary vozů Porsche. Mechaniky (kariéra napříč érami, mise testovacího jezdce) se přebírají jako nápad.

## D-002 Engine Godot 4.7
- **Stav:** proposed (potvrdit po prototypu jízdy, fáze 2)
- **Rozhodnutí:** Godot 4.7 (původně 4.6, 15. 10. 2026 přechod na tehdy aktuální 4.7.2), fyzika Jolt, renderer Forward+ přes Metal.
- **Důvod:** zdarma (MIT), nativní na Apple Silicon, nejrychlejší vývoj pro jednoho autora.
- **Alternativa:** Unity 6. Unreal 5 zamítnut kvůli náročnosti a slabší podpoře Macu.

## D-003 Vlastní jízdní model
- **Stav:** accepted
- **Rozhodnutí:** Raycast kola nad tuhým tělesem v Jolt, ne `VehicleBody3D`.
- **Důvod:** Charakter jednotlivých aut a „sim-cade“ pocit jde vyladit jen s plnou kontrolou nad modelem pneumatik a přenosem hmotnosti.

## D-004 Fiktivní auta
- **Stav:** accepted
- **Rozhodnutí:** Cílová auta hry jsou fiktivní designy inspirované érami (zadní motor 50. let, klínové tvary 70. let...).
- **Důsledky:** Fyzikální parametry originálu slouží jako reference pro realistické hodnoty dané éry. Výjimka pro první krok: viz D-009.

## D-005 Vlastní tratě ve stylu originálu
- **Stav:** accepted
- **Rozhodnutí:** Tratě se nekopírují. Zachovává se styl: evropská krajina, světlo, otevřené silnice, alternativní cesty. Silnice budou užší než v originálu.
- **Důsledky:** Cílové tratě jsou vlastní. Výjimka pro první krok: viz D-009, kvůli které je exportér alespoň jedné původní trati potřeba.

## D-006 Bez hudby
- **Stav:** accepted
- **Rozhodnutí:** Hra nebude mít hudbu z originálu ani licencovanou hudbu.

## D-007 Zvuky ze samplů
- **Stav:** accepted
- **Rozhodnutí:** Zvuky motorů se skládají z nasamplovaných smyček podle otáček a zátěže (granulární/crossfade syntéza). Zdroje: vlastní nahrávky nebo knihovny s licencí CC0/CC-BY.
- **Důsledky:** Několik typů motorů (např. plochý 4válec, plochý 6válec, turbo) sdílí více aut s jiným doladěním.

## D-008 Data originálu jen lokálně
- **Stav:** accepted
- **Rozhodnutí:** Repozitář je privátní. Veškeré assety z originální hry (a licencované modely) leží v `sources/`, vše rozbalené a převedené v `decomposed/`. Obě složky jsou v `.gitignore` a existují jen lokálně.
- **Důsledky:** Do gitu jde jen kód, nástroje, dokumentace a vlastní obsah. Nástroje čtou ze `sources/` a zapisují do `decomposed/` se stejnou strukturou podsložek.

## D-009 První krok s původním autem na původní trati
- **Stav:** accepted
- **Rozhodnutí:** Prototyp (fáze 2) se staví s jedním původním autem a na jedné původní trati z originální hry, převedenými do glTF ze `sources/` do `decomposed/`.
- **Cíl:** Ověřit, že migrovaná hra funguje a je hratelná. Teprve po splnění tohoto cíle se začne s vlastními tratěmi a vlastními auty.
- **Důvod:** Přímé srovnání s originálem. Stejné auto se stejnými parametry `.sim` na stejné trati umožní objektivně ladit jízdní model, kolize a poškození proti originálu spuštěnému přes Wine. Odpadá také tvorba vlastních assetů před ověřením hratelnosti.
- **Důsledky:**
  - Assety zůstávají jen lokálně v `decomposed/` (D-008). Godot projekt je načítá odtud a nic z nich necommituje.
  - Exportér auta (CRP → glTF) a exportér vybrané trati mají vysokou prioritu.
  - Fiktivní auta (D-004) a vlastní tratě (D-005) zůstávají cílem, ale práce na nich začne až po splnění milníku fáze 2 (hratelný prototyp s původním obsahem).
  - Volba konkrétního auta a trati: viz otevřená otázka v `docs/plan.md`.

## D-010 Poškození s následky a odpadajícími díly
- **Stav:** accepted
- **Rozhodnutí:** Poškození auta má kromě deformace i mechanické následky, které jsou realističtější a závažnější než v originále: rozbíhavost a menší přilnavost kola na poškozeném rohu, ztráta výkonu motoru, větší odpor vzduchu, menší rejstřík řízení. Při plném poškození zóny odpadnou její díly, kola se od poloviny poškození rohu viklají a při plném poškození rohu i boku upadnou. Kapota, kryt motoru a dveře se nejdřív uvolní na pantech (nad 50 % poškození předku nebo zádi, dveře i po tvrdém nárazu) a kapota a kryt motoru se utrhnou při nárazu z 100 km/h.
- **Důvod:** Přání uživatele (17. 10. 2026). Originál díly ani kola neodhazuje.
- **Důsledky:** Prototyp používá díly, které jsou v modelu originálu samostatné (kapota, víko motoru, dveře, světla, značka, výfuk, zástěry). Vlastní auta (D-004) se modelují s oddělenými nárazníky a blatníky, kotevními body a vnitřními plochami. Další návrhy jsou v [IDEA-006](../ideas/severe-damage-wheel-loss.md). Míru následků je potřeba doladit po srovnání s originálem.

## D-011 Zvuky originálu v prototypu, vlastní ve vydání
- **Stav:** accepted
- **Rozhodnutí:** Prototyp (fáze 2) používá zvuky originálu (motor 356 A ze sady `sd1a`, nárazy a pneumatiky ze `SND_coll.bnk`), převedené do `decomposed/` a načítané za běhu. Přehrávač pracuje s popisem sady (`engine.json`: smyčky a otáčky), takže se sada vymění za vlastní samply bez změny kódu.
- **Důvod:** Přímé srovnání s originálem a slyšitelná zpětná vazba (řazení, plyn, smyk) hned, bez čekání na vlastní nahrávky (obdoba D-009).
- **Důsledky:** Zvuky originálu se nikdy necommitují (D-008). Pro vydání platí D-007 a zdroje z [IDEA-004](../ideas/sound-engines-ambience.md); evidence licencí (`assets/audio/LICENSES.md`) vznikne s prvním vlastním zvukem.

## D-012 Žádné placené doplňky
- **Stav:** accepted
- **Rozhodnutí:** Projekt nepoužívá placené doplňky (Godot Asset Library, itch.io, Blender Market apod.). Funkce, které by doplněk řešil, se implementují vlastním kódem nebo se použije bezplatný open-source doplněk s kompatibilní licencí (MIT, BSD, Apache, CC0).
- **Důsledky:** Rozbíjení objektů, látky, částice a podobné systémy se staví z vestavěných funkcí Godotu 4.7 a vlastních skriptů. Použitý open-source doplněk se eviduje i s licencí. Nástroje mimo hru (Blender a jeho vestavěné doplňky, Python knihovny) musí být také zdarma.

## D-013 Mechanické válečkové počitadlo kilometrů
- **Stav:** accepted
- **Rozhodnutí:** Rychloměr má mechanické válečkové počitadlo podle [IDEA-005](../ideas/mechanical-odometer.md): nejnižší váleček (stovky metrů) se otáčí plynule, vyšší se pootočí jen při přenosu z 9 na 0. Jen celkový nájezd v jedné řadě válečků, bez denního počitadla a nulování. Vzdálenost se počítá z otáčení poháněných kol (`Car.odometer_m`), ne z pohybu karoserie. Kreslí se procedurálně v `_draw()` (bez shaderu a textur) ve stylu éry auta podle roku výroby (50., 70., 90. léta). Nájezd se ukládá pro každé auto do `user://odometer.cfg`.
- **Důvod:** Mechanický charakter přístrojů je součást atmosféry dané éry. Procedurální kreslení zapadá do budíků (`gauge.gd`), je ostré v každém rozlišení a nepotřebuje assety.
- **Důsledky:** Při protáčení kol počitadlo přičítá, při smyku s blokovanými koly ne. Kariéra, mise s nájezdem a kokpitový pohled zůstávají jako další kroky v IDEA-005.

## D-014 Výchozí grafické nastavení prototypu
- **Stav:** accepted
- **Rozhodnutí:** Prototyp používá `PhysicalSkyMaterial` (okolní světlo a odrazy z oblohy), tonemapping AgX, SSAO, glow a výškovou mlhu se sun scatter. Slunce pozdního odpoledne má PSSM 4 rozdělení do 500 m, `light_angular_distance` 0,5 a atlas 8192 se středním filtrem měkkých stínů. MSAA 4×, anizotropie 16×, na macOS upscaling MetalFX spatial 0,75. SDFGI, SSR a TAA jsou vypnuté. Odrazy okolí na autě řeší D-018. Materiály modelů originálu doplňuje za běhu `game/scripts/materials.gd` (lak, chrom, sklo, guma, detailní šum trati), bez nových assetů.
- **Důvod:** Měření z 17. 10. 2026 ([IDEA-009](../ideas/graphics-lighting-effects.md), `game/README.md`): na M1 Pro při 3600 × 2260 dá nastavení 55 FPS (kokpit 47) proti 35 FPS s plnou kvalitou. MetalFX 0,75 je na snímcích k nerozeznání od nativního rozlišení, SDFGI stojí třetinu FPS a skoro není vidět, TAA nic nepřidá.
- **Důsledky:** Cílových 60 FPS zatím nejsou. Zbytek dorovnají předvolby kvality (IDEA-009, krok 5): stíny, SSAO, glow a měřítko upscalingu. Na jiných platformách zůstává nativní rozlišení.

## D-015 Asistenti rozjezdu a pohonu: náběh plynu, kontrola trakce, spojka, turbo, samosvor
- **Stav:** accepted
- **Rozhodnutí:** Plyn z klávesy naběhne při rozjezdu za 0,4 s, ve vyšší rychlosti a stupni rychleji (0,15 s), a klesne za 0,1 s. Analogový vstup jde přímo. Kontrola trakce (F6, výchozí zapnutá) bere poháněnému kolu moment, když jeho kombinovaný normovaný skluz přesáhne 0,8 vrcholu pneumatiky, a při 1,05 už mu nedá nic. Funguje pro každé kolo zvlášť a ne při brzdění motorem. Fyzika k tomu dostala spojku při rozjezdu (motor až na 40 % omezovače), turbodíru (plnicí tlak s časovou konstantou podle éry: do roku 1979 0,8 s, do 1994 0,5 s, později 0,3 s) a samosvorný diferenciál pro závodní auta (0x10C ≥ 1,3, 60 % momentu).
- **Důvod:** Plný plyn z klávesy je skok 0 → 1. U 935 (689 Nm) se zadní kola protočila na poměr prokluzu 1,5 (vrchol 0,12) a motor došel do omezovače (diagnostika 18. 10. 2026, `game/README.md`). Takové auto se dá řídit jen dávkovaným plynem, který klávesa nedá. Kontrola trakce je stejný druh pomoci jako asistent řízení (F3) a ABS (F4): „plný plyn“ znamená „tolik, kolik pneumatiky unesou“. Spojka a turbodíra jsou fyzika, kterou model neměl, a dávají autům charakter éry. Samosvor zmenšil protáčení vnitřního kola na výjezdu ze zatáčky.
- **Důsledky:** 0–100 km/h: 935 3,3 s (dřív 4,1 s), 356 15,0 s (dřív 15,5 s). Bez kontroly trakce se 935 na rovince skoro neprotáčí díky turbodíře a náběhu plynu, v zatáčce s plným plynem se ale roztočí. Jak tyto věci řešil originál, ukáže až srovnání přes Wine. Parametry turba a samosvoru jsou hypotézy podle éry a dat `.sim`, ne údaje originálu.

## D-016 Automatická kontrola modelů z originálu
- **Stav:** accepted
- **Rozhodnutí:** Každý převedený model se kontroluje nástrojem `tools/mesh_check.py` (jen čísla, bez snímků): nejvýš 0,5 % trojúhelníků s pořadím proti normálám, žádný zahozený trojúhelník, u tratí nejvýš 0,5 % ploch silnice a terénu mířících dolů a žádné prázdno pod silnicí hlavní trasy. Spáry, okraj šířky SimD, konce úseků a vedlejší úseky jsou varování. Převodník otáčí trojúhelníky podle uložených normál, terén bez normál nahoru (`docs/formats/crp.md`).
- **Důvod:** Přání uživatele (18. 10. 2026): auta bez obrácených normál a děr, tratě bez děr a se správně orientovanými polygony. Originál kreslí oboustranně a jeho pořadí vrcholů není spolehlivé (2,9 % trojúhelníků aut, 28 % terénu farmlandu). Kontrola z čísel stojí méně tokenů než prohlížení snímků.
- **Důsledky:** Modely jsou připravené na kreslení jen předních stran (back-face culling), materiály glTF ale zatím zůstávají oboustranné. Výsledky jsou v `docs/model-check.md` a při každém novém převodu se spouští kontrola.

## D-017 Asistenti, zvuk a diagnostika se nastavují v menu
- **Stav:** accepted
- **Rozhodnutí:** Asistent řízení, ABS, kontrola trakce, zvuk a diagnostika (údaje telemetrie v HUD) jsou přepínače v hlavním menu na jednom řádku mezi výběrem trati a tlačítkem Play. Při jízdě je změnit nejde: klávesy F3, F4, F6 a M jsou zrušené a HUD už stav asistentů neukazuje. Volba se ukládá do `user://settings.cfg` s posledním výběrem auta a trati. Výchozí stav je všechno zapnuté.
- **Důvod:** Přání uživatele (18. 10. 2026). Nastavení patří před start jízdy, ne na obrazovku hry.
- **Důsledky:** Testy spouštějí `main.tscn` bez menu a dostanou výchozí hodnoty, uložené nastavení hráče je neovlivní. Spojka při rozjezdu, náběh kláves a automatická převodovka zůstávají bez přepínače (D-015).
- **Změna 19. 10. 2026:** Asistent řízení, ABS a kontrola trakce jsou ve výchozím stavu **vypnuté**, zvuk a diagnostika zůstávají zapnuté. Důvod: po převzetí brzd, účinnosti převodu a brzdění motorem z dat originálu (D-023) se auta podle uživatele chovají velmi věrně originálu i bez asistentů. Asistenti zůstávají v menu jako volba. Testy teď jezdí bez asistentů: 356 A brzdí ze 100 km/h na 60,2 m (s ABS 58,2 m) a 935 se při rozjezdu neprotáčí ani bez kontroly trakce (max. skluz 0,10, vrchol 0,12). Hráč, který má uložené nastavení v `user://settings.cfg`, si zachová svou volbu.

## D-018 Odrazy okolí v laku a sklech auta
- **Stav:** accepted
- **Rozhodnutí:** Auto s sebou veze `ReflectionProbe` (`materials.gd`, `add_car_reflections`). Je to box 8 × 4 × 8 m ve výšce 0,8 m, zachytí okolí do 300 m a aktualizuje se v režimu `UPDATE_ONCE` (pohyb sondy spustí nové zachycení rozložené do šesti snímků). Meshe auta jsou na vizuální vrstvě 2. Sonda tuto vrstvu nezachytí (`cull_mask`), takže se auto neodráží samo v sobě, a ovlivní jen ji (`reflection_mask`), takže silnice kolem se nemění. Skla mají `BLEND_MODE_PREMULT_ALPHA`: tabule s alfou 0,3 propustí 70 % pohledu dovnitř, ale odraz okolí má plnou sílu.
- **Důvod:** Přání uživatele (18. 10. 2026): odraz okolí v laku a ve sklech. Lak a skla dřív odrážely jen oblohu. SSR na průhledná skla nefunguje a odráží jen to, co je v obraze. S obyčejnou alfou Godot ztlumil i odraz ve skle na 30 %.
- **Důsledky:** Na M1 Pro (3600 × 2260, farmland řez 1284) klesne FPS za autem z 56 na 50 a v kokpitu ze 49 na 41. Kratší dosah (150 m) nic neušetří. Skla teď viditelně odrážejí oblohu a krajinu. Na světlém laku je odraz slabý, převládá bílá barva laku. Interiér dostává okolní světlo ze sondy, takže je tmavší a neutrálnější. Až budou předvolby kvality (IDEA-009, krok 5), sonda bude jedna z položek, kterou jde vypnout.

## D-019 Den a noc podle trati z HDRI oblohy
- **Stav:** accepted
- **Rozhodnutí:** Každá trať má denní a noční HDRI (`assets/hdri/<trať>_<day|night>.hdr`, mimo git, varianty trati s číslem sdílí jeden záznam, záloha podle `data/hdri.json`). Hra ho načte za běhu jako `PanoramaSkyMaterial`, který dává i okolní světlo a odrazy. Směr `DirectionalLight3D` určí nejjasnější místo HDRI (výsledek v `user://hdri_sun.cfg`). Slunce má pevnou energii 1,5 a obloha se škáluje na třetinu jeho osvětlení, protože slunce v HDRI je oříznuté. Příliš jasná špička se kolem sebe ořízne. Noc: měsíc s energií 0,1 a stíny, ztlumená obloha, expozice 1,0, silnější glow, reflektory auta (`SpotLight3D` se stíny, dosah 200 m, sklon −2°, na silnici svítí asi 2× dál než první nastavení; stíny s větším biasem a měkkými okraji PCSS) a zadní světla (emise + `OmniLight3D`, brzdová i ve dne). Denní doba se volí v menu a ukládá s ostatním nastavením. Bez HDRI zůstane procedurální obloha s hláškou v logu. Jen vestavěné funkce Godotu (D-012).
- **Důvod:** Přání uživatele (18. 10. 2026): denní a noční režim pro každou trať z vlastních HDRI. Slunce ve stejném směru jako na obloze dává stíny, které sedí s obrázkem.
- **Doplnění (19. 10. 2026, tvar reflektorů):** Kulatý kužel svítil na strop tunelu stejně jako na silnici. Reflektor má teď kužel 45° a projektor (`light_projector`, textura generovaná v `car_lights.gd`): potkávací světlo do šířky ±38° s ostrou horní hranou 3,5° nad osou (asi 1,5° nad vodorovnou), dolů slábne do 22°. `spot_angle_attenuation` je 3,0, protože nízké hodnoty tlumí i osu kuželu. Energie je 30 místo 17, protože světlo už nesvítí na stěny a stropy. Stojí asi 6 FPS (monaco1 v tunelu 45 proti 51, širší kužel stínů).
- **Důsledky:** HDRI obloha FPS nemění, noc stojí 2–8 FPS kvůli stínům reflektorů (M1 Pro, 3600 × 2260). HDRI farmland a monaco jsou fotky celého prostředí, takže pod obzorem a mezi domy trati je vidět jejich krajina a domy. Lepší je obloha bez země (`*_puresky`). Zadní světla svítí celou texturou zadních světel (i blinkry a couvací) červeně. Pohled z kokpitu se v této fázi neověřuje (`graphics_test` měří jen pohledy za autem).

## D-020 Barva laku z palety originálu
- **Stav:** accepted
- **Rozhodnutí:** Vedle výběru auta je v menu výběr barvy laku. Nabízí „Původní“ (šedobílá textura beze změny, výchozí) a paletu modelu z `FEData/Data/nfs5.car` (19 barev, převodník `tools/car_colors.py`, [formats/car.md](formats/car.md)). Tovární barva varianty je označená „(továrna)“. Barví se jen exteriér, a to celá karoserie jednou barvou: lak (alfa atlasu 204), zóny pruhů (153, 166, 179, 230) a prahy s okraji pruhů (77). Barví se i texely karoserie, které používají obtisky (pruhy 935 na víku motoru). Chrom, světla, potisky obtisků a interiér zůstávají beze změny. Barva se ukládá s posledním výběrem do `user://settings.cfg`.
- **Důvod:** Přání uživatele (18. 10. 2026): vybírat barvy z originálu, jen základní barvu bez obtisků. `.clr` u modelů jsou barvy pruhů, ne lak. Když se barvila jen alfa 204, zůstaly přes auto bílé pruhy (zóny pruhů jsou v textuře šedobílé).
- **Důsledky:** Textura laku se pro zvolenou barvu přepočítá na CPU při načtení auta, jen jednou. Doplňkové barvy palety (pruhy) a barvy interiéru jsou v JSON, ale hra je nepoužívá. Platí jen pro prototyp s auty originálu (D-009). Fiktivní auta (D-004) budou mít vlastní palety.

## D-021 Noční světla tratí z originálních září
- **Stav:** accepted
- **Rozhodnutí:** Světla tratí se berou z originálu: poloha z podpoložek `ef` článků trati (`<trať>_lights.json` z `tools/track2gltf.py`, [formats/crp.md](formats/crp.md#efekty-ef-článku)), vzhled a blikání z `GameData/Render/flare.dat` (`flares.json` z `tools/flare.py`, [formats/flare.md](formats/flare.md)). Hra (`game/scripts/track_lights.gd`) kreslí každou záři jako dva aditivní billboardy (jádro a svatozář, textury `common.fsh`). Záře ve světě jsou v jednom `MultiMesh` na ID a vrstvu, záře na rozmístěných objektech visí na jejich tělese a padají s ním (kozy). Blikající záře sdílí jeden čas (60 tiků/s, střídavé `wrna`/`wrnb`, běžící šipky). V noci 12 `OmniLight3D` bez stínů přeskakuje každých 0,25 s na rozsvícené záře nejblíž kameře, aby lampy svítily i na silnici. Ve dne záře svítí slaběji a bez světel. Tunel monaco1 a monaco2 záře nemá, lampy jsou namalované v textuře stěny. Ty zůstávají bez emise: strop tunelu používá pás lamp z textury, takže i slabá emise rozsvítila celý tunel do bíla (19. 10. 2026, připomínka uživatele). V noci svítí jako emise jen nejjasnější pixely oken (`win*`) a neonů (`neo*`) Monaka. Jen vestavěné funkce Godotu (D-012).
- **Důvod:** Přání uživatele (19. 10. 2026): najít v datech originálu světla Monaka (blikající oranžová světla na kozách, světla v tunelu) a použít je. Data je mají pro všech 15 tratí, takže stejný kód svítí i na ostatních (autobahn 463 září, industrial 700).
- **Doplnění (19. 10. 2026, lampy a kozy Monaka):** Lampy s vymodelovaným sklem (záře `lamp`, `lmpy`, `strg`, `stry`) vypadají jako zadní světla auta. Sklo svítí emisí (textury `inlp`, `trl4`, `lmp1`, `lyte`, energie 3–4, teplý odstín) a halo kreslí glow prostředí. Z záře zůstane jeden malý billboard, který blíž než 8 m zmizí. Každá lampa má vlastní teplé `OmniLight3D` (2 700 K, energie 1,4, dosah 16 m, útlum 0,5) s útlumem podle vzdálenosti od kamery (45 + 15 m) místo přeskakující skupiny. Kozy: oranžová čočka v textuře `abda` svítí a bliká s `wrna` (maska sytě oranžových pixelů), billboard má 40 % velikosti. Čočka, billboard i světlo mají jednu jantarovou barvu (1; 0,5; 0,08) s nízkou energií, protože jasnější oranžová se v tonemappingu ořízla do bíla a vlastní barva záře `wrna` barvila dlažbu do červena. Okna (`win*`) svítí celou texturou přes kontrastní křivku (gama 2,6), teplým odstínem (1; 0,72; 0,42) a energií 2,0 (vybráno ze tří variant). Rozsvícené pokoje za sklem tak zůstanou vidět a glow dostanou jen nejjasnější místa. Maska jasných pixelů propouštěla skoro celé světlé okno jako plochou bílou. Skupina 12 světel pro ostatní záře má dosah 7 m a energii 0,5, protože kozy předtím zbarvily celou ulici do oranžova.
- **Důsledky:** Noc stojí 1–3 FPS navíc (M1 Pro, 3600 × 2260: monaco1 50,8 proti 52,7, industrial 48,1 proti 49,7). Rychlost tiků a jednotka velikosti jsou odhad, doladit proti originálu (Wine). Záře mají test hloubky, takže je zakryjí zdi, ale svítí i přes mlhu. Předlohy (kozy, kužely, `EndWall`) mají záře v `library` podle značky, pro rozestavení úloh z `_stNN.scn`. Zdroje částic (hydranty, fontány) a stíny `ef` hra zatím nepoužívá.

## D-022 Varianty aut ze stylů originálu
- **Stav:** accepted
- **Rozhodnutí:** Auta originálu se převádějí se všemi variantami jejich modelu. Varianta je styl z `<model>.tpg` (`[styleN]`: typ dílu pro každý geometrický slot a podmínky alternativních textur `[fileN.<položka>]`, [formats/crp.md](formats/crp.md#styly-varianty-modelu)). `tools/crp2gltf.py` dá do glTF díly všech stylů a zapíše `<model>_styles.json` (pro každý styl uzly k odebrání a vlastní atlasy, stejné atlasy sdílené). Styl varianty z menu je bajt 0x1C0 v `nfs5.car` (`car_colors.json`, `styles` pro každý model), hra ho použije přes `CarStyle.apply` hned po načtení modelu, před materiály a fyzikou. Modely se neslučují: varianty jedné řady už jsou v jednom `.crp`, `gt2` je kopie `993` s jiným `.tpg`, `f901`, `f996`, `fboxster` a `cop*` jsou samostatné úplné modely. Kabriolety mají střechu staženou, pokud data mají obě polohy (`top_up` ji zvedne). Převodník vynechá díly nižší úrovně detailu, které jen zdvojují díly úrovně 1, a vnitřní panely víek otočí od vnějších.
- **Důvod:** Přání uživatele (19. 10. 2026): obletět všechna auta kamerou na skidpadu a najít mezery, překryvy a chybějící polygony, zjistit, jestli modely jedné řady obsahují jen změněné díly a nemají se sloučit, a vše opravit. Převodník bral jen díly typu 0: každý kabriolet, speedster, targa a turbo vypadal jako kupé a Carrera RS 2.7 (f901) neměla karoserii.
- **Důsledky:** glTF aut je větší (356 A 6 795 trojúhelníků místo 3 116, 23 atlasů místo 11), hra si nechá jen díly stylu. Kontrola modelů (`car_orbit_test`, `mesh_check.py` pro každý styl) je v [model-check.md](model-check.md#styly-a-překryvy-dílů). Výsuvný spoiler (`SpoilerUp`), animace střechy, tuningové balíčky (`packages.ini`) a řidič zatím nejsou. Styly 2–4 policejní 356 mají v datech neúplnou záď, hra je nepoužívá. Platí pro prototyp s auty originálu (D-009).

## D-023 Rozbor Porsche.exe v Ghidře (+ REA) pro význam dat originálu
- **Stav:** accepted
- **Rozhodnutí:** Význam polí a struktur dat originálu se smí zjišťovat rozborem `Porsche.exe` v Ghidře (zdarma, Apache 2.0). Používá se headless Ghidra s vlastními skripty a REA (MIT) jako MCP server Claude Code pro cílené dotazy. Hopper ani IDA se nepoužívají (D-012).
  - **Analyzuje se jen** `Porsche.exe` z oficiálního patche EA (5. 6. 2000, nešifrovaný), uložený v `sources/`. `PORSCHE.ICD` je chráněný SafeDisc a nepoužívá se. Žádná ochrana se neobchází.
  - **Výstupy Ghidry** (projekt, výpisy dekompilace, snímky REA) patří jen do `decomposed/ghidra/` (D-008).
  - **Do repozitáře** se zapisují jen popisy formátů, významy polí, adresy funkcí a principy slovy (`docs/formats/`). Nikdy ne přepsaný ani dekompilovaný kód originálu (D-001), ani doslovné tabulky konstant převzaté pro hru.
  - **Postup:** najít načítací funkci podle řetězce s příponou souboru, jednorázově vypsat dekompilaci všech funkcí a cíleně hledat offsety struktur. REA je na jednotlivé funkce a reference.
- **Důvod:** Pilot z IDEA-012 (19. 10. 2026) za asi 45 minut určil význam téměř všech polí `.sim` ([formats/sim.md](formats/sim.md#analýza-porscheexe-ghidra)). Zároveň vyvrátil tři hypotézy, které prototyp používal: 0x058 není setrvačnost motoru, 0x104 je přímo v m/s², 0x10C/0x110 se násobí 0,001. Porovnáváním aut by se to nedalo zjistit.
- **Důsledky:**
  - Nástroje běží jen lokálně na Macu, mimo repozitář: Ghidra a OpenJDK 21 přes Homebrew, Node 24 v `~/.local/opt` (REA nepodporuje Node 25), REA registrovaná v `~/.claude.json`.
  - Další kandidáti: formáty tratí (`.key`, `.edg`, `.jnc`, `SimD`), profily soupeřů `.ais`, přiřazení zvukových sad motoru, poškození.
  - Z principů originálu se staví vlastní implementace, kód se nepřepisuje.

## D-024 Díly aut: Stock / Sport a volba pneumatik
- **Stav:** accepted
- **Rozhodnutí:** Místo obchodu s jednotlivými díly má menu u auta přepínač **Stock / Sport** (mezi autem a barvou) a pod tratí volbu **pneumatik: sériové / slick / do deště**. Data jsou z originálu (D-009): katalog `FEData/Data/nfs5.prt`, seznam nabízených dílů každé varianty v `nfs5.car` a vzorce z `Porsche.exe` 0x49CB50 ([formats/prt.md](formats/prt.md)). `tools/parts.py` vybere sady do `decomposed/FEData/Data/parts.json`, hra je použije na hodnoty `.sim` při startu (`game/scripts/car_parts.gd`).
  - **Stock** = `.sim` beze změny (díly z továrny jsou neutrální).
  - **Sport** = nejlepší díl z každé skupiny, kterou seznam auta nabízí, včetně výměny celého motoru (např. 356 1100 dostane motor 1500 S) a bez omezení rokem dílu. Pravidla výběru „nejlepšího“ jsou v [prt.md](formats/prt.md#stock--sport-ve-hře-d-024). Vzhled (lak, ráfky, střecha) a pneumatiky se do Sport nepočítají.
  - **Pneumatiky** se volí zvlášť a jen ty, které seznam auta má. Faktor přilnavosti typu pneumatik je zatím jen pro suchý asfalt, poměrem k sériovému typu auta.
  - Auta, u kterých originál díly ignoruje (959, 928, GT2, GT3), mají jen Stock a sériové pneumatiky.
- **Důvod:** Přání uživatele (19. 10. 2026): z dílů originálu jen jednoduchý přepínač, pneumatiky zvlášť. Ze tří voleb pneumatik a z výměny motoru rozhodl uživatel.
- **Důsledky:** Sport u 356 A 1600: 850 → 761 kg, moment 110 → 137 Nm, 0–100 km/h 14,4 → 9,9 s, brzdná dráha ze 100 km/h 60 → 50 m (`drive_test` na skidpadu). Slicky 58,5 m, pneumatiky do deště 61,1 m. Konstanty vzorců jsou jen v `parts.json` (D-023). Až budou tratě rozlišovat povrchy a počasí, má se použít celá tabulka povrch × typ pneumatik (sucho/déšť) z exe.

## D-025 Závod od startu do cíle s odpočtem
- **Stav:** accepted
- **Rozhodnutí:** Na tratích se startem a cílem z `_fstart.scn` (`start`, `finish` v `_road.json`) jede hra závod od startu do cíle (`game/scripts/race_timer.gd`).
  - **Start:** odpočet 3-2-1, auto stojí na startovní čáře originálu, drží ho brzdy a sešlápnutá spojka, motor jde vytočit. Stopky běží od GO, ne od průjezdu startovní čárou.
  - **Čas:** součet kroků fyziky (pauza ho zastaví, testy jsou opakovatelné), v cíli dopočítaný na okamžik průjezdu čárou v rámci kroku. Formát m:ss.cc.
  - **Cíl** platí jen ve směru jízdy, v šířce čáry a po průjezdu všech kontrolních bodů (řez silnice každých 50 řezů v okruhu 40 m). Návrat na silnici (R) čas nezastaví.
  - **Nejlepší čas** pro trať a auto v `user://records.cfg`. Backspace = závod znovu (auto na start, oprava, nový odpočet).
  - **Za cílem** se stopky zastaví, hráč auto neovládá (ani R) a auto samo brzdí podél silnice do zastavení, pak stojí na brzdách.
  - **Čáry:** cílová čára jsou dlaždice originálu (`FNSH` z `_fstart.scn`, D-009), startovní čára vlastní bílý pruh (originál ji nemá); obě jako decaly. Auto stojí 3 m za startovní čarou (trigger startu je 2,2 m před řezem, na kterém auto dřív stálo).
- **Důvod:** Přání uživatele (29. 10. 2026): funkční start a cíl se stopkami, start odpočtem místo průjezdu čarou; viditelné čáry a za cílem zastavit hru (ovládání, auto bezpečně zastavit, stopky). Jak start řešil originál při jízdě bez soupeřů, se ověří přes Wine.
- **Důsledky:** Monte Carlo a skidpad start a cíl nemají, jezdí se volně; okruhy s počítáním kol (`lap` v `_road.json`), mezičasy a zvuk odpočtu zatím nejsou. Kontrolní body jsou jen po hlavní trase mezi startem a cílem, alternativní úseky `SimD` se neberou v úvahu.

## D-026 Rejd řízení zmenšený s rychlostí
- **Stav:** accepted
- **Rozhodnutí:** Úhel předních kol je omezený podle rychlosti na rozvor × μ·g / v² + `steer_lock_margin` (1,0) × vrchol směrového úhlu pneumatik, nejvýš `max_steer_deg` (30°). Ke straně smyku smí kola až do směru pohybu přední nápravy plus stejná rezerva (kontrování). Platí pro všechny vstupy a není to asistent (D-017), ale vlastnost modelu jako v originálu. Vypnout jde přes `speed_sensitive_steering`.
- **Důvod:** Uživatel řešil nedotáčivost (29. 10. 2026) a zvolil začít rejdem. Pevný rejd 30° přetáhne přední pneumatiky z klávesnice na 3–6násobek vrcholu směrového úhlu. Originál zmenšuje rozsah řízení s rychlostí (0x0FC, jednotka zatím neurčená).
- **Důsledky:** Na skidpadu při plném rejdu z klávesnice: boční zrychlení +40–60 % (356 A 0,55 → 0,76 g při 60 km/h), auto už nevyjede z kruhu ([driving-model.md](driving-model.md#rejd-řízení-podle-rychlosti-29-10-2026)). Jízda robota v `drive_test` se nemění. Zbývá vyvážení náprav z 0x0F0 místo `rear_grip` 1,12 a nové měření brzdění v zatáčce.
