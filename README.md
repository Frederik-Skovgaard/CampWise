# CampWise

All-in-one camping helper for **WoW: Forever**. One addon instead of five: camp buff timers, a single bar for your campfires and camp objects, clear tooltips, and a "what to place next" suggestion, plus shared camp pins on the map. Everything except sharing works solo, with nobody else needing the addon.

## Features

- **Buff timers.** Camp Benefits, Well Fed, Boosted Rest and Well-Rested, with progress bars that drain and turn yellow, then red, as they run low. You get a chat warning before a buff runs out (5 minutes by default). It spots the purple campfire's **Violet Flames** (doubled effects, 2 hours).
- **Camp bar.** It appears when you're near a campfire.
  - **Sit:** a big button for sitting by the fire.
  - **Use:** your campfire kit, crafted camp kits and other camp items.
  - **Craft:** your campfire and camp-object recipes, only from professions you've learned. Click once to open the recipe and again to craft it.
- **What's at this camp.** It reads your Camp Benefits buff to list the objects already placed. Recipes for professions already at the camp get a tick.
- **What to place next.** It glows the object that helps the most people in your group. It skips professions already at the camp and stats a class buff already covers, such as Arcane Intellect or Fortitude.
- **Tooltips.** Campfires, camp objects, kits and Camp Benefits get a short line saying what they do.
- **Shared camps.** When you sit at a fire, CampWise shares its spot, the objects there and whether it's a purple campfire with your party or raid and your guild. Each message carries your character name. You can also turn on sharing with **everyone on your realm** who runs CampWise (off by default, since it tells strangers your name and exact spot). Camps in the zone you're in show as pins on the world map and minimap; camps in other zones stay hidden so they don't get in your way. Hover a pin to see what's there. Pins expire after 10 minutes without a report. Each channel can be turned off in settings.
- **Three themes:** Blizzard native, Clean flat and Rustic campfire. You can also change colours, opacity, borders, font size and width.

## Controls

| Action | Timer box | Camp bar background |
|---|---|---|
| Right click | Open settings | Open settings |
| Ctrl + left click | Lock / unlock position | Lock / unlock position |
| Shift + left click | Collapse / expand | — |
| Left drag | Move (when unlocked) | Move (when unlocked) |

## Slash commands

`/cw` or `/campwise`:

- `config`: settings window
- `timers`, `bar`: show or hide a box (`lock`, `reset`, `scale <n>`, `<minutes>` for the timer warning)
- `next`: print the suggested object
- `camp`: list the objects at this camp
- `camps`: list shared camps
- `share`: turn camp sharing on or off
- `advisor`, `tooltips`: turn suggestions or tooltip lines on or off
- `auras`, `auras all`: list your camp buffs or all buffs with spell IDs (for bug reports)

## Known limits

- The game doesn't expose campfires to addons, so CampWise works from your buffs. The camp list only includes objects whose benefit you've received, so sit again after someone places a new one. Camp Benefits and the tent's Boosted Rest last an hour and follow you to the next fire, so they only count if you got them at the fire you're at. You can also hover an object in the world to mark it as being at this camp.
- Some names are matched in English: Violet Flames, Well Fed, profession names and class buffs.
- Buffs can be hidden from addons during combat. Timers show "hidden" until combat ends.

## Bugs and suggestions

Please open an issue at https://github.com/Frederik-Skovgaard/CampWise/issues. For buff problems, include the output of `/cw auras`.

## Releasing

Update `## Version` in CampWise.toc and CHANGELOG.md, commit, then push a tag such as `v2.0.2`. The Release workflow builds the zip with the BigWigs packager and uploads it to GitHub Releases, CurseForge and Wago.

## License

MIT. See LICENSE. The chair picture (Media/CampChair.tga) is original CampWise art under the same license.
