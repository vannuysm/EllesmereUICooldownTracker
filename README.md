# Forever Cooldown Tracker (Ellesmere UI)

A fork of [Forever Cooldown Tracker (Paladin & More)](https://www.curseforge.com/wow/addons/forever-paladin-cooldown-tracker), originally created by **Ugge Zen (Uggezen)**. This repository builds on the 2.0.3 addon and improves the experience of managing tracked entries through EllesmereUI.

## Credit and thanks

Huge thanks to **Ugge Zen** for creating the original addon and making it available under the MIT license. The cooldown tracking, buff timers, reminders, spell-rank tools, settings kit, and profile system provide the foundation for this project. This fork builds on it with improvements to the EllesmereUI settings experience.

Thanks also belongs to the EllesmereUI authors for the UI framework and plugin APIs used by the integration.

Please visit the [original addon on CurseForge](https://www.curseforge.com/wow/addons/forever-paladin-cooldown-tracker) to check out and support Ugge Zen's work.

## Changes in this fork

### Visible, draggable tracking lists

The same editor is used on all four pages:

| Panel | Page | Entries managed |
| --- | --- | --- |
| Buff Bars | Tracked Buffs | Buff names and prefixes |
| Cooldown Bar | Tracked | Spell and item names |
| Reminders | Your Buffs | Personal buffs and alternative groups |
| Reminders | Ally Buffs | Buffs for others and alternative groups |

Each list provides:

- Drag handles and drag-and-drop reordering.
- A floating label and insertion line showing where an entry will land.
- A **Remove** button at the far right of each row.
- Cancellation when a drag is released outside the list or the page is hidden.
- Protection against editing an outdated list after settings or a profile change.

### Shared components

`OrderedList` and `TrackingEditor` in [EllesmereIntegration.lua](EllesmereIntegration.lua) implement the shared list and add controls. Each page supplies its settings list, labels, and matching explanation. Reordering, adding, and removing entries refresh the appropriate tracker and its EllesmereUI page cache.

### A separate addon identity

The fork installs as `EllesmereUICooldownTracker` and uses its own saved variables (`EUICT_DB` and `EUICT_DBC`), named frames, addon-compartment callback, slash commands, and integration registration keys. Its TOC also omits the original CurseForge project ID so addon managers do not associate the fork with the upstream release.

Settings and profiles are stored separately from the original addon. To transfer a setup, export a profile from the original addon and import it on this fork's Profiles page; the shared `FCT1` profile format remains compatible.

The EllesmereUI sidebar label is **Cooldown Tracker (Ellesmere)** because the public plugin API reserves labels beginning with `EllesmereUI` or `EUI` for its own modules.

## Installation and use

1. Copy the addon files into your WoW installation's `Interface/AddOns/EllesmereUICooldownTracker` folder, with `EllesmereUICooldownTracker.toc` directly inside it.
2. Enable **EllesmereUI** to use the integrated settings pages. **EllesmereUIActionBars** is optional and supplies the appearance and glow settings used by the integration.
3. Run `/reload`, open EllesmereUI, and select **Cooldown Tracker (Ellesmere)** to manage the tracking lists.

The underlying addon also provides its standalone settings through `/euict` or `/ellesmerecooldowns` when EllesmereUI is unavailable.

## License

This project is licensed under the [MIT License](LICENSE).

- Copyright (c) 2026 Ugge Zen — original work.
- Copyright (c) 2026 Matt VanNuys — modifications and additions.

The original copyright notice and MIT permission terms are retained in `LICENSE` alongside the attribution for this fork's contributions.
