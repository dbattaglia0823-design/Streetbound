# Streetbound: November 2026 vehicle-asset integration

**Catalog scope:** 50 named playable car sprites added in commit `bc1c64e2`, in addition to the 98 previously playable cars, for **148 total playable cars**. This change does not automatically publish the other older, unregistered assets from the vehicle art folder.

The source of truth for the new entries is `data/player_vehicle_additions.json`. `PlayerVehicleCatalog.all()` reads both the original 98-car file and this extension, preserving legacy IDs and save-game ownership. All consumers of the shared catalog—including the garage, dealerships, upgrades, active driving controller, vehicle audio, race systems, and persistence—see the expanded roster without introducing a competing car list.

## Price realism and evidence rules

Prices are expressed as **USD**. The game uses the catalog `price_usd` as an in-game purchase amount; that value is **not** a guaranteed, live dealer quote, auction appraisal, or VIN-specific estimate.

- `msrp_usd`: published model-year U.S. starting MSRP (**2** new vehicles).
- `msrp_estimate_usd`: approximate list/launch price when the selected model-year U.S. sticker could not be verified (**8**).
- `used_estimate_usd`: indicative U.S. secondhand asking/resale benchmark, sensitive to mileage and condition (**7**).
- `collector_estimate_usd`: indicative collector or auction-level value; may vary dramatically with provenance (**25**).
- `converted_launch_estimate_usd`: USD-equivalent foreign list price around launch, **not** a current used-car valuation (**4**).
- `fictional_game_value_usd`: explicitly fictional acquisition value for concepts or unique prototypes without a reliable public-sale market (**4**). This is marked **GAME VALUE (NO MARKET SALE)** in the dealership, not misrepresented as a real-world quote.

Four new cars use game-only values: **Hyundai N Vision 74**, **Koenigsegg CCGT**, **McLaren F1 GT**, and **Nissan NISMO GT-R LM Road Car**. Buying or selling an original example of these is not a normal retail transaction; the simulated price exists only to make every sprite playable and collectible.

**Spec confidence:** 23 records contain a selected linked manufacturer/automotive reference; 27 are representative model-year/trim estimates pending more detailed individual verification. Each car has source and price-basis metadata. Those counts do not mean that all prices are verified live sales. Dimensions, curb-versus-dry mass, real-world peak power, and combined hybrid system power should not be assumed directly comparable across unrelated manufacturers.

## Reference vehicles and modeled game prices

Power is rounded from the catalog's kW representation; mass in kg. The underlying JSON also includes torque, length, width, wheelbase, gear count, drivetrain, audio, handling calibration, dealer tier and progression level.

| Vehicle | Reference year | HP | Mass kg | Drive | In-game USD | Price basis |
| --- | ---: | ---: | ---: | :---: | ---: | --- |
| Acura Integra Type R | 2001 | 195 | 1,197 | FWD | $46,000 | Est. collector |
| Ariel Atom 500 | 2010 | 500 | 550 | RWD | $180,000 | Est. collector |
| Ariel Nomad | 2016 | 235 | 670 | RWD | $50,000 | Est. used |
| Aston Martin DB5 | 1965 | 282 | 1,468 | RWD | $1,500,000 | Est. collector |
| Aston Martin Valkyrie AMR Pro | 2022 | 1000 | 1,000 | RWD | $4,000,000 | Est. collector |
| Aston Martin Vulcan | 2016 | 820 | 1,350 | RWD | $2,650,000 | Est. collector |
| Audi R8 V10 Plus | 2017 | 602 | 1,555 | AWD | $165,000 | Est. used |
| Audi R8 LMS GT3 | 2022 | 577 | 1,235 | RWD | $505,000 | Est. foreign launch |
| Audi Sport quattro S1 E2 | 1985 | 476 | 1,090 | AWD | $1,500,000 | Est. collector |
| BAC Mono | 2020 | 332 | 570 | RWD | $215,000 | Est. foreign launch |
| Hennessey Venom F5 | 2022 | 1817 | 1,360 | RWD | $3,000,000 | Est. MSRP |
| Hennessey Venom GT | 2014 | 1244 | 1,244 | RWD | $1,550,000 | Est. collector |
| Honda Civic Type R | 2025 | 315 | 1,446 | FWD | $45,895 | MSRP |
| Hyundai N Vision 74 | 2022 | 670 | 2,472 | RWD | $250,000 | Game only |
| Koenigsegg Agera RS | 2017 | 1160 | 1,395 | RWD | $4,200,000 | Est. collector |
| Koenigsegg CCGT | 2007 | 600 | 1,100 | RWD | $2,200,000 | Game only |
| Koenigsegg Gemera | 2025 | 2300 | 2,022 | AWD | $1,900,000 | Est. MSRP |
| Koenigsegg Jesko Attack | 2023 | 1600 | 1,320 | RWD | $3,500,000 | Est. MSRP |
| Koenigsegg Regera | 2018 | 1500 | 1,590 | RWD | $2,900,000 | Est. collector |
| Lamborghini Essenza SCV12 | 2021 | 819 | 1,378 | RWD | $3,500,000 | Est. MSRP |
| Lamborghini Sesto Elemento | 2012 | 562 | 999 | AWD | $3,000,000 | Est. collector |
| Lotus Evija | 2025 | 2012 | 1,894 | AWD | $2,600,000 | Est. foreign launch |
| Maserati MC20 | 2023 | 621 | 1,500 | RWD | $245,000 | Est. used |
| McLaren 12C | 2012 | 592 | 1,434 | RWD | $90,000 | Est. used |
| McLaren 570S | 2018 | 562 | 1,422 | RWD | $143,000 | Est. used |
| McLaren 650S | 2015 | 641 | 1,468 | RWD | $137,000 | Est. used |
| McLaren 720S | 2020 | 710 | 1,419 | RWD | $201,000 | Est. used |
| McLaren 750S | 2025 | 740 | 1,389 | RWD | $349,000 | MSRP |
| McLaren F1 GT | 1997 | 618 | 1,120 | RWD | $40,000,000 | Game only |
| McLaren F1 | 1995 | 627 | 1,140 | RWD | $22,000,000 | Est. collector |
| McLaren P1 | 2015 | 903 | 1,490 | RWD | $2,350,000 | Est. collector |
| McLaren Senna | 2019 | 789 | 1,374 | RWD | $2,500,000 | Est. collector |
| McLaren W1 | 2026 | 1258 | 1,399 | RWD | $2,100,000 | Est. MSRP |
| Mercedes-Benz 190E 2.5-16 Evolution II | 1990 | 232 | 1,340 | RWD | $300,000 | Est. collector |
| Nissan Fairlady Z 432 | 1970 | 158 | 1,040 | RWD | $200,000 | Est. collector |
| Nissan NISMO GT-R LM Road Car | 1995 | 305 | 1,580 | RWD | $2,500,000 | Game only |
| Nissan Skyline GT-R V-Spec | 1999 | 276 | 1,560 | AWD | $185,000 | Est. collector |
| Noble M600 | 2012 | 650 | 1,198 | RWD | $260,000 | Est. collector |
| Pagani Huayra BC Coupe | 2017 | 750 | 1,218 | RWD | $4,000,000 | Est. collector |
| Pagani Zonda Cinque Roadster | 2010 | 678 | 1,210 | RWD | $12,000,000 | Est. collector |
| Pagani Zonda R | 2009 | 750 | 1,070 | RWD | $5,500,000 | Est. collector |
| Plymouth Barracuda Formula S | 1968 | 330 | 1,540 | RWD | $41,000 | Est. collector |
| Plymouth Cuda 426 Hemi | 1970 | 425 | 1,710 | RWD | $252,000 | Est. collector |
| Pontiac Firebird Trans Am GTA | 1988 | 225 | 1,588 | RWD | $19,000 | Est. collector |
| Pontiac Firebird Trans Am | 1979 | 220 | 1,714 | RWD | $43,000 | Est. collector |
| Porsche 911 GT2 RS | 2018 | 700 | 1,470 | RWD | $540,000 | Est. collector |
| Porsche 911 GT3 RS | 2024 | 518 | 1,450 | RWD | $255,000 | Est. MSRP |
| Porsche 911 GT3 | 2024 | 502 | 1,435 | RWD | $183,000 | Est. MSRP |
| Porsche 935 (2019) | 2019 | 700 | 1,380 | RWD | $900,000 | Est. foreign launch |
| Zenvo TSR-S | 2019 | 1177 | 1,495 | RWD | $1,800,000 | Est. MSRP |

## Key cross-checks

- [Honda 2025 Civic Type R manufacturer pricing](https://hondanews.com/en-US/releases/release-d73d9911716c8277bb60a2789701ad49-2025-honda-civic-type-r-pricing-and-epa-ratings-2025)
- [BAC Mono technical launch release](https://www.bac-mono.com/news/bac-launches-turbocharged-new-generation-mono-more-power-tech-lighter-weight-and-road-legal-across-europe)
- [Koenigsegg Gemera HV8 and Dark Matter factory specification](https://www.koenigsegg.com/index.php/technical-specifications-gemera-2023)
- [McLaren 750S published MSRP (KBB)](https://www.kbb.com/mclaren/750s/2025/specs/)
- [2018 McLaren 570S current asking-price comparisons](https://www.luxurycardeals.com/prices/mclaren/570s)
- [2020 McLaren 720S approximate resale benchmark](https://www.kbb.com/mclaren/720s/2020/base-style/)
- [Porsche GT2 RS collector market benchmark](https://www.classic.com/m/porsche/911/991/9912/gt2-rs/)
- [Hyundai N Vision 74 concept information](https://www.hyundai.com/worldwide/en/newsroom/detail/0000000089)
- [Nissan GT-R LM unique road prototype](https://www.nissan-global.com/EN/HERITAGE_COLLECTION/181_nismo_gt-r_lm_road_car.html)
- [Aston Martin Valkyrie AMR Pro factory reference](https://www.astonmartin.com/en/models/valkyrie-amr-pro)
- [Lotus production Evija kerb weight and specification](https://www.lotuscars.com/en/press/models/evija)
- [1997 McLaren F1 GT model-specific specifications](https://www.automobile-catalog.com/make/mclaren/f1/f1_gt/1997.html)
- [Koenigsegg Regera factory direct-drive reduction](https://www.koenigsegg.com/koenigsegg-direct-drive)
- [Zenvo TSR-S 1177 bhp twin-supercharged V8](https://zenvoautomotive.prezly.com/zenvo-reveals-latest-commission-tsr-s-hypercar)

For additional per-model links, see `source_spec_url` and `source_price_url` on each entry. Manufacturer specifications apply only to the selected trim/year/fuel; the 2023 Jesko Attack entry, for example, uses its **E85** power rating. The Gemera is the HV8/Dark Matter variant rather than the earlier three-cylinder prototype. Honda's 2025 Civic Type R `$45,895` is MSRP **before** the $1,150 destination charge.

## Runtime integration and safeguards

- Each entry points to an existing PNG in `res://assets/Vehicles/` and is treated as verified artwork rather than a placeholder.
- Width, length and wheelbase populate the drawing scale, capsule collision geometry, and independent four-wheel visual anchors. Final wheel-hub centering and sprite-forward orientation still require visual review because the art has inconsistent source framing.
- The factory output, weight and drivetrain feed `VehicleConfig`; forward gear counts map to **class-level ratio profiles**, not actual OEM gear sets. Hybrid and electric vehicles share simplified game physics: multi-motor power/regen are not individually simulated. Braking force, grip and boost settings are **gameplay tuning**, not factory measured data.
- All cars have a valid existing dealership tier and driver-level requirement; purchases, owned status, save files, upgrades and garage selection already read the same expanded catalog.
- Audio models use existing engine families and induction types. Cars with electric or hybrid reference powertrains receive their corresponding audio flags; Zenvo TSR-S uses the implemented supercharger profile and flat-plane V8 sound; the Koenigsegg Regera uses its documented 2.73:1 single-speed hybrid direct drive instead of the electric-car reduction ratio.
- Tests were expanded from 98 to 148 and a separate `tests/new_vehicle_additions_test.gd` checks every newly added sprite, config, price label, gearbox, audio, dealership membership, source metadata, legacy IDs, and example values. GitHub Actions runs that test on both Godot 4.6.3 and 4.4.1.

## Remaining validation limits

Automated alpha bounds can fit the collision body and wheels, but they cannot reliably infer which way a sprite faces or whether every visual wheel hub aligns precisely. An in-game visual inspection of all 50 is still recommended. Likewise, where `spec_confidence` is `representative_trim` or `price_basis` is an estimate, a current regional/VIN-level valuation would need additional evidence before calling the amount a verified market transaction price.
