# Databáze písniček

Lokální tmavý webový přehrávač a databáze písniček bez nutnosti instalovat jakékoliv knihovny, Node.js ani Python. Běží čistě přes vestavěný Windows PowerShell server a všechny nahrané soubory (audio, cover art, lyrics, playlisty i nastavení) ukládá lokálně do složky `data/` vedle kódu webu.

## Požadavky
- **Windows** (vestavěný PowerShell a moderní prohlížeč – Chrome, Edge, Firefox…). Nic dalšího není potřeba instalovat.
- *(Volitelné)* `yt-dlp` a `ffmpeg` v `PATH` (nebo v `C:\ytdlp\`) – pouze pokud chceš používat automatický import z odkazů YouTube / YouTube Music.

## Jak spustit
1. Stáhni repozitář (`Code → Download ZIP`) a rozbal ho do libovolné složky.
2. Dvakrát klikni na `spustit.bat`.
3. Automaticky se vytvoří prázdná složka `data/`, spustí se lokální server a otevře se web v prohlížeči na `http://127.0.0.1:8080/`.

---

## Hlavní funkce

### Správa písniček, knihovna a ovládání
- **Přidávání, úprava a mazání písniček** – podpora audio souborů (`MP3`, `WAV`, `OGG`, `FLAC`, `M4A`, `AAC`, `OPUS`, `WEBM`), volitelného cover artu (`PNG`, `JPG`, `WEBP`, `GIF`) a textu písničky (lyrics).
- **Rychlý import z odkazu (YouTube / YouTube Music)** – po vložení odkazu stáhne originální nejvyšší kvalitu audia (`.m4a`/`.webm`) bez ztrátového překódování, původní cover art, název, interpreta, album i synchronizované lyrics z LRCLIB. Volitelně lze zaškrtnout **Převést audio do MP3** a **Převést cover do JPG** (volba se pamatuje mezi relacemi); cokoliv chybějícího lze ručně doplnit.
- **Playlisty a Drag & Drop** – vytváření, přejmenování a mazání vlastních playlistů, přidávání písniček do více playlistů najednou, **měnění pořadí písniček v playlistu přetažením myší** i **přetažení písničky přímo na název playlistu** v levé liště.
- **Řazení, hledání a zobrazení** – okamžité hledání podle názvu, interpreta, alba i slov v lyrics; řazení knihovny (*Nejnovější / A–Z / Interpret*); kompaktní karty i seznam; zasouvání/vysouvání levého i pravého panelu.
- **Dvojklik a kontextové menu (pravý klik)** – dvojklik na písničku ji rovnou přehraje; pravý klik otevře rychlou nabídku (*Přehrát*, *Přehrát jako další*, *Přidat/Odebrat z playlistu*, *Najít lyrics*, *Upravit*, *Smazat*).

### Přehrávání a zvukové efekty
- **Fronta „Přehrát jako další“ (Up Next)** – zařadí písničku hned po té aktuální bez nutnosti měnit playlist (s pilulkou `Fronta: N ×` pro snadné vyčištění).
- **Zapamatování poslední písničky a času** – po znovuotevření webu zůstane připravena poslední rozehraná písnička přesně v tom samém čase.
- **Vinyl Pitch (`-12` až `+12 st`)** – krokování po půltónech se zamknutým poměrem výšky tónu a rychlosti (*Vinyl mode*), při zachování přesné synchronizace textu a délky písničky.
- **Reverb (`0–100 %`)** – prostorový efekt v reálném čase přes vestavěné Web Audio API.
- **Shuffle & Repeat** – náhodné přehrávání a opakování (*Vypnuto / Celý seznam / 1 písnička*).
- **A–B smyčka** – nastavení vlastního začátku a konce pasáže, která se bude opakovat dokola.
- **Windows Media Controls** – ovládání pomocí multimediálních kláves na klávesnici a sluchátkách (`Media Session API`).

### Synchronizované lyrics a překlad
- **Živé zvýrazňování textu** – aktuálně zpívaný řádek se zvýrazní, rozsvítí a automaticky posouvá doprostřed. Kliknutím na libovolný řádek lze přeskočit přímo na dané místo v písničce.
- **Tlačítko „Najít lyrics“** – u už přidaných písniček (v okně *Upravit* nebo přes pravý klik) automaticky dohledá synchronizované `.lrc` přes **LRCLIB** (se zálohou přes **lyrics.ovh**).
- **3 režimy synchronizace** *(indikátor `✓` / `✕` v detailu písničky)*:
  1. Automatické načtení časů ve formátu `.lrc` (`[mm:ss.xx]`).
  2. Vestavěný režim **Synchronizovat** (označování začátků řádků mezerníkem při poslechu + uložení přímo do `lyrics.txt`).
  3. **Auto-odhad** pro obyčejný text bez časových značek.
- **Překlad lyrics** – přeložení textu do vybraného jazyka (s automatickým rozpoznáním původního jazyka) při zachování 100% synchronizace s časem; zobrazení **Obojí / Překlad / Originál**.
- **Celoobrazovkový režim Lyrics (Focus / Karaoke)** – jen dynamické tmavé pozadí reagující na hudbu a velké plynulé lyrics uprostřed bez přeskakování textu (klávesa `L` nebo ikonka zvětšení).

### Vizuál, výkon a nastavení
- **Dynamické barvy z cover artu** – vybírá 2 odlišné barvy přímo ze skutečných pixelů cover artu pro akcenty, glow efekty, tlačítka, checkboxy, vizualizér i ikonu karty v prohlížeči (web zůstává vždy v tmavém režimu).
- **Audio vizualizér** – reaguje na hudbu na pozadí webu, ve spodní liště, na obou místech nebo lze vypnout.
- **⚡ Lightweight Web režim** – úsporný režim v nastavení (`⚙` vlevo nahoře), který skryje cover obrázky, přepne na kompaktní seznam, uvolní canvas vizualizéry, vypne Reverb DSP, dynamické barvy, přechody, gradienty, blur, stíny a omezí překreslování časové osy pro minimální spotřebu RAM/CPU/GPU.
- **Úspora na pozadí** – při přepnutí na jinou kartu prohlížeče se automaticky pozastaví vykreslování vizualizérů a animací při zachování 100% kvality zvuku.
- **Nastavení webu (`⚙`) s trvalým ukládáním** – ukládá se do `localStorage` i `data/settings.json` (výchozí hlasitost 40 %, velikost písma lyrics, krok posunu šipkami, dvojklik, potvrzení smazání, pamatování hlasitosti / Pitch & Reverb / Shuffle & Repeat / poslední písničky).

## Klávesové zkratky
- `Mezerník` – Přehrát / Pozastavit *(v režimu synchronizace označí další řádek)*
- `←` / `→` – Posun v písničce zpět / vpřed (5 / 10 / 15 s podle nastavení)
- `↑` / `↓` – Zvýšit / snížit hlasitost po 5 %
- `M` – Ztlumit / obnovit zvuk
- `L` – Otevřít / zavřít celoobrazovkový režim Lyrics
- `Esc` – Zavřít celoobrazovkový režim Lyrics, kontextové menu, nastavení nebo vedlejší okna

## Struktura projektu
```text
song-database/
├── index.html          # Kompletní rozhraní webu (HTML + CSS + JS)
├── server.ps1          # Lokální PowerShell HTTP server a API
├── spustit.bat         # Jednoklikový spouštěč serveru a prohlížeče
├── .gitignore          # Vylučuje osobní složku data/ z Gitu
├── README.md           # Dokumentace projektu
└── data/               # Vytvoří se automaticky při prvním spuštění (není v repozitáři)
    ├── songs.json      # Databáze metadat všech písniček
    ├── playlists.json  # Uložené playlisty
    ├── settings.json   # Uložené nastavení webu
    └── song_<id>/      # Složka pro každou písničku (audio, cover, lyrics.txt)
```
