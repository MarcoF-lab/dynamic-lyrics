# Dynamic Lyrics (clone personale)

Testi sincronizzati di Spotify su iPhone, lock screen, Dynamic Island e **CarPlay** (iOS 26).

Come funziona: l'app interroga Spotify (Web API) per la canzone in riproduzione, scarica il testo sincronizzato da [LRCLIB](https://lrclib.net) (gratis, senza chiave) e mostra la riga corrente in una **Live Activity**. Su iOS 26 le Live Activity appaiono anche su CarPlay — nessun entitlement CarPlay richiesto.

## Setup (una tantum, ~20 minuti)

### 1. Pubblica il repo su GitHub

Fatto: [github.com/MarcoF-lab/dynamic-lyrics](https://github.com/MarcoF-lab/dynamic-lyrics)

### 2. Attiva GitHub Pages (per il login Spotify)

Fatto. Callback OAuth:

```
https://marcof-lab.github.io/dynamic-lyrics/callback.html
```

### 3. Crea l'app Spotify

1. Vai su [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) → **Create app**
2. Redirect URI: l'URL GitHub Pages del punto 2 (esatto, con `callback.html`)
3. API: spunta **Web API**
4. Copia il **Client ID**

### 4. Scarica l'IPA

Il push del punto 1 fa partire la build automaticamente. Su GitHub: **Actions → ultima run → Artifacts → DynamicLyrics-unsigned-ipa** (scarica e de-zippa: dentro c'è `DynamicLyrics.ipa`).

### 5. Installa su iPhone da Windows (Sideloadly)

1. Scarica [Sideloadly](https://sideloadly.io) + iTunes (versione Apple, non Microsoft Store)
2. Collega iPhone via USB
3. Trascina `DynamicLyrics.ipa`, inserisci il tuo Apple ID (gratuito va bene)
4. **Advanced options → spunta "Signing mode: Apple ID"** e lascia che rimappi i bundle id
5. Su iPhone: **Impostazioni → Generali → VPN e gestione dispositivo** → autorizza il certificato sviluppatore
6. **Impostazioni → Privacy e sicurezza → Modalità sviluppatore** → attiva

⚠️ Apple ID gratuito = l'app scade dopo **7 giorni**, va re-installata con Sideloadly. Con account Developer a pagamento ($99/anno) dura 1 anno.

### 6. Configura l'app

1. Apri Dynamic Lyrics su iPhone
2. Incolla **Client ID** e **Redirect URI** (lo stesso URL del punto 2)
3. Accedi con Spotify
4. Metti play su Spotify → i testi appaiono, parte la Live Activity

### 7. CarPlay (iOS 26)

La Live Activity appare da sola su CarPlay quando è attiva. Se non la vedi:
**Impostazioni → Generali → CarPlay → [tua auto]** → verifica che le Live Activity siano abilitate.

## Consigli d'uso

- Lascia attivo il toggle **"Resta attiva in background"**: tiene viva l'app (audio silenzioso, non disturba Spotify) così la Live Activity continua ad aggiornarsi in auto.
- Crea un'**automazione Comandi**: "Quando apro Spotify → Apri Dynamic Lyrics". È lo stesso trucco che usa l'app originale per ripartire dopo che iOS la chiude.
- Se una canzone non ha testo su LRCLIB vedrai "♪ Nessun testo trovato" — capita con brani poco noti.

## Struttura

```
App/      → app SwiftUI: auth Spotify (PKCE), polling player, fetch LRC, sync
Shared/   → ActivityAttributes condivise app↔widget
Widget/   → Live Activity (lock screen, Dynamic Island, CarPlay small family)
docs/     → pagina callback OAuth per GitHub Pages
.github/  → workflow build IPA non firmato su runner macOS
```
