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
Ten images were rendered from the repository. Alfa Romeo 4C: recognizable but soft edges, visible badge; Dodge Dart and Neon: soft details, should be refreshed; Maserati MC20: detailed, minor edge cleanup; Nissan Fairlady Z 432: red/orange edge halo; Nismo GT-R LM: obvious white/blue edge debris, priority cleanup; Skyline GT-R V-Spec: blue edge debris, verify generation against catalog. Three generic traffic sprites were also reviewed: slot 7 (white cargo van) has minor outline debris; slot 9 (blue pickup) has conspicuous blue edge artifacts; slot 10 (white box truck) has white, red and yellow fringe debris. Their exact make/model is not established, so their filenames remain unchanged rather than guessed. File byte size alone does not establish image quality. Larger images were unavailable; all other images are NOT visually approved. No original pixels changed.

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

## Roster reconciliation (follow-up)

Removed all 24 missing-artwork catalog entries per project direction. Preserved all 124 artwork-backed entries and IDs. Added 132 existing named assets to playable catalog (256 playable total); registered one unidentified Lotus and ten traffic sprites separately. No vehicle PNG deleted. Specs and prices of the 132 are representative estimates, not verified against external sources. RSQ5 and Plaid are explicitly unverified named variants. The unidentified Lotus is not purchasable under an invented name. Existing ownership loading drops retired IDs, selects an owned surviving vehicle (or starter), and keeps money and unrelated progress; no compensation policy added. Automated coverage checks require every PNG to have exactly one role.

Retired IDs:
- acura-tl (Acura TL)
- acura-tsx (Acura TSX)
- acura-ilx (Acura ILX)
- audi-a3 (Audi A3)
- audi-a4 (Audi A4)
- audi-a5 (Audi A5)
- audi-a6 (Audi A6)
- audi-a7 (Audi A7)
- audi-a8 (Audi A8)
- audi-q3 (Audi Q3)
- audi-q5 (Audi Q5)
- audi-q7 (Audi Q7)
- bentley-flying-spur (Bentley Flying Spur)
- bentley-bentayga (Bentley Bentayga)
- bugatti-eb110 (Bugatti EB110)
- cadillac-ct4 (Cadillac CT4)
- cadillac-ct5 (Cadillac CT5)
- dodge-avenger (Dodge Avenger)
- dodge-magnum (Dodge Magnum)
- ferrari-308 (Ferrari 308)
- ferrari-458-italia (Ferrari 458 Italia)
- ferrari-f8-tributo (Ferrari F8 Tributo)
- ferrari-roma (Ferrari Roma)
- ferrari-296-gtb (Ferrari 296 GTB)
