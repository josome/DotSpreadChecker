# DotSpreadChecker

Check if the important dots are spread around the mobs.

World of Warcraft (Retail, Midnight 12.x) addon that shows how far your DoTs are spread in the current pull.

One square per enemy nameplate in combat. A square turns red once every DoT tracked for your spec is on that enemy. The red state is drawn by Blizzard's AuraContainer widget, so the addon never reads aura data and keeps working under the 12.x secret-value restrictions.

## Tracked DoTs

| Spec | DoTs |
|---|---|
| Affliction Warlock | Agony |
| Shadow Priest | Vampiric Touch + Shadow Word: Pain |
| Fire Mage | Ignite |
| Unholy Death Knight | Virulent Plague |
| Assassination Rogue | Rupture + Garrote |
| Arms Warrior | Rend |
| Enhancement Shaman | Flame Shock |
| Balance Druid | Moonfire + Sunfire |
| Feral Druid | Rake + Rip |

Each DoT can be unticked per spec in the options to ignore it.

## Usage

- Options: Esc → Options → AddOns → DotSpreadChecker
- `/dots` toggles lock, `/dots reset | combat | minimap | debug | probe`
- Position, square size and squares per row are saved per character.

## Credits and license

Based on WADM by guezito (itself a fork of ARDM). GPL-2.0-or-later.

## Releasing

Raise `## Version` in `DotSpreadChecker.toc` (for example to `0.13.0` or `0.13.0-beta.1`) and push to `master`. The "Package and release" workflow then creates the tag `v0.13.0`, builds `DotSpreadChecker-v0.13.0.zip` with a single `DotSpreadChecker/` folder and publishes it as a release. Versions with `alpha` or `beta` become pre-releases. A push without a version change releases nothing. Use the packaged zip, not GitHub's automatic "Source code" archive.
