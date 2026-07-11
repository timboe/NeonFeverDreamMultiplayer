# NeonFeverDream — Game Design

## Overview

Top-down MOBA/strategy game in the vein of Future Cop LAPD with a mutable playfield mechanic (Dungeon Keeper-style). Set on a Cairo pentagonal tiling grid.

Four-unit rock-paper-scissors combat system, six building types, and a dual-mode player avatar that trades RTS macro for FPS micro.

* * *

## Players

2-4 players, human or AI control.

Symmetric or asymmetric maps, hand-crafted, formed mainly of raised tiles. With some tiles lowered at the start of the game.

Containing obsidian tiles around the perimeter and forming forced blocked and open areas within the map. Obsidian tiles are fixed in their pre-set raised or lowered position and cannot be changed by any players.

When not in FPS-mode commanding a rally, unit behavior is automated following rules an not under the direct control of the players.

### Alliance System (Team Play)

Players can toggle hostility per-player (allied, neutral, hostile). Allied players:

- **Share vision** — all allied units and buildings are visible on each other's minimap.
- **Share influence AoE** — allied buildings contribute to a shared team territory for placement and contested-tile purposes. A tile covered by any ally's building counts as team territory.
- **Shared victory** — all allied MCPs must survive. If one is destroyed, all allied buildings and units are destroyed simultaneously. Victory is awarded to the last surviving player or team.
- **Allied interaction** — Zoombas can repair allied buildings. Allied units do not target each other. Allied Garages/Beacons/Nests do not compete for the same Zoomba pool.
- **No shared energy** — each player manages their own energy pool. Energy cannot be transferred between allies (prevents one player bankrolling another).

This structure works for 2v2, 3v1, and 2v1v1 configurations.

## Buildings (6 types)

All buildings are constructed on LOWERED tiles by Zoombas ("imps"). Each building projects an **influence AoE** — a BFS over the pentagonal tile neighbor graph. A player's territory is the **union** of all their building AoEs. Buildings can only be placed within the pre-existing AoE.

Obsidian tiles are excluded from the AoE.

Contested tiles (covered by two+ players' AoEs) can be built on by all contested players, and count toward the zoomba cap split N ways (where N = number of contesting players). This rewards border aggression without double-counting.

Most tiles start RAISED up, tiles within AoE can be LOWERED by Zoombas (pulled down to ground level) at which point they become navigable & buildable. LOWERED tiles can similarly be RAISED back up by Zoombas, blocking the path. Raising and lowering is rate-limited to a concurrent job cap of 3 per player. Requests to raise or lower tiles or place buildings within the AoE are issued by the players in RTS-mode.

All buildings occupy a single tile. Tiles with buildings on them cannot be raised or lowered.

### MCP — Master Command Post

| Property | Value |
| --- | --- |
| Influence radius | 6 tiles (113 tiles) |
| Function | Spawns Zoombas up to AoE controlled cap (costs energy). Internal reactor generates 50% of a Generator's full-AoE output (does not draw from tiles). 1 Vat's worth of energy storage (1000e), pooled with Vats for spending purposes — acts as a free, uninfectable Vat. Does not participate in adjacency bonuses or generator-split mechanics. |
| HP | 15000 |
| Cost | N/A (starting building, cannot be replaced) |
| Avatar buff | Zoomba spawn rate +25% (1 per 1.6s), zoomba move/work speed +20%, MCP damage reduction +25% while the Avatar is empowering the MCP. |
| Avatar Interaction | None |
| Special Function | Destroyed = game over. The only building that cannot be replaced. |

### Generator — Power Extraction

| Property | Value |
| --- | --- |
| Influence radius | 4 tiles (54 tiles) |
| Function | Extracts energy from tiles in its AoE |
| HP | 2000 |
| Cost | 900e |
| Avatar buff | Influence radius +1 tile while the Avatar is empowering this Generator (expand influence, contest more tiles, generate more power). |
| Avatar Interaction | None |
| Special Function | **Tile energy is split.** If N generators (any player) cover the same tile, each receives 1/N of that tile's output. This encourages building generators with overlapping AoEs near enemy generators to syphon their income. |

### Vat — Energy Storage

| Property | Value |
| --- | --- |
| Influence radius | 2 tiles (17 tiles) |
| Function | Stores energy for burst production (unit building, unit production). |
| Base capacity | 1000e (+10% per adjacent friendly Vat, additive 0-50%) |
| HP | 1500 |
| Cost | 400e |
| Avatar buff | +20% storage while the Avatar is empowering this Vat (stacks with adjacency bonus). |
| Avatar Interaction | None |
| Special Function | **Adjacency bonus:** each Vat gains 10% additional capacity for each adjacent friendly Vat (1-hop on the tile graph, additive, 0%-50%). **Shared health pool:** adjacent Vats share HP (for each vat, 10% less per adjacent vat, additive, 0%-50%, then summed over all connected vats). **Infection cascade:** VIRUS infection spreads to all connected Vats in an adjacency chain. |

### Garage — Tank Factory

| Property | Value |
| --- | --- |
| Influence radius | 3 tiles (33 tiles) |
| Function | Produces TANKs. Each TANK requires one Zoomba as pilot. TANK creation is relatively slow (1 per 6s). Each Garage has a ZOOMBA/TANK ratio slider (0–100%, default 50/50, minimum one zoomba). Each Garage tracks a target tank count = its ratio × total free Zoombas. Garages compete for available Zoombas round-robin each tick. |
| HP | 2000 |
| Cost | 750e |
| Avatar buff | TANK fire rate +25% against aerial targets for all TANKs created by any Garage while the Avatar is empowering that Garage (to be play tested, adjust if needed). |
| Avatar Interaction | Avatar controls the fraction of Zoombas which should mount up in a tank. The setting is applied per Garage. Ratio is viewable from RTS mode, editable only in FPS mode at a garage. In addition, avatar can toggle tank production from each individual garage. |
| Special Function | None |

### Beacon — Aerial Factory

| Property | Value |
| --- | --- |
| Influence radius | 2 tiles (17 tiles) |
| Function | Produces AERIAL units (1 per 4s). Each Beacon has a **PATROL/STRIKE ratio slider** (0–100%, default 50/50). |
| HP | 2000 |
| Cost | 750e |
| Avatar buff | All AERIAL units produced by any Beacon while the Avatar is empowering that Beacon: lifetime +30s from 2m to 2m30s (to be play tested) |
| Avatar Interaction | Avatar controls the ratio of ariel units created as Patrol units vs Strike units. The setting is applied per Beacon. Ratio is viewable from RTS mode, editable only in FPS mode at each beacon. In addition, avatar can toggle aerial production from each individual beacon. Diegetic UI at each Beacon includes STRIKE target priority and PATROL stance controls (see Diegetic Building UI section). |
| Special | None |

### Nest — Virus Factory

| Property | Value |
| --- | --- |
| Influence radius | 2 tiles (17 tiles) |
| Function | Produces VIRUS units (1 per 5s). |
| HP | 2000 |
| Cost | 750e |
| Avatar buff | VIRUS speed +30% while the Avatar is empowering this Nest. TANKs being attacked by VIRUS are immobilized and cannot fire against AERIAL. |
| Avatar Interaction | Avatar controls VIRUS targeting and production via the Nest's diegetic UI (see Diegetic Building UI section). Production toggle on/off available per Nest. Settings viewable (read-only) from RTS mode, editable only in FPS mode. |
| Special | None |

* * *

## Units (6 effective types)

### Avatar (Direct player influence — non-combat)

| Property | Value |
| --- | --- |
| Territory | Anywhere on the map, including enemy territory. |
| Max count | 1 |
| HP | 200 |
| Respawn time | 8s |
| Lifetime | Permanent, respawns when killed |
| Cost | Free (respawn) |
| Function | Player's avatar embodies their direct influence in the game world. Click on a friendly building within 1 tile to empower it (FPS only). That building's avatar buff becomes active. Empowerment cancels if the avatar moves more than 1 tile away. Empowerment status is preserved when leaving FPS mode. |
| Interaction: Zoomba | When under active control, may tag enemy zoomba to direct attack. |
| Interaction: Tank | When under active control, may tag enemy tanks to direct attack. |
| Interaction: Aerial Patrol | When under active control, may tag enemy patrol units to direct attack. Vunerable to attack from enemy patrol units. |
| Interaction: Aerial Strike | When under active control, may tag enemy strike units to direct attack. Vunerable to attack from enemy strike units. |
| Interaction: Virus | When under active control, may tag enemy virus units to direct attack. Un-cloaks enemy virus units. |
| Interaction: Buildings | When under active control, may tag enemy buildings to direct attack. |
| Special | When under active control, has time-limited RALLY ability. Nearby friendly units join the Avatar's rally party and will follow the avatar until it is destroyed or the player leaves FPS-mode. RALLIED units within 4 tiles of the Avatar gain +10% damage (tether bonus). Marking a priority target (crosshair click) causes the rallied squad to deal +25% damage against that target (ping amplifier). Recovers 10 HP/s when out of combat for 5s (similar to zoombas). |

### Zoomba (Worker — non-combat)

| Property | Value |
| --- | --- |
| Territory | HOME only (never leaves owned/contested tiles) |
| Max count | `floor(sqrt(tile_count × 8))` |
| Lifetime | Permanent |
| Cost | 25e |
| HP | 50 |
| Function | Primary role is to constructs buildings, repairs damaged buildings, raises/lowers tiles, pilots TANKs. |
| Interaction: Zoomba | May encounter enemy zoomba only on contested tiles. Does not interact with enemy zoomba. |
| Interaction: Tank | May encounter enemy tanks only on contested tiles. Does not interact with enemy tanks. |
| Interaction: Aerial Patrol | May encounter enemy Patrol units only on contested tiles. Scrams if under fire. |
| Interaction: Aerial Strike | May encounter invading enemy strike units on home or contested tiles. Scrams if under fire. |
| Interaction: Virus | May encounter invading enemy  virus on home or contested tiles. Does not interact with virus. Does not de-cloak virus. |
| Interaction: Buildings | Does not interact with enemy buildings on contested tiles. |
| Special | Only created at MCP. Heals 10 HP/s when out of combat for 5s (not being attacked, not in scram). **Scram:** when attacked by enemy STRIKE or PATROL on contested tiles, paths to MCP at high speed for 3s. After scram ends, resumes normal behavior. |

### TANK (Ground Defender)

| Property | Value |
| --- | --- |
| Territory | HOME only (never leaves owned/contested tiles) |
| Max count | Zoombas - 1 |
| HP | 400 |
| Lifetime | Permanent |
| Cost | 150e (plus 1 Zoomba pilot — 25e one-time) |
| Function | Patrols owned/contested territory. Provides AA-cover against aerial units. |
| Interaction: Zoomba | May encounter enemy zoomba only on contested tiles. Does not interact with enemy zoomba. |
| Interaction: Tank | May encounter enemy tanks only on contested tiles. Does not interact with enemy tanks. |
| Interaction: Aerial Patrol | May encounter enemy Patrols only on contested tiles. STRONG engagement against aerial enemy units (6x bonus). |
| Interaction: Aerial Strike | Primary role is to intercepts enemy aerial strike units invading home / contested tiles. STRONG engagement against aerial enemy units (5x bonus). |
| Interaction: Virus | Cannot detect cloaked VIRUS. When a VIRUS uncloaks to attack the TANK (~10s to destroy), the TANK can queue a kill-VIRUS job for nearby PATROL units. The TANK has no direct defense and relies on PATROL support during the 10s attack window. |
| Interaction: Buildings | None |
| Special | Each TANK requires 1 Zoomba pilot. Total TANK cap = current Zoombas − 1. Tank destroyed → explodes, leaving the pilot Zoomba at the center of the wreckage (returns to workforce immediately). Repairs 25 HP/s when out of combat for 5s (not taking damage, not firing). Follows the avatar if RALLYED, but will not leave home / contested territory. |

### AERIAL — PATROL Mode (Air Defender)

| Property | Value |
| --- | --- |
| Territory | HOME (patrols friendly/contested territory). Flies at a medium altitude. |
| Max Count | Limited only by finite lifetime |
| Lifetime | 2 minutes or until shot down. Fuel and health are separate resource bars. Cannot be re-fueled or repaired. |
| Cost | 100e |
| HP | 400 |
| Function | Patrols owned/contested territory. Provides virus protection by detecting and engaging cloaked VIRUS. Primary anti-VIRUS unit. |
| Interaction: Zoomba | May encounter enemy zoomba only on contested tiles. Opportunistic engagement of enemy zoomba, defenseless but low priority target. |
| Interaction: Tank | May encounter enemy tank only on contested tiles. WEAK against tanks. |
| Interaction: Aerial Patrol | May encounter enemy Patrol only on contested tiles. Engages in BALANCED combat. |
| Interaction: Aerial Strike | Intercepts enemy aerial strike units invading the AoE. WEAK against striking enemy aerial units due to height differential. |
| Interaction: Virus | Detects cloaked VIRUS at range (2-3 tile omnidirectional AoE). Automatically queues a kill-VIRUS job for itself upon detection. Strong against VIRUS. If multiple VIRUS are uncloaked simultaneously, nearby PATROL units share the jobs. Will NOT accept kill-VIRUS jobs over enemy territory. |
| Interaction: Building | May encounter enemy buildings only on contested tiles. Opportunistic engagement of enemy buildings on contested tiles, but does not seek these out. |
| Special | Built at a Beacon with the assigned ratio. If following the avatar in a RALLY squad, auto-switches to STRIKE when entering contested/enemy territory, and auto-switches back to PATROL if re-entering home territory. Also switches and back to PATROL when the RALLY disbands. Cannot recover lost health. |

### AERIAL — STRIKE Mode (Air Offense)

| Property | Value |
| --- | --- |
| Territory | ENEMY (flies straight to enemy territory). Flies at a high altitude. |
| Max Count | Same as Ariel Patrol |
| Lifetime | Same as Ariel Patrol |
| Cost | 100e |
| HP | 400 |
| Function | Offensive against enemy base. Target selection is configured per-Beacon via diegetic UI (see UI section). Begins to path towards it with a weighted random walk and A\* waypoints. Intercepts enemies en-route. Once primary target is destroyed, targets next nearest enemy building. A building under attack will issue an order for a friendly tank to come defend it. |
| Interaction: Zoomba | May encounter enemy zoomba on contested and enemy tiles. Opportunistic engagement of enemy zoomba, defenseless but low priority target. |
| Interaction Tank: | May encounter enemy tank units on contested and enemy tiles en-route to attack the enemy base. WEAK against tanks. |
| Interaction: Aerial Patrol | Secondary role is to engage enemy patrol units. May encounter enemy Patrol units on contested and enemy tiles. Engages Patrol, STRONG against patrol due to height difference. x2 bonus. |
| Interaction: Aerial Strike | May encounter enemy strike units on any tile while en-route to attack the enemy's base. Engages in BALANCED combat. |
| Interaction: Virus | Cannot attack VIRUS directly. However, STRIKE can detect cloaked VIRUS within a narrow 1-tile radius (direct overfly). Upon detection, STRIKE queues a kill-VIRUS job for nearby PATROL units. STRIKE will not accept the job itself. Over enemy territory, PATROL will not respond to these jobs — STRIKE's de-cloaking provides intel only for the attacking player. |
| Interaction: Building | Primary role is to target and attack enemy buildings until destroyed. |
| Special | Same as Aerial Patrol. Though switches back to STRIKE when a RALLY disbands. |

### VIRUS (Ground Infiltrator)

| Property | Value |
| --- | --- |
| Territory | ENEMY (moves straight to enemy territory, cloaked from view by default). |
| Max Count | Limited only by finite lifetime |
| Lifetime | 2m (self-depletes at 1.25 HP/s, ~120s from full health). Health stops depleting while channeling an attack (uncloaked). |
| Cost | 100e |
| HP | 150 |
| Function | Offensive against enemy base. Chooses one enemy tank or building to target at random and begins to path towards it with a weighted random walk and A\* waypoints. If no tanks left then chooses a random enemy building. If its target tank is destroyed it then targets the nearest enemy tank or building — whichever is closer. VIRUS remains cloaked while moving but must uncloak to attack a TANK (~10s kill) or infect a building (~10s channel). Infecting a building destroys the virus; infection duration is based on remaining health at the start of the channel: base 15s at full health (150 HP), prorated linearly (e.g. 75 HP = 7.5s infection). Multiple VIRUS infecting the same building stack durations. |
| Interaction: Zoomba | May encounter enemy zoomba on contested and enemy tiles. Does not interact with enemy zoomba. |
| Interaction: Tank | Primary action to target enemy tanks on contested and enemy tiles. VIRUS must uncloak to attack (~10s to destroy a tank). STRONG against tanks. Tank cannot fight back but can queue a kill-VIRUS job for PATROL upon attack start. |
| Interaction: Aerial Patrol | Detected by PATROL at 2-3 tile range while cloaked. WEAK to attack from PATROL if uncloaked. Virus unable to target aerial units. |
| Interaction: Aerial Strike | Detected by STRIKE at 1-tile range (direct overfly). STRIKE queues a kill-VIRUS job for PATROL but will not engage itself. Over enemy territory, PATROL will not respond. Virus unable to target aerial units. |
| Interaction: Virus | May encounter enemy virus units on any tile while en-route to attack the enemies' base. Does not interact with enemy virus units, cloaked or un-cloaked. |
| Interaction: Building | Secondary interaction to target enemy buildings on contested and enemy tiles. VIRUS uncloaks and channels ~10s to infect, destroying itself. The infection effect is based on remaining health. Multiple virus can infect the same building simultaneously (durations stack). Infection is visible to the defender once it begins (uncloaking reveals the VIRUS).<br><br>Infected Generator - Generates power for the virus owner instead of the generator owner while infected.  <br>Infected Vat - Quickly depletes enemy's power reserves stored in the vat when infected. Impacts all connected vats.  <br>Infected Beacon - Drains power and deals 25 DPS to all active enemy Aerial Patrol & Strike units.  <br>Infected Garage - Halves TANK patrol speed and reduces AA fire rate by 80%.  <br>Infected Nest - Causes all enemy virus to lose their cloak and take damage over time while on infected player's territory.  <br>Infected MCP - Halts production of new Zoomba and makes MCP significantly more vulnerable to aerial attack.<br><br>**Cure:** The Avatar can immediately remove all infections from any friendly building by touching it (FPS mode). The single building the Avatar is currently empowering is immune to infection. |
| Special | Cloaked by default. Revealed when: within PATROL detection AoE (2-3 tiles, home/contested territory), directly overflown by STRIKE (1 tile), within Avatar LoS (3-4 tiles in FPS mode, 1 tile in RTS mode), or when beginning an attack on a TANK or building (auto-uncloak). **Strategic note:** VIRUS has no direct counter to PATROL — it cannot attack aerial units at all. A VIRUS player must use STRIKE to deplete enemy PATROL before VIRUS can reach its targets. This creates a combined-arms requirement: VIRUS without STRIKE support is ineffective against a prepared defender. **Infection cap:** A player can have only one active building infection per enemy player at a time. This prevents chain-infecting an entire base and forces the attacker to choose critical targets. |

* * *

## Combat Matrix (4-unit RPS)

Zoomba are excluded as they do not actively participate in combat and scram if shot at by invading STRIKE or by PATROL on contested tiles. They may be destroyed and new ones will need to be re-made at the MCP.

Avatars similarly are excluded as they do not actively participate in combat, they do not scram if shot at by STRIKE or PATROL, they may be destroyed and will re-spawn at the MCP.

| Attacker | Defender | Winner | Mult | DPS | TTK | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| TANK | STRIKE | **TANK** | x5 | 250 | 1.6s | TANK loses ~80 HP (20%). AA intercept. |
| TANK | PATROL | **TANK** | x6 | 300 | 1.3s | TANK loses ~67 HP (17%). Contested only. |
| TANK | VIRUS | **VIRUS** | — | ~40 | 10s | TANK has no ground weapon. VIRUS channels. TANK queues PATROL kill-job. |
| TANK | TANK | — | 0 | 0 | — | No interaction. Cannot target ground. |
| STRIKE | PATROL | **STRIKE** | x2 | 100 | 4.0s | STRIKE loses ~200 HP (50%). Height advantage. |
| STRIKE | TANK | **TANK** | x1 | 50 | 1.6s | STRIKE dies in 1.6s (TANK AA 250 DPS). TANK loses ~80 HP (20%). Ineffective trade. |
| STRIKE | Building | **STRIKE** | x2 | 100 | 15-20s | Primary role. TTK per building type. |
| STRIKE | VIRUS | **—** (intel) | — | — | — | Detects at 1 tile, queues PATROL kill-job. |
| STRIKE | STRIKE | **Draw** | x1 | 50 | 8.0s | Both die simultaneously. Balanced. |
| PATROL | VIRUS | **PATROL** | x5 | 250 | 0.6s | Primary role. Kills nearly on detection. |
| PATROL | STRIKE | **STRIKE** | x0.5 | 25 | 16.0s | Weak vs height disadvantage. Avoids engagement. |
| PATROL | PATROL | **Draw** | x1 | 50 | 8.0s | Both die simultaneously. Balanced. |
| PATROL | TANK/Zoomba/Building | — | x1 | 50 | — | Low priority, opportunistic. |
| VIRUS | TANK | **VIRUS** | — | ~40 | 10s | Channels. TANK queues PATROL support. |
| VIRUS | Building | **VIRUS** | — | ~40 | 10s | Channels to infect, sacrifices self. |
| VIRUS | Aerial | — | 0 | 0 | — | Cannot target aerial units. |

### Damage Multiplier Reference

Base damage rate: **50 DPS**. All combat values derive from this.

| Attacker | vs STRIKE | vs PATROL | vs TANK | vs VIRUS | vs Building | vs Zoomba | vs Avatar |
|----------|-----------|-----------|---------|----------|-------------|-----------|-----------|
| **TANK** | x5 (250) | x6 (300) | 0 | 0 | 0 | 0 | 0 |
| **STRIKE** | x1 (50) | x2 (100) | x1 (50) | x1 (50) | x2 (100) | x1 (50) | x1 (50) |
| **PATROL** | x0.5 (25) | x1 (50) | x1 (50) | x5 (250) | x1 (50) | x1 (50) | x1 (50) |
| **VIRUS** | 0 | 0 | ~40 | 0 | ~40 | 0 | 0 |
| **AVATAR** | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **ZOOMBA** | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The four-way Rock-Paper-Scissors loop (each beats the next):

```
TANK ──(AA 5-6x)──→ STRIKE ──(height 2x)──→ PATROL ──(detects 5x)──→ VIRUS ──(channels 10s)──→ TANK
  │                                          ↗                                                      │
  └─────(AA 6x)──────→ PATROL ─────────────┘                                                       │
       (contested)                                                                  (TANK calls PATROL support)
```

* * *

## Avatar (FPS Mode)

The player's physical first-person representation. Entered via Tab/Enter. Can be killed (respawns at MCP after ~8s).

### Capabilities in FPS

The primary capability is to muster targeted/focused attacks, as opposed to relying on the automated offensive logic. 

The secondary capability is to fine-tune building settings via diegetic UI panels in FPS mode.

| Action | How | Effect |
| --- | --- | --- |
| Spot VIRUS | LoS based | Sees cloaked VIRUS at ground level (3-4 tile range in FPS mode, 1 tile in RTS mode). PATROL-spotted VIRUS is relayed to minimap in RTS mode. |
| Ping VIRUS | Crosshair click on a spotted VIRUS | Queues a kill-VIRUS job for nearest PATROL. Also works on VIRUS spotted by nearby PATROL/STRIKE (relayed to minimap). |
| Prioritize target | Crosshair click on enemy building or unit | Marks it as priority target for the RALLY squad (+25% damage from rallied units). |
| RALLY | Press R (~15s cooldown) | Gathers nearby friendly units (~8 tile radius) into a squad that follows the avatar. AERIAL auto-switch mode by territory. Multiple presses grow the squad. RALLIED units within 4 tiles of the Avatar gain +10% damage (tether bonus). Lasts until avatar death or exit from FPS. |
| Empower building | Click on a friendly building within 1 tile (FPS only) | The Avatar empowers that building: its avatar buff becomes active. Cancels if the avatar moves more than 1 tile away. Status preserved on exit from FPS. |
| Cure infection | Touch an infected friendly building | Immediately removes all VIRUS infections from that building. The building the Avatar is currently empowering is immune to infection. |
| Interact with building | Interact with its diegetic control panel | Alter the building's settings and behavior. See Diegetic Building UI section below. |

### Diegetic Building UI (FPS-mode only)

Each production building has a diegetic control panel accessible in FPS mode. Settings are viewable (read-only) from RTS mode.

For toggle choice options, a new option is chosen for each unit. E.g. if a nest has its slider at 50% Tanks / 50% Buildings, is targeting Blue and Yellow players, and has Generator toggled for buildings. Then on average 25% of created virus attack blue generators, 25% yellow generators, 25% blue tanks and 25% yellow tanks.  

#### Garage
- ZOOMBA/TANK ratio slider (0–100%, per-Garage. Also displays read-only the sum over % of all garages, goes red if over 100%). If the total across all Garages exceeds 100%, Garages compete for available Zoombas but will never convert the last free Zoomba (minimum one Zoomba always remains free).
- Production radio button (on/off)
- TANK stance radio buttom: Hold position (patrol within Garage AoE) / Wide Patrol

#### Beacon
- PATROL/STRIKE ratio slider (0–100%, per-Beacon)
- Production radio button (on/off)
- Enemy player targetting toggle: Red, Blue, Green, Yellow (only hostile players are presented)
- STRIKE targeting toggle: MCP, Vat, Generator, Garage, Beacon, Nest 
- STRIKE targeting radio button: Nearest / Lowest HP 
- PATROL stance radio button: Hold position (patrol within Beacon AoE) / Wide Patrol


#### Nest
- VIRUS TANK/BUILDING ratio slider (0–100%, per-Nest, default 50/50). At 100%, all VIRUS target tanks. At 0%, all target buildings.
- Production radio button (on/off)
- Enemy player targetting toggle: Red, Blue, Green, Yellow (only hostile players are presented)
- Building targeting toggle: MCP, Vat, Generator, Garage, Beacon, Nest (visible when slider is not at 100% Tanks)
- VIRUS targeting radio button: Nearest / Lowest HP 

All settings are toggles, radio buttons or sliders — no patrol routes or waypoints.

### Costs of being in FPS

- No overhead battlefield view
- Cannot place buildings or queue terrain jobs

* * *

## RTS Mode (Overhead)

The default command view. Commands are issued through the Zoomba job queue.

### Capabilities in RTS

| Action | How | Effect |
| --- | --- | --- |
| Lower tile | Click RAISED tile → select to LOWER | Queues `MODIFY_TERRAIN` job. A Zoomba paths there and works it (~10–15s). Tile becomes LOWERED (passable floor). |
| Raise tile | Click un-built LOWERED tile → select to RAISE | Same job in reverse. Tile becomes RAISED (impassable wall). |
| Place building | Click UI button → click valid tile | Same as existing `BuildingManager` pattern. Validates tile, queues `CONSTRUCT_BUILDING` job. |
| View Garage/Beacon/Nest ratios | Hover / UI readout | Shows current building settings. Read-only. |
| View energy | HUD | Income (per tile via Gens), storage (Vats), spend rate |
| View Zoomba cap and Tank count | HUD | Current cap vs current count and number of zoomba in tanks |

### What RTS cannot do

- Change Garage/Beacon/Nest ratios.
- Ground-level scouting (avatar can still spot nearby VIRUS in RTS mode, but at only 1 tile vs 3-4 tiles in FPS mode)
- RALLY troops (FPS-only)
- Directly command combat unit movement via RALLY (they follow patrol/AI behavior when in RTS)

* * *

## Win Conditions

- **MCP destruction** is the only victory condition. When a player's MCP is destroyed, all of their remaining buildings are instantly destroyed (removing their AoE from the map).
- All of that player's units are simultaneously destroyed (no escape portal).
- The game ends when only one player (or one team, for NvN games) remains.
- No surrender mechanic. Stalemates are prevented by: Underdog Grit scaling the behind player's economy and Desperation Meter stacking offensive damage — both escalate the longer a player is behind.

* * *

## Economy

### Flow

```
MCP internal reactor (fixed, 50% Generator output, no tile draw)
      |
      ▼
Claimable tiles (1e/sec each) → Energy extracted by Generators (split among covering generators)
      |
      ▼
Stored in Vats (adjacency bonus, infection cascade risk)
      |
      ▼
Spent on: Zoomba production (MCP), TANK conversion (Garage),
          AERIAL units (Beacon), VIRUS units (Nest),
          building construction, terrain modification (Zoomba time)
```

No starting energy — the MCP's internal reactor provides initial income (27e/sec) while the first tiles are being lowered.

---

### Income Sources

| Source | Output | Condition |
|--------|--------|-----------|
| MCP internal reactor | **27e/sec** (fixed) | Always active. 50% of a Generator's full-AoE output. |
| Generator (ideal) | **54e/sec** | Covers 54 tiles at radius 4. Uncontested. |
| Generator (typical) | **~20-40e/sec** | Early placement near MCP overlap or border. |
| Infected Generator | Income goes to attacker | VIRUS infection, temporary. |

**Tile income split**: If N generators (any player) cover the same tile, each receives 1/N of that tile's 1e/sec output. Contesting enemy generators on border tiles reduces their income.

---

### Vat Storage

| Setup | Capacity | How |
|-------|----------|-----|
| Solo Vat | **1000e** | Base capacity. |
| +1 neighbor | 1100e | +10% per adjacent Vat. |
| Max cluster (5 neighbors) | 1500e | +50% cap. |

1000e holds enough for: ~6 TANK conversions, ~10 AERIAL units, ~40 Zoombas, or 1 Generator + change.

---

### Costs

#### Buildings

| Building | Energy Cost | First affordable (MCP-only) |
|----------|-------------|-----------------------------|
| Generator | 900e | ~33s |
| Vat | 400e | ~15s |
| Garage | 750e | ~28s |
| Beacon | 750e | ~28s |
| Nest | 750e | ~28s |
| MCP | N/A | Starting building, cannot be replaced |

#### Units

| Unit | Energy Cost | Notes |
|------|-------------|-------|
| Zoomba | 25e | Produced at MCP. One-time cost per worker. |
| TANK | 150e | Per-life conversion cost at Garage. Requires 1 Zoomba pilot (25e one-time). When destroyed, pilot returns — pay 150e to re-convert. |
| AERIAL (PATROL) | 100e | Produced at Beacon. 2-minute lifetime. |
| AERIAL (STRIKE) | 100e | Produced at Beacon. 2-minute lifetime. |
| VIRUS | 100e | Produced at Nest. 2-minute health-based lifetime. |
| Avatar respawn | Free | 8s timer, no energy cost. |

---

### Production Rates (Brisk)

| Production Building | Rate | Steady-state cap (at max prod) |
|--------------------|------|-------------------------------|
| MCP | 1 Zoomba per 2s | Limited by zoomba cap (tile count). |
| Garage | 1 TANK per 6s | Limited by available free Zoombas. |
| Beacon | 1 AERIAL per 4s | ~30 units at steady state (120s ÷ 4s). |
| Nest | 1 VIRUS per 5s | ~24 units at steady state (120s ÷ 5s). |

---

### Economy Tension

At one fully-placed Generator's output (54e/sec), running all production at max is not sustainable:

| Activity | Drain | % of 54e/sec |
|----------|-------|--------------|
| Max Zoomba production (1 per 2s × 25e) | 12.5e/sec | 23% |
| Max TANK production (1 per 6s × 150e) | 25e/sec | 46% |
| Max AERIAL production (1 per 4s × 100e) | 25e/sec | 46% |
| Max VIRUS production (1 per 5s × 100e) | 20e/sec | 37% |
| All of the above simultaneously | 82.5e/sec | 153% |

You cannot run everything from one Generator. With two Generators (~80-110e/sec), a full military becomes sustainable while leaving room for expansion. With three or more, you enter late-game territory — mass production, decisive pushes, and VIRUS/Generator theft become critical.

---

### Non-Monetary Costs

| Action | Cost | Rationale |
|--------|------|-----------|
| Terrain raise/lower | **Zoomba time only** (10-15s per tile) | Rate-limited by zoomba labor and a concurrent job cap of 3 per player. No energy cost — prevents rich-get-richer on map control. |
| Building repair | **Free** (one Zoomba visit) | Damaged buildings auto-queue a fix-me job. 50 HP/s per Zoomba assigned to repair. No additional energy cost. |
| TANK self-repair | **Free** (internal pilot) | Repairs automatically when out of combat. No energy cost. |
| Zoomba self-heal | **Free** (slow regen) | Heals over time when not in scram mode. |

---

### Catch-Up Mechanics (explicit, visible to all players)

**Underdog Grit:** Zoombas belonging to the player with the fewest tiles work faster. +3% speed per 10% tile deficit relative to the leader, capped at +30%. This speeds up terrain work and building construction without directly buffing combat.

**Desperation Meter:** The MCP gains a stacking energy bonus for each consecutive minute a player has fewer tiles than the leader. +5e/sec per minute behind, stacking, capped at +30e/sec. Resets when the player claims the lead or ties for the lead. Also grants +3% damage to offensive units (STRIKE, VIRUS) per stack, capped at +18%. This ensures the behind player's military can punch through a turtle.

