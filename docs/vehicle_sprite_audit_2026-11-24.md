# Vehicle sprite inventory and partial visual audit

Baseline: c59b76d4846194ac2efa1a1423dfb4ab1f120844 (main). Inventory: 267 PNGs under assets/Vehicles; 148 playable catalog entries; 24 referenced PNGs absent; 143 PNGs not directly referenced by either playable catalog (includes traffic and future content). Missing images use the existing provisional silhouette.

## Missing artwork (24)
- Acura TL, TSX, ILX
- Audi A3, A4, A5, A6, A7, A8, Q3, Q5, Q7
- Bentley Flying Spur, Bentayga
- Bugatti EB110
- Cadillac CT4, CT5
- Dodge Avenger, Magnum
- Ferrari 308, 458 Italia, F8 Tributo, Roma, 296 GTB

## Visual inspection (partial)
Seven images were rendered from the repository. Alfa Romeo 4C: recognizable but soft edges, visible badge; Dodge Dart and Neon: soft details, should be refreshed; Maserati MC20: detailed, minor edge cleanup; Nissan Fairlady Z 432: red/orange edge halo; Nismo GT-R LM: obvious white/blue edge debris, priority cleanup; Skyline GT-R V-Spec: blue edge debris, verify generation against catalog. File byte size alone does not establish image quality. Larger images were unavailable; all other images are NOT visually approved. No original pixels changed.

## Filename corrections
- `assets/Vehicles/Acura/Integra TypeS.png` → `assets/Vehicles/Acura/Integra Type S.png`
- `assets/Vehicles/Alfa Romeo/Alfa Romeo 33 Stradale Overhead.png` → `assets/Vehicles/Alfa Romeo/33 Stradale.png`
- `assets/Vehicles/Aston Martin/Valyrie AMR Pro.png` → `assets/Vehicles/Aston Martin/Valkyrie AMR Pro.png`
- `assets/Vehicles/Audi/RS6 Avante.png` → `assets/Vehicles/Audi/RS6 Avant.png`
- `assets/Vehicles/Ferrari/Ferrari F80.png` → `assets/Vehicles/Ferrari/F80.png`
- `assets/Vehicles/Ford/F150.png` → `assets/Vehicles/Ford/F-150.png`
- `assets/Vehicles/Mercedes-Benz/Evolution II.png` → `assets/Vehicles/Mercedes-Benz/190E 2.5-16 Evolution II.png`
- `assets/Vehicles/Nissan/Skyline GTR V-Spec.png` → `assets/Vehicles/Nissan/Skyline GT-R V-Spec.png`
- `assets/Vehicles/Pontiac/Pontiac Firebird Trans.png` → `assets/Vehicles/Pontiac/Firebird Trans Am.png`

Preserve catalog IDs, PNG blob SHAs, Godot import UIDs and import parameters. Update both catalogs and checked references and corresponding import cache paths. Generic Lotus and ten traffic filenames require visual identification before a model-based rename. RSQ5, Plaid, and the Chevrolet folder typo are deferred pending a separate verification/reference pass. Other existing model names may benefit from punctuation normalization.

Remaining work: complete a visual contact-sheet review of every sprite (true overhead, front facing down, correct model and trim, clean transparency, no wheels or lettering, consistent rendering), identify the 11 generic filenames, repair or restore 24 missing PNGs, run Godot import and vehicle tests. This report is not a full visual certification.
