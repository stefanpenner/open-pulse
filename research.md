# Stimulation Modes — Research Summary

## BLE Protocol Reality

Reverse engineering (PulseLibre, hydrasparx, parallaxintelligencepartnership) confirms that the Pulsetto device receives **no mode-specific parameters** over BLE. The official app's "modes" (Stress, Anxiety, Sleep, Burnout, Pain) are purely app-side presentation — the device itself only accepts:

| Command | Purpose |
|---------|---------|
| `D\n` | Start both channels |
| `A\n` | Start left channel only |
| `C\n` | Start right channel only |
| `0\n` | Stop |
| `1-9\n` | Set intensity level |
| `Q\n` | Query battery |
| `u\n` | Query charging |
| `i\n` | Query device ID |
| `v\n` | Query firmware version |

Pulsetto claims different carrier frequencies per mode (4,500–5,200 Hz), but these are either fixed in firmware or marketing claims — the app sends no frequency parameters.

**Our levers:** channel selection (A/C/D), intensity modulation (1-9), and duty cycling (start/stop commands) — all orchestrated from the app in real time.

---

## Mode Designs

### 1. Stress Relief — 6 min

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Channel | Bilateral (`D`) | Bilateral safe, theoretically stronger NTS afferent input |
| Intensity | Constant at user-set level | All clinical studies use constant intensity |
| Duty cycle | Continuous (no off periods) | Continuous > 30s/30s for equivalent stim time (Miyaguchi 2024) |
| Pattern | Flat — no modulation | Maximizes stimulation in limited time window |

**Evidence notes:**
- Acute HR effects proven at 1-2 min (Badran 2019: -2.4 BPM with 10 Hz/500 us)
- Meaningful HRV shifts at ~10 min (Chen 2022: RMSSD, SDNN, HF-HRV increases)
- Cortisol suppression requires 30+ min (Cuberos Paredes 2025: 50% reduction at 30 min)
- 6 min is the minimum reasonable duration for effects beyond real-time HR
- No evidence supports intensity ramp-down; habituation data suggests the opposite
- Bilateral vs unilateral: no direct comparison for stress exists, but bilateral is safe (Redgrave 2018 meta-analysis) and doubles afferent input (Yap 2020)

**Evidence grade: Strong**

---

### 2. Sleep — 10 min

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Channel | Bilateral (`D`), slow rotation: D→A→D→C→D | Avoids right-only which may promote arousal via dopaminergic pathways |
| Intensity | Moderate (recommend 3-4), gentle fade last 2 min | 80% of discomfort threshold optimal (Bottari 2024) |
| Duty cycle | Continuous | Bottari 2024 used continuous with best N3/deep sleep results |
| Rotation pace | ~2 min per channel position | Slow, non-alerting rhythm |

**Evidence notes:**
- Clinical insomnia studies use 20-30 min (JAMA Network Open 2024: 30 min 2x/day; Li 2022: 20 min 2x/day)
- Acute HRV effects do occur at 10 min (PeerJ 2022)
- Bottari 2024 found 80% of discomfort threshold paradoxically allowed higher absolute current and produced best N3 outcomes
- **Critical:** Stimulation during the 2nd half of the night reduces deep sleep by 5.5% (Bottari/Williamson 2025) — never stimulate during sleep
- Use within 30 min of intended sleep onset
- Right-sided VNS preferentially activates midbrain dopaminergic nuclei (arousal-promoting) — avoid right-only for sleep
- Intensity fade-out is untested but physiologically aligned with wake→sleep autonomic transition
- Channel rotation is experimental — no published evidence for or against

**Evidence grade: Moderate** (channel rotation experimental; duration below clinical evidence base)

---

### 3. Focus — 6 min

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Channel | Left only (`A`) | 81% of cognitive tVNS studies use left; fMRI shows left modulates temporal/frontoparietal/DMN networks |
| Intensity | Moderate (4-5), bump +1 at midpoint (3 min) | Inverted-U curve well-established (Loerwald 2018); midpoint readjustment prevents adaptation (alertness study 2023) |
| Duty cycle | 30s on / 30s off | Standard in cognitive tVNS research |
| Use as | Pre-task primer (stimulate before work) | Offline > online for spatial working memory (Sun 2021) |

**Evidence notes:**
- Inverted-U dose-response: moderate VNS intensity (0.8 mA) enhanced motor cortex plasticity; both lower (0.4 mA) and higher (1.6 mA) failed (Loerwald 2018)
- LC-NE activation occurs within seconds: pupil dilation peaks at 4.25s post-onset, alpha attenuation within 0-4s (Sharon 2021)
- 30s on/30s off: standard duty cycle in cognitive research; each epoch demonstrably activates LC-NE system
- Rapid cycling (7s on / 18s off) showed stronger effects at lower intensity in animal model (PMC 2016) — not yet validated in humans
- Offline (pre-task) stimulation significantly increased spatial 3-back hits; online stimulation showed no effect (Sun 2021)
- Salivary alpha-amylase (NE proxy) significantly increased by 30s epochs but not 3.4s epochs (Bomber 2024)
- Left ear not proven *superior* but is the most researched; fMRI shows laterality-specific connectivity changes (PMC 2025)
- No evidence for alternating L/R for cognition — completely untested

**Evidence grade: Moderate-Strong**

---

### 4. Pain Relief — 8 min

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Channel | Bilateral (`D`) | Max afferent coverage |
| Intensity | High-comfortable (user-set +1, capped at 9), slow oscillation ±1 on 30s wave | "Strong but comfortable" consistently superior in TENS and tVNS |
| Duty cycle | Continuous | Short session — every off-second is wasted |
| Default | Higher than other modes (suggest 6-7) | TENS: higher comfortable intensity = better hypoalgesia |

**Evidence notes:**
- **Major caveat:** No published evidence that 5-10 min of auricular tVNS produces acute pain relief
- Closest precedent: gammaCore's 4-min cervical protocol (FDA-cleared for migraine) — but targets different anatomical site (cervical vs auricular)
- Auricular pain studies use 30-60+ min: Busch 2013 (1 hr), Straube 2015 (4 hrs/day), CPM study 2024 (effects only significant at 30 min, not 15)
- Straube 2015: 1 Hz was significantly better than 25 Hz for chronic migraine — we cannot control device frequency, but could approximate via duty cycling (theoretical, based on TENS burst mode literature)
- Intensity oscillation: Pantaleao 2011 found adjusted amplitude TENS produced greater hypoalgesia; Bergeron-Vezina 2018 failed to replicate in chronic pain patients
- Frequency modulation reduces perceived habituation but not actual pain relief (Hingne 2019)
- TENS literature is consistent: "strong but comfortable" > threshold or sub-threshold intensity

**Evidence grade: Weak** (short duration is the fundamental problem)

---

### 5. Calm / Breathe — 5 min

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Channel | Bilateral (`D`) | Continuous, non-distracting |
| Breathing pace | 6 breaths/min (10s cycle: 4s inhale, 6s exhale) | Resonance frequency breathing — very robust standalone evidence for HRV |
| Stimulation gating | Exhale-gated: off during inhale, on during exhale | **RAVANS protocol (Napadow lab, Harvard/MGH)** |
| Intensity during exhale | Constant at user-set level (binary on/off) | RAVANS validates binary gating, not ramped |
| UI | Breathing animation: expand on inhale (stim off), contract on exhale (stim on) | Device as breathing pacer (Szulczewski 2022, Neuromodulation) |

**Evidence notes:**
- **Exhalation-gated stimulation is established science:**
  - NTS receives inhibitory input during inhalation, facilitatory during exhalation
  - 7T fMRI: eRAVANS evoked significantly greater brainstem response than iRAVANS across ALL nuclei — NTS, dorsal raphe, median raphe, locus coeruleus (Garcia 2017)
  - Depression: eRAVANS produced 2.3x greater BDI-II reduction than iRAVANS (Sclocco 2021)
  - HR: expiratory-gated reduced HR by -1.30% vs +0.11% for inspiratory-gated (Juel 2019)
- **Combined tVNS + slow breathing — mixed evidence:**
  - Positive: insomnia pilot (2023) — combined > tVNS alone for ISI scores
  - Positive: multimodal study (2025 preprint) — combined SDNN 157.6 ms vs tVNS-alone 109.5 ms
  - Negative: Szulczewski 2023 — expiratory-gated taVNS did NOT augment HRV beyond slow breathing alone at 0.1 Hz (possible ceiling effect)
- The breathing guidance itself is the primary active ingredient
- Position as "guided resonance breathing with vagal stimulation" not "proven synergy"
- RAVANS uses binary on/off (1s bursts during exhale), not gradual ramp — staying with validated protocol

**Evidence grade: Strong** (exhalation gating is proven; combination synergy is mixed but clinically positive)

---

### 6. Atrial Fibrillation (AF) — 60 min

**NOTE: This mode requires a different device.** The Pulsetto stimulates the cervical vagus via the neck. All AF evidence is for **auricular (ear) stimulation at the tragus**. This section documents the protocol for use with a programmable TENS + tragus ear clip electrode, with PulseLibre serving as a session timer and adherence tracker.

| Parameter | Value | Evidence |
|-----------|-------|----------|
| Site | Tragus of ear (auricular branch of vagus nerve) | TREAT AF, Yu 2015, Stavrakis 2021 — all used tragus |
| Frequency | 20 Hz | TREAT AF protocol; 20 vs 25 Hz never directly compared, likely equivalent |
| Pulse width | 200 us | TREAT AF protocol; 200-500 us all produce effects (crossover trial 2025) |
| Amplitude | Individually titrated: increase until discomfort, then reduce by 1 mA (~4-29 mA range, mean ~17 mA) | TREAT AF: "1 mA below discomfort threshold" |
| Waveform | Biphasic, constant current | Standard across all tVNS research |
| Duration | 60 min daily | TREAT AF: 1 hr/day for 6 months |
| Duty cycle | Continuous | TREAT AF used continuous stimulation |

**What "AF burden" means:**

AF burden = percentage of time the heart is in atrial fibrillation, measured continuously via implanted cardiac monitor (e.g., Medtronic LINQ). In TREAT AF, this was measured over 6 months.

**Key clinical results:**

| Outcome | Active (tragus) | Sham (earlobe) | Effect | p-value |
|---------|----------------|-----------------|--------|---------|
| AF burden at 6 months | ~0.5% (~7 min/day in AF) | ~3.0% (~43 min/day in AF) | **85% lower** (ratio 0.15) | 0.011 |
| Total AF duration | — | — | **83% lower** | 0.032 |
| Responders (>75% reduction) | 47% | 5% | — | 0.003 |
| TNF-alpha (inflammation) | — | — | **23% decrease** | 0.009 |
| Other cytokines (IL-6, IL-1b, IL-10, IL-17) | — | — | No significant difference | NS |

**What parameters matter most (evidence-ranked):**

1. **Stimulation site** (most critical) — Tragus/ear vs neck/earlobe is the difference between active treatment and sham. Cymba conchae may be even better (exclusively vagal innervation, stronger brainstem activation on fMRI) but tragus is what was validated in AF trials.
2. **Amplitude titration method** — "1 mA below discomfort" is the validated approach. Actual mA varies enormously across individuals (4-29 mA in TREAT AF). Fine mA control enables proper titration; Pulsetto's blind 1-9 levels cannot do this.
3. **Session duration** — 60 min/day is the only validated duration for AF. Shorter sessions have not been tested.
4. **Adherence** — TREAT AF active arm had 75% adherence. The app's primary role is tracking and encouraging adherence.
5. **Frequency** (marginal) — 20 Hz used in all AF trials. Crossover trial (2025) found non-linear inverted-U relationship between frequency and HRV; 10 Hz and 25 Hz both produced significant effects. 20 vs 25 Hz difference is likely negligible.
6. **Pulse width** (marginal) — 200 us in TREAT AF. 500 us is considered "most biologically active" but requires lower current. 200-500 us range all produce effects. No head-to-head comparison in AF patients.

**Why the Pulsetto cannot be used for AF:**

The Pulsetto stimulates the cervical vagus nerve through the neck. All AF evidence targets the auricular branch of the vagus nerve at the tragus of the ear. These are anatomically distinct pathways with different cardiac effects. No app modification can change the stimulation site — this is a hardware constraint.

**MVP hardware for AF protocol:**

| Component | Example | Approx cost |
|-----------|---------|-------------|
| Programmable TENS (20 Hz, 200 us) | TragusClip Kit 1 (EV806P TENS + ear clip) | ~$40-50 |
| Tragus ear clip electrode (if separate) | TENSPros snap-connector ear clip | ~$15 |
| PulseLibre app | Session timer + adherence tracker | $0 |

**Advanced hardware (full BLE control):**

| Component | Example | Approx cost |
|-----------|---------|-------------|
| Open-source constant-current stimulator | NeuroStimDuino v3.0 (3-100 Hz, 0-2000 us, 0-22 mA) | $260 |
| BLE bridge | ESP32-S3 dev board | ~$10 |
| Tragus ear clip electrode | TENSPros or medical-grade silver clip | ~$15 |
| Batteries | 2x 18650 Li-ion | ~$15 |
| **Total** | | **~$310** |

**Upcoming trial to watch:**

VAST-AF (120 patients, persistent AF post-cardioversion, 1 hr/day for 3 months) — first RCT for persistent (not just paroxysmal) AF.

**Evidence grade: Strong** (for paroxysmal AF with proper hardware; N/A for Pulsetto neck stimulation)

---

### 7. Custom — 4-10 min

Full manual control: user sets timer, intensity, no programmatic pattern. Current freeform behavior.

---

## Polyvagal Framework — Mode Mapping

The autonomic ladder (Porges, Polyvagal Theory) describes three nervous system states.
OpenPulse modes target specific state transitions:

| Current State | Experience | Goal | Suggested Mode |
|---|---|---|---|
| Sympathetic (fight/flight) | Wired, tense, anxious, restless | Downregulate to ventral-vagal | **Stress Relief** or **Calm/Breathe** |
| Dorsal vagal (freeze) | Foggy, stuck, numb, shut down | Gently mobilize toward ventral-vagal | **Focus** (LC-NE activation) |
| Ventral-vagal (regulated) | Calm, present, balanced | Maintain or transition to rest | **Sleep** or **Calm/Breathe** |
| Any state + pain | — | Pain modulation | **Pain Relief** |

Key insight: you cannot skip ladder rungs. Someone in dorsal vagal freeze needs gentle
activation (Focus) before calming modes become useful — calming an already-shutdown
system is counterproductive.

---

## Evidence Grading Summary

| Mode | Channel | Intensity | Duty Cycle | Overall |
|------|---------|-----------|------------|---------|
| Stress Relief | Evidence-informed | Evidence-based | Evidence-based | **Strong** |
| Sleep | Experimental (rotation) | Plausible (fade) | Evidence-based | **Moderate** |
| Focus | Convention-based (left) | Evidence-informed (inverted-U) | Evidence-based (30s/30s) | **Moderate-Strong** |
| Pain Relief | Reasonable | Experimental (oscillation) | Evidence-based | **Weak** |
| Calm/Breathe | Standard | **Evidence-based (RAVANS)** | **Evidence-based (respiratory gating)** | **Strong** |
| Custom | User choice | User choice | User choice | N/A |

---

## Key Research Sources

### Stress / Anxiety
- Miyaguchi et al. (2024) — Continuous vs intermittent taVNS: [PMC11099104](https://pmc.ncbi.nlm.nih.gov/articles/PMC11099104/)
- Badran et al. (2019) — Short trains of taVNS and heart rate: [PMC6536129](https://pmc.ncbi.nlm.nih.gov/articles/PMC6536129/)
- Cuberos Paredes et al. (2025) — taVNS cortisol suppression: [PMC11815478](https://pmc.ncbi.nlm.nih.gov/articles/PMC11815478/)
- Chen et al. (2022) — taVNS HRV effects: [PeerJ 14447](https://peerj.com/articles/14447/)
- Redgrave et al. (2018) — Safety meta-analysis: [Nature Scientific Reports](https://www.nature.com/articles/s41598-022-25864-1)

### Sleep
- Zhang et al. (2024) — JAMA Network Open RCT, chronic insomnia: [JAMA](https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2828072)
- Bottari et al. (2024) — tVNS sleep parameter optimization, PTSD veterans: [J Sleep Research](https://onlinelibrary.wiley.com/doi/10.1111/jsr.13891)
- Bottari/Williamson et al. (2025) — tVNS during 1st vs 2nd half of night: [SLEEP abstract](https://academic.oup.com/sleep/article/48/Supplement_1/A181/8135826)
- Li et al. (2022) — tVNS for primary insomnia: [PMC9599790](https://pmc.ncbi.nlm.nih.gov/articles/PMC9599790/)

### Focus / Cognition
- Sun et al. (2021) — taVNS spatial working memory, offline vs online: [Frontiers in Neuroscience](https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2021.790793/full)
- Loerwald et al. (2018) — VNS intensity inverted-U curve, motor cortex plasticity: [PMC6347516](https://pmc.ncbi.nlm.nih.gov/articles/PMC6347516/)
- Sharon et al. (2021) — tVNS pupil dilation and alpha attenuation: [PMC7810665](https://pmc.ncbi.nlm.nih.gov/articles/PMC7810665/)
- Alertness study (2023) — Cortical arousal, intensity readjustment: [PMC9859411](https://pmc.ncbi.nlm.nih.gov/articles/PMC9859411/)
- Bomber et al. (2024) — Stimulation duration comparison: [PMC11430400](https://pmc.ncbi.nlm.nih.gov/articles/PMC11430400/)

### Pain
- Busch et al. (2013) — tVNS pain thresholds: [PubMed 22621941](https://pubmed.ncbi.nlm.nih.gov/22621941/)
- Straube et al. (2015) — 1 Hz vs 25 Hz for chronic migraine: [PubMed 26156114](https://pubmed.ncbi.nlm.nih.gov/26156114/)
- Zhang et al. (2021) — 1 Hz vs 20 Hz fMRI, PAG connectivity: [PMC8371886](https://pmc.ncbi.nlm.nih.gov/articles/PMC8371886/)
- Pantaleao et al. (2011) — TENS amplitude adjustment hypoalgesia: [PubMed 21277840](https://pubmed.ncbi.nlm.nih.gov/21277840/)
- CPM enhancement study (2024) — taVNS trigeminal neuralgia: [PMC11543976](https://pmc.ncbi.nlm.nih.gov/articles/PMC11543976/)
- gammaCore migraine (Barbanti 2015): [PMC4485661](https://pmc.ncbi.nlm.nih.gov/articles/PMC4485661/)

### Calm / Breathe (RAVANS)
- Garcia et al. (2017) — 7T fMRI, eRAVANS vs iRAVANS brainstem: [PMC6592731](https://pmc.ncbi.nlm.nih.gov/articles/PMC6592731/)
- Sclocco et al. (2021) — RAVANS in major depression: [PMC8429271](https://pmc.ncbi.nlm.nih.gov/articles/PMC8429271/)
- Sclocco et al. (2019) — RAVANS in migraine, NTS activation: [PMC5517046](https://pmc.ncbi.nlm.nih.gov/articles/PMC5517046/)
- Juel et al. (2019) — Inspiratory vs expiratory gated HR effects: [PMC8041682](https://pmc.ncbi.nlm.nih.gov/articles/PMC8041682/)
- Szulczewski (2022) — taVNS + slow breathing theoretical framework: [PubMed 35396070](https://pubmed.ncbi.nlm.nih.gov/35396070/)
- Szulczewski (2023) — Expiratory-gated taVNS does not augment HRV during slow breathing: [Springer](https://link.springer.com/article/10.1007/s10484-023-09584-4)
- taVNS + 0.1 Hz breathing insomnia pilot (2023): [PubMed 38042286](https://pubmed.ncbi.nlm.nih.gov/38042286/)

### Atrial Fibrillation
- **Stavrakis et al. (2020) — TREAT AF RCT** (the key paper): [PMC7100921](https://pmc.ncbi.nlm.nih.gov/articles/PMC7100921/)
- Yu et al. (2015) — First human proof-of-concept, AF suppression during ablation: [JACC](https://www.jacc.org/doi/abs/10.1016/j.jacc.2014.12.026)
- Stavrakis et al. (2021) — Tragus stimulation modulates atrial alternans and AF burden: [JAHA](https://www.ahajournals.org/doi/10.1161/JAHA.120.020865)
- Low-level aVNS lowers BP/HR in paroxysmal AF (2025): [Frontiers in Neuroscience](https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2025.1525027/full)
- Frequency/pulse width crossover trial, HRV in healthy adults (2025): [PMC11940630](https://pmc.ncbi.nlm.nih.gov/articles/PMC11940630/)
- VNS and AF paradox review: [Neuromodulation](https://www.neuromodulationjournal.org/article/S1094-7159(22)00029-0/fulltext)
- VAST-AF trial design (persistent AF, 120 patients): [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0002870323003253)
- Tragus vs cymba conchae anatomy: [PMC6607436](https://pmc.ncbi.nlm.nih.gov/articles/PMC6607436/)
- Intensity not affecting cardiac vagal activity (sham comparison): [PMC6788680](https://pmc.ncbi.nlm.nih.gov/articles/PMC6788680/)

### General tVNS Parameters
- Parameter settings review (Frontiers 2021): [Frontiers in Neuroscience](https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2021.709436/full)
- Critical review of tVNS challenges (PMC 2020): [PMC7199464](https://pmc.ncbi.nlm.nih.gov/articles/PMC7199464/)
- Minimum reporting standards consensus (2020): [Frontiers in Human Neuroscience](https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2020.568051/full)

### BLE Protocol
- [jooray/PulseLibre](https://github.com/jooray/PulseLibre) — React Native mobile app
- [jooray/pulse-libre-desktop](https://github.com/jooray/pulse-libre-desktop) — Python desktop app
- [hydrasparx/pulsetto](https://github.com/hydrasparx/pulsetto) — Web Bluetooth (discovered A/C/D channel commands)
- [parallaxintelligencepartnership/pulse-libre](https://github.com/parallaxintelligencepartnership/pulse-libre) — Flutter app
- [FCC Filing 2A5T3-BXN-PU-22V001](https://fcc.report/FCC-ID/2A5T3-BXN-PU-22V001)
