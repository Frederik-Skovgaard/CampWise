# Changelog

## 2.0.1 (2026-11-13)

Fixes from a code audit, mostly camp sharing privacy and safety.

- Sharing with everyone on the realm is now off by default, and is turned off once for everyone who had it from the old default. Party/raid and guild sharing are unchanged. The settings and README now say it reaches the whole realm, not just nearby players
- Shared camps send object IDs instead of names. Received objects that CampWise doesn't know are dropped, so other players can't put their own text in your pins or chat
- Hovering your own Craft buttons, bag items or action bars no longer marks an object as "at this camp"; only objects in the world count
- Other players' reports can no longer change your own camp, and a single report can't leave a camp marked purple for good
- Your own camp is never pushed off the list, and only 20 new camps from others are accepted per minute
- Only one "Your camp" pin when you move to a new fire
- At least 15 seconds between your own camp messages; a throttled message is retried
- Aura changes are handled once per burst instead of by every module separately, which cuts work in combat
- Map pins only redraw when the map, zoom or camps change
- The hidden realm channel is left when you turn sharing off
- Messages from players on other realms with your character name are no longer ignored
- Opening CampWise from the game's AddOns settings no longer closes that panel (taint risk)
- Map pins and `/cw camps` only show camps in the zone you're in
- Your own camp pin updates as soon as the camp changes, instead of on the next share
- Pin tooltips no longer break or flicker while the minimap redraws
- The Camp Benefits buff tooltip no longer gets an extra CampWise note
- New original chair picture for the Sit button, replacing one made from game art
- A stale camp arrival time saved before a PC restart is now discarded

## 2.0.0 (2026-11-13)

- Shared camps: sitting at a fire shares its spot, objects and purple flame with party/raid, guild and nearby CampWise users
- World map and minimap pins for your own and shared camps, with a tooltip listing the objects
- Camp sharing settings with a toggle for each channel; `/cw camps` and `/cw share`
- Leftover Camp Benefits and tent lockouts from an earlier camp no longer count toward the camp you're at
- Hover a camp object near a fire to mark it as being at this camp
- Boosted Rest is now read correctly (it's a debuff)
- Missing timers show the buff's icon instead of a question mark

## 1.0.0 (2026-11-13)

First release.

- Camp buff timers with progress bars, low-time warnings and Violet Flames detection
- Camp bar with Sit, Use and Craft groups, shown near a campfire
- Craft buttons limited to learned professions, with crafted kits added to Use automatically
- Camp contents read from the Camp Benefits buff
- "What to place next" suggestion based on your group, the camp and class buffs
- Tooltip lines for campfires, camp objects, kits and Camp Benefits
- Settings window with three themes (Blizzard native, Clean flat, Rustic campfire), colours, opacity, border, font size and width
- Mouse shortcuts: right click for settings, Ctrl + click to lock, Shift + click to collapse
