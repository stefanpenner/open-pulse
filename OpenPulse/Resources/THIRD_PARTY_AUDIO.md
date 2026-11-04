# Session audio

**Calming music** plays a soft left/right "tick, tock" during a session, like bilateral tappers.

- The app makes the sound in code (`OpenPulse/Models/BilateralTicks.swift`). No audio file ships.
- Music stays **opt-in** and off by default.
- Local only: no streaming, no accounts.
- Copy says "calming", not medical or "healing frequency" claims.

The old ambient pad (`AmbientCalm.m4a`) was a synthetic placeholder. It was removed because the hum did not sound good.
To add a real track later, check that its license allows bundling in a shipped mobile app.
