# Ruční nahrání na Cloudflare

Soukromá webová verze za heslem (D-041), jen pro tebe a kamarády na testování. Ve složce jsou:

- `bucket/` – soubory hry pro úložiště R2 (v kořeni hra, ve složce `data/` balíčky dat),
- `worker.js` – kód Workeru, který u každého souboru ověří heslo.

Názvy položek v dashboardu Cloudflare se občas mění, podle smyslu je ale najdeš.

## 1. Bucket R2

1. V dashboardu otevři **R2 Object Storage** a zvol **Create bucket**. Při první aktivaci R2 může Cloudflare chtít platební kartu, do 10 GB se nic neplatí.
2. Název například `stuttgart-speed-web`, umístění automatické, **Create bucket**.
3. Veřejný přístup (`r2.dev`, **Public access**, **Custom domains**) nech vypnutý. Obešel by heslo.

## 2. Nahrání souborů

1. V bucketu zvol **Upload** a přetáhni všechny **soubory** z `bucket/` (bez složky `data`).
2. Zvol **Create folder**, pojmenuj ji `data` a otevři ji.
3. Uvnitř `data` zvol **Upload** a přetáhni všechny soubory z `bucket/data/`.
4. Kontrola: v kořeni bucketu je složka `data` a soubory `index.*`, ve složce `data` je `manifest.json` a zipy. Na velikosti písmen záleží.

## 3. Worker

1. Otevři **Workers & Pages**, zvol **Create** a začni prázdným Workerem (**Start with Hello World**). Název například `stuttgart-speed-web`, **Deploy**.
2. **Edit code**: smaž ukázkový kód, vlož celý obsah `worker.js` a zvol **Deploy**.
3. V nastavení Workeru přidej v **Bindings** položku **R2 bucket**: název proměnné přesně `BUCKET`, bucket z kroku 1.
4. V **Settings › Variables and Secrets** zvol **Add**, typ **Secret**, název přesně `GAME_PASSWORD` a hodnota je heslo, které dáš kamarádům. **Deploy**.

Dokud heslo nenastavíš, Worker odmítne každého.

## 4. Hraní

Adresa je u Workeru, má tvar `https://stuttgart-speed-web.<tvůj-subdomén>.workers.dev`. Prohlížeč se zeptá na jméno (může být libovolné) a heslo. Ověřeno v Chromiu.

## Když něco nejde

- **Pořád se ptá na heslo:** zkontroluj název `GAME_PASSWORD` a že je Worker po změně znovu nasazený.
- **Chyba 1101 nebo „Worker threw exception“:** chybí binding `BUCKET`.
- **„Not found“ nebo hra hlásí, že nenašla data:** soubory nejsou ve správné složce, `manifest.json` musí být jako `data/manifest.json`.
- **Soubory se nahrály i se složkou** (v bucketu je jen `bucket/`): nemusíš je nahrávat znovu. V **Settings › Variables and Secrets** přidej proměnnou typu **Text** s názvem `PREFIX` a hodnotou `bucket/` (i s lomítkem na konci) a dej **Deploy**.

## Nová verze hry

Nahraj znovu změněné soubory na stejná místa (přepíšou se). Po novém exportu hry to jsou soubory `index.*` v kořeni, po novém převodu dat změněné zipy a `data/manifest.json`. Worker zůstává.
