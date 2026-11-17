# Streetbound: vehicle pricing and factory-spec audit
**Catalog date:** 2026-11-16 · **Scope:** all 98 *playable* vehicle entries (including nine recent additions)

## Scope, evidence and honest limits

The previously published 98-car roster in `data/player_vehicle_catalog.json`
had 98 named cars but many powertrain and dimension tuples copied between
unrelated models. Its `notes` explicitly described prices and stats as
fictional or provisional. This audit replaces those copies with a **specific
reference model year and trim** for every playable car and records what level
of evidence supports the entry.

For the full row-by-row before/after comparison, see
[`docs/vehicle_spec_price_audit.csv`](vehicle_spec_price_audit.csv). Its 30
columns include the old and new horsepower, torque, mass, dimensions,
drivetrain and price; the reference trim and gearbox; price basis; mass and
torque exceptions; and any directly consulted manufacturer/secondary source.
The catalog itself carries the same reference fields.

**Evidence boundary:** 34 vehicle records are marked
`spec_confidence: source_checked` and contain a directly consulted
manufacturer or automotive reference URL. The other **64 are marked
`representative_trim`**, with model-specific approximations but **not
individually source-verified**. Do not present all 98 as officially verified.
This is an exhaustive *catalog audit and correction pass*, not an exhaustive
VIN/options-level verification or live appraisal.

### Price basis: USD, but never mix estimates with official MSRP

| `price_basis` | Number | Interpretation |
| --- | ---: | --- |
| `msrp_usd` | 16 | Published approximate/base U.S. MSRP for selected year/trim |
| `msrp_estimate_usd` | 32 | Estimated U.S. MSRP for a representative trim/year |
| `used_estimate_usd` | 30 | Illustrative 2026 U.S. used-market estimate |
| `international_used_estimate_usd` | 3 | Overseas used value expressed in USD (e.g. MiTo, Giulietta, Brera), **not** a U.S. listing |
| `collector_estimate_usd` | 7 | Illustrative collector/auction market estimate, not an active quote |
| `converted_launch_estimate_usd` | 10 | Rough USD equivalent of limited-production overseas launch pricing |

A quoted `price_usd` remains the **in-game purchase price**; it is *not*
a commitment to real availability. Model condition, mileage, exchange rate,
delivery fees, regional tax, dealer markup and equipment can materially
change real prices. Prices are not inflation-adjusted. Future features can
use separate economy tuning rather than overwriting audited market references.

## Major corrections

| Vehicle/trim | Previously | Audited reference |
| --- | --- | --- |
| 2025 Acura Integra Type S | 237 hp, RWD, 1,050 kg | **320 hp, FWD**, 1,460 kg, $52,900 March 2025 published MSRP |
| 2025 Cadillac CT5-V Blackwing | 288 hp, 350 Nm, $55k | **668 hp, 893 Nm**, RWD, $95,595 base MSRP |
| 2026 Cadillac Celestiq | 288 hp, RWD, $55k | **655 hp, dual-motor AWD**, ~$340k starting-price estimate, EV audio |
| 2026 Chevrolet Corvette ZR1X | RWD, $315k | **AWD hybrid**, 1,250 hp, $209,700 Chevrolet January 2026 published MSRP including destination |
| 1987 Ferrari F40 | 932 hp / 1,640 kg | **478 hp, ~1,235 kg**, period factory specifications |
| 1994 Bugatti EB110 GT | 1,274 hp / 1,980 kg | **560 hp / 1,620 kg**, 3.5 L quad-turbo V12 |
| 2026 Bugatti Tourbillon | 1,274 hp, $250k | **1,800 metric PS (~1,775 mechanical hp)** combined V16 hybrid, ~$4.2m estimated foreign-launch conversion |
| Bugatti W16 Mistral | $250k, 1,274 hp | **1,578 mechanical hp / 1,600 PS**, ~$5.5m estimated conversion |
| 2021 Bentley Bacalar | $250k, RWD | **650 hp, W12 AWD**, limited-series estimated converted-launch pricing |
| 2023 Bentley Batur | $250k, RWD | **730 hp, W12 AWD**, limited-series estimated converted-launch pricing |
| 2019 Bentley Mulsanne | AWD, ~2,054 kg | **RWD, 2,711 kg**, 505 hp, 1,020 Nm |
| 2014 Alfa Romeo MiTo | RWD | **FWD**; 2015 Giulietta likewise FWD |
| 2015 Dodge Dart / 2005 Dodge Neon | RWD | **FWD** |
| 2024 BMW M8 Competition | RWD | **AWD** |

In total the before/after CSV records 82 horsepower changes, 73 torque
changes, 92 mass changes, 16 drivetrain changes, 63 geometry changes and
92 purchase-price changes. Unchanged numbers may still differ slightly
from a different model year, optional package or exact VIN.

## Physics and metadata

- `reference_year`, `reference_trim`, `reference_transmission`,
  `reference_gear_count`, `reference_powertrain`, `price_basis`,
  `spec_confidence`, `reference_mass_basis`,
  `reference_torque_basis` and `source_spec_url` are available per car.
- `PlayerVehicleCatalog.make_configuration()` applies each corrected
  power/torque, curb-or-dry mass, drivetrain and **gear count** to the active
  vehicle. It no longer silently adds 5% extra torque to trucks and SUVs.
- **Important simulation limitation:** the gear-count-specific ratio profiles
  are intentionally generalized and not actual model-specific OEM gear
  ratios, final drives or torque-converter curves. Gear count is correct for
  the chosen reference trim; speed/shift feel needs separate calibration.
  EVs get a single reduction gear rather than a six-speed transmission.
- The CELESTIQ is now a genuine `electric` acoustic profile, and the i8,
  NSX, 296 GTB, Tourbillon, ZR1X and Bentley Continental hybrid models
  enable the hybrid launch mix. This does not yet model electric motor
  regeneration or full multi-motor torque physics independently.
- **Manufacturer dry weights:** Ferrari F50 and Bugatti Bolide are labeled
  as dry-weight references; do not compare directly to curb-weight rows.
  Bugatti Tourbillon's public manufacturer mass is *under* 1,995 kg;
  1,995 is used here as a bounding modeling value.
- The Tourbillon, Valkyrie and Corvette ZR1X have published **combined
  hybrid horsepower** but the catalogue's torque figures are combustion-
  engine references, not invented summed system torque.
- The Bolide is a **track-only** car; being driveable in a game does not
  imply road-legal status.
- `brake_force_n`, `tire_grip` and `boost_max_psi` remain *gameplay
  coefficients* (boost modeled for sound/response). They are not actual
  instrumented OEM braking, skidpad or measured boost data.
- Existing `id` values, ownership, wheel-art calibration, race unlock
  levels, 10 dealer assignments and the upgrade system remain intact.
  Some source artwork is still explicitly unverified and uses a provisional
  silhouette—price/spec work does not validate missing sprites.

## Selected primary and secondary technical references

Direct source URLs for all 34 cross-checked entries are retained in the
machine-readable CSV and JSON. Representative high-signal sources include:

- [2025 Acura Integra / Type S fact sheet](https://www.acura.com/-/media/Files/Vehicles/INTEGRA/2025/Type-S/Acura_2025_Integra_Type-S_Fact_Sheet.pdf?cache-busting=1.1.1)
- [2025 Cadillac CT5-V Blackwing specifications](https://brochures.cadillac.com/2025/ct5-v-series/specs-models/)
- [2026 Cadillac Celestiq](https://www.cadillac.com/electric/celestiq)
- [Chevrolet's original 2026 ZR1X MSRP announcement](https://news.chevrolet.com/content/public/us/en/chevrolet/newsroom.detail.html/Pages/news/us/en/2025/aug/0806-Chevy-Corvette-ZR1X-pricing-reveals-Quail-Silver-Edition.html)
- [Chevrolet 2025 Corvette ZR1 MSRP and 1,064 hp](https://news.chevrolet.com/newsroom.detail.html/Pages/news/us/en/2025/jan/0109-zr1.html)
- [2024 Alfa Romeo Giulia 2.0 Turbo specs](https://s3.amazonaws.com/chryslermedia.iconicweb.com/mediasite/specs/2024_AR_Giulia_SP.pdf)
- [2025 Audi RS3 specs](https://www.caranddriver.com/audi/rs3/specs/2025/audi_rs3_audi-rs3_2025)
- [Bentley Mulsanne: 2019 specifications](https://www.edmunds.com/bentley/mulsanne/2019/st-401848858/features-specs/)
- [Bentley Arnage: 2008 specifications](https://www.edmunds.com/bentley/arnage/2008/st-100986896/features-specs/)
- [Bugatti EB110 GT comparison](https://newsroom.bugatti.com/api/en/press-releases/pdf/bugatti-eb110-vs-chiron-super-sports-and-hyper-sports-cars-compared)
- [Bugatti W16 Mistral technical sheet](https://bugatti-newsroom.imgix.net/687a1f84e4a10282f1c9db98/technical-specifications-w16-mistral-en.pdf)
- [Bugatti Tourbillon technical sheet](https://bugatti-newsroom.imgix.net/6675179393f6515cdb966608/technical-specifications-bugatti-TB-en.pdf)
- [Bugatti Bolide technical sheet](https://bugatti-newsroom.imgix.net/67a4b4ec6578153cb3dd2194/technical-specifications-bugatti-bolide-en.pdf)
- [Ferrari F50 period specifications](https://cdn.ferrari.com/cms/network/media/pdf/CS_Ferrari_F50_Legacy_Tour_end_2025_ita.pdf)
- [Ferrari Purosangue year/trim specs](https://www.caranddriver.com/ferrari/purosangue/specs/2024/ferrari_purosangue_ferrari-purosangue_2024)
- [Aston Martin One-77 factory brochure](https://astonmartins.com/wp-content/uploads/2013/01/one-77-brochure.pdf)

## Validation

The `tests/vehicle_realworld_audit_test.gd` checks all 98 IDs and required
reference fields, disallows silent reintroduction of class-copy tuples,
checks source-status labeling, verifies applied physics, drivetrain and
forward gear counts, and locks in key high-profile corrections. Existing
roster, dealership, ownership and audio tests continue to validate the
same save and purchase flows on Godot 4.4.1 and 4.6.3.

## Future-requested vehicle list is not a playable catalog

`assets/Vehicles/streetbound_vehicle_list.txt` contains **259 model
requests**: 212 grouped by manufacturer and 47 subsequent year-specific or
one-off requests. Some overlap with the 98 playable catalog. Another
`data/pending_vehicle_audio_profiles.json` holds **154 future/pending audio
profiles**, not 154 additional purchasable cars. Neither source provides
complete price/trim/year-specific production data for a playable model. The
audio request parser now reads the actual source location and both sections;
previously it read zero models from a retired path. The future request list
is not silently turned into playable cars or invented dealership prices.
The exhaustive real-world **pricing and spec audit covers the 98 actual
playable vehicle IDs**, not unimplemented ideas on the future list.

## Further independent work

The 64 representative (not directly checked) trims and every price labeled
`*_estimate_usd` require a separate year/trim-specific source comparison
or actual vehicle listing to claim exact real-world accuracy. Those rows
are openly marked in the CSV rather than silently counted as verified.

**Power units:** For Bugatti Tourbillon, manufacturer-stated 1,800 metric PS translates to approximately 1,775 U.S. mechanical horsepower; the in-game imperial HP display uses 1,775. 1 PS = 0.98632007 mechanical hp.

**2024 price cross-checks:** Acura TLX Technology FWD $45,000 MSRP excluding destination (<https://hondanews.com/en-US/releases/release-ce25b2bdc6167d48c9de61f4f905a9f8-2024-acura-tlx-tlx-type-s-pricing-epa-ratings>); Alfa Romeo Stelvio Sprint AWD $47,950 MSRP excluding destination (<https://www.cars.com/research/alfa_romeo-stelvio-2024/specs/439865/>).

## Follow-up source verification — November 16, 2026

This second verification pass corrected **six records** against more precise
year/trim references. Three previously unreferenced vehicles are now
`source_checked`; their *estimated* in-game prices remain labeled as
estimates unless an MSRP was published.

| Vehicle | Previous audit | Updated reference |
| --- | --- | --- |
| 2025 Acura Integra A-Spec w/Technology 6MT | 1,435 kg; $37,400 | **1,394 kg** (3,073 lb); **$38,000** U.S. MSRP excluding destination; precise trim name |
| 2025 Acura Integra Type S | $52,600 initial fact-sheet price | **$52,900**, Acura's March 2025 updated MSRP excluding destination |
| 2026 Chevrolet Corvette ZR1X 1LZ Coupe | $207,395 August 2025 launch price | **$209,700**, Chevrolet's published January 2026 starting MSRP including destination |
| 2025 Aston Martin Vanquish | 1,774 kg representative mass | **1,910 kg EU certified unladen** and manufacturer dimensions; 824 bhp and 1,000 Nm verified |
| 2024 Audi Q3 45 TFSI quattro | 350 Nm; 1,760 kg | **340 Nm** (251 lb-ft); **1,776 kg** (3,916 lb) for the referenced U.S. 45 TFSI trim |
| 2024 BMW M2 6MT | 1,755 kg; $65,500 estimated MSRP | **1,730 kg** (3,814 lb); **$64,195** published 2024 U.S. price; 453 hp, 550 Nm, RWD, 6MT |

Manufacturer and automotive sources supporting this follow-up:

- [Acura 2025 model fact sheet and curb weights](https://www.acura.com/-/media/Files/Vehicles/INTEGRA/2025/Acura_2025_Integra_Fact_Sheet.pdf)
- [Acura's March 2025 Integra MSRP update](https://acuranews.com/en-US/releases/2025-acura-integra-pricing-epa-ratings)
- [Chevrolet's January 2026 ZR1X MSRP and published performance](https://news.chevrolet.com/newsroom.detail.html/Pages/news/us/en/2026/jan/0113-zr1x.html)
- [Aston Martin's Vanquish factory dimensions and unladen weight](https://www.astonmartin.com/en-us/models/vanquish)
- [Edmunds 2024 Audi Q3 45 TFSI technical details](https://www.edmunds.com/audi/q3/2024/features-specs/)
- [Car and Driver 2024 BMW M2 Coupe specs and MSRP](https://www.caranddriver.com/bmw/m2/specs/2024/bmw_m2_bmw-m2_2024)

**Remaining limitation:** 64 representative entries and all prices explicitly
labeled `*_estimate_usd` still need individual primary-source or live-market
verification before the entire roster can be called fully accurate.
