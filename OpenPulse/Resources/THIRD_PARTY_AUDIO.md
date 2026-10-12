# Session ambient audio

Open Pulse plays **one optional local loop** when the user enables **Calming music**.

Bundled file the app loads:

- `AmbientCalm.m4a` (name fixed in code — see `AmbientAudioPolicy.resourceName`)

## Buying a track (recommended)

YouTube-style 528 Hz meditation needs a **real production** (reverb, layers, mix), not stock jingles or pure sines.

### Search terms

- `528 Hz meditation`
- `528 Hz ambient drone`
- `solfeggio ambient pad`
- `healing frequency soft` *(for search only — do not use “healing” claims in the app)*

### Good places to buy

| Source | Why | License watch-out |
|--------|-----|-------------------|
| [AudioJungle](https://audiojungle.net/search/528%20hz%20meditation) | One-off WAV, cheap | Prefer **Extended** if required for apps that ship music to many end users — **read the item’s license FAQ before buy** |
| [Envato Elements](https://elements.envato.com/) music | Unlimited downloads on sub | Confirm **mobile app / software End Product** is allowed for that music item |
| [Pond5](https://www.pond5.com/music) | Large library | Check “app / game / software” rights |
| [Music of Wisdom](https://www.musicofwisdom.com/) (and similar meditation labels) | Genre-correct | Ask for **commercial app distribution** in writing |

**Avoid for shipping inside the app:** Epidemic Sound-style *subscription for video platforms* unless their plan **explicitly** allows bundling audio in a distributed mobile binary.

### What to download

- Prefer **WAV or high-bitrate AIFF** (we convert to AAC)
- Stereo, 44.1 or 48 kHz
- Soft, continuous, **no hard ending** (or we fade)
- Length: 2–10 minutes is fine (app loops it)

### Drop-in steps

1. Buy and download the file.
2. Save the **license receipt PDF** next to the audio (for your records).
3. Put the original here (optional archive):

   `OpenPulse/Resources/purchased/YourTrack.wav`

4. Tell the agent (or run):

   ```bash
   ffmpeg -y -i "OpenPulse/Resources/purchased/YourTrack.wav" \
     -c:a aac -b:a 256k -movflags +faststart \
     "OpenPulse/Resources/AmbientCalm.m4a"
   ```

5. Rebuild / reinstall the app.

## App product rules

- Music stays **opt-in**, off by default
- Copy: “soft ambient” / “calming music” — **not** medical or “healing frequency” claims
- No streaming accounts; local file only

## Temporary placeholder

`AmbientCalm.m4a` may be a synthetic pad until a purchased track replaces it.
