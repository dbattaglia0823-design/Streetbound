# Streetbound — Audio-ready future vehicle roster

Source of truth: `streetbound_vehicle_list.txt`. The original list has **223 requested model rows**. `data/player_vehicle_catalog.json` already represents **66 exact** entries, plus **three differently spelled aliases** (Camaro Z/28, Corvette ZO6 → Z06, F-150). This update prepares the **remaining 154 model/trim entries**, but intentionally leaves the current **88 playable vehicles unchanged**.

## Status

`data/pending_vehicle_audio_profiles.json` is the preproduction audio catalog. Each entry includes manufacturer/model name and stable ID, engine/family, induction type, modeled reference boost for *auditioning*, reference RPM range, exhaust resonance/roughness, throttle/intake/driveline presence, flutter eligibility, idle character, overrun tendency, hybrid electric assist, and a warning when year, version or engine is ambiguous.

This is an **audio design pass**. Engine sounds are generated from the existing eight-band power/coast synthesizer plus the CC0 recorded acoustic-family layer where an appropriate shared recording already exists. **No new OEM-exact car recordings were obtained.** New family sounds without cleared matching recordings use original synthesis; assigning a generic existing sample to a new rotary/EV/V16 would be misleading.

### Additional sound families

| Family | Examples from future lineup | Audio design |
|---|---|---|
| I5 turbo | Audi RS3 | Distinct five-cylinder uneven exhaust pulses and turbo spool |
| Boxer 4 | Subaru WRX, BRZ, Toyota GR86, Porsche 718 | Boxer pulse character; turbo only on applicable profiles |
| Boxer 6 | Porsche 911 | Flat-six note instead of generic V6 |
| Twin rotor | Mazda RX-7, RX-8 | Smooth high-rev rotary harmonic buzz; turbo RX-7 versus naturally aspirated RX-8 |
| V16 hybrid | Bugatti Tourbillon | Naturally aspirated V16 at high revs with electric low-speed assist; **not** a W16 turbo profile |
| Electric | Tesla models, Hyundai Ioniq 5/6, GMC Hummer EV, Porsche Taycan, Cadillac Celestiq, Rolls-Royce Spectre | Motor/inverter and reduction gear whine; quiet at a standstill; no fake intake, ignition, combustion, exhaust popping or turbo release |

Other prepared performance trims include Dodge Charger/Challenger Hellcat Redeye (**supercharger**), Cadillac CT5-V Blackwing (**supercharger**), Lamborghini Temerario (**twin-turbo V8 hybrid**), Huracán (**naturally aspirated V10**), Ferrari FXX K Evo (**V12 hybrid**), McLaren P1 (**turbo V8 hybrid**), and Nissan GT-R (**turbo V6**). The list also includes luxury sedans, trucks, compacts and classic sports cars.

## Preview a future vehicle's audio in Godot

1. Open `scenes/pending_audio_preview.tscn` in the Godot 4.4.1 editor.
2. Use **Run Current Scene (F6)**.
3. Search/select any of the 154 future cars.
4. Change **RPM, throttle, boost and road speed**, or use the Idle, Cruise, Full Pull, Lift Off and Shift controls.
5. Compare the new layouts and power/coast transitions with your ears. Mute works in the preview.

The preview uses a hidden reusable vehicle controller to drive the real audio mixer, not placeholder car art, an economy purchase, or a simulated audio output file. It is intentionally separate from the playable game.

`PendingVehicleAudio.make_preview_configuration(id)` creates a temporary copy of the base VehicleConfig with audition RPM and boost parameters. `PendingVehicleAudio.apply_to_config(config,id)` applies **only audio parameters** without changing any real car's power, mass, tire grip or drivetrain.

When a new model is introduced into the real `data/player_vehicle_catalog.json` without a custom `audio_family`, `PlayerVehicleCatalog.make_configuration` automatically applies its matching prepared audio settings. The new vehicle's real `boost_max_psi`, RPM and drivetrain must still be authored as real gameplay specifications when it is made purchasable.

## Source-to-profile quality checks

`tests/pending_vehicle_audio_test.gd` reads the actual text roster, checks all 223 rows are represented by an existing car, known alias, or pending profile, verifies no missing audio ID was injected into the playable catalog, and tests the new engine synthesis signatures and EV/hybrid/petrol behavior.

**Trim ambiguity:** Several text-list names omit model year or performance version. The audio catalog uses representative versions only: e.g., Audi RS Q5 is not verified as a production RS designation; Porsche 911 assumes a turbo Carrera rather than a naturally aspirated GT3; Subaru STI represents a turbo boxer. The next step when vehicles are implemented is to assign a specific model year/trim, confirm its engine and recording reference, and replace generic samples with redistributed licensed RPM load/coast clips when available.

## Source research

- [Bugatti Tourbillon V16 acoustic design and hybrid powertrain](https://newsroom.bugatti.com/en/press-releases/sound-of-a-new-era-the-bugatti-tourbillons-v16) — official, 2026
- [Audi RS3 engine technical data: turbo inline-five](https://media.audi.com/is/content/audi/country/sg/assets/english/models/a3/rs3sb/Audi_RS_3_Sedan_Sportback_Spec_Sheet_May_25.pdf)
- [Mazda RX-8 RENESIS twin rotor](https://newsroom.mazda.com/en/publicity/release/2003/200301/0129e.html)
- [Mazda RX-7 historical turbo twin-rotor](https://www.mazda.com/en/about/history/1990-1999/)
- [Subaru boxer engine explanation](https://www.subaru.com/vehicle-info/articles/what-is-boxer-engine)
- [Lamborghini Temerario twin-turbo V8 hybrid](https://www.lamborghini.com/models/temerario)

The web references establish relevant **engine family and induction** choices for highlighted models. The numerical mixing values in the catalog are **art-directed game sound defaults**, not factory-verified recording measurements.

## Future passes

As each new car model is added: check model/trim and engine type, inspect its exact powertrain and audio clips, and import correctly licensed idle/low/mid/high load and coast samples under `assets/audio/engines/<car-id>/`. Full synthetic engine stems and shared CC0 family recordings remain useful fallbacks. Neither a waveform's family classification nor its model name proves that a genuine manufacturer sound was captured.
