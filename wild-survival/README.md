# Wild Survival

A third-person 3D wildlife survival game for **Godot 4.7** (GDScript, Forward+ renderer).
You are a deer in a 1 km² procedurally laid-out jungle. Eat, drink, stay hidden and stay alive while
lions, tigers, cheetahs and hyenas hunt you through a full day / night cycle.

## Running the game

1. Install **Godot 4.7.x** (standard build, not .NET) from <https://godotengine.org/download>.
2. In the Project Manager choose **Import**, select `wild-survival/project.godot`, and open it.
   The first open imports all models, textures and audio (about a minute or two).
3. Press **F5** (Run Project). The main scene is `res://scenes/main.tscn`.

The game opens in a normal **resizable window** (title bar, minimise / maximise / close, drag to move,
drag the edges to resize). **F11** or **Alt+Enter** switches to fullscreen and back, and
Settings > Graphics > *Window* offers Window / Maximised window / Fullscreen.

World generation takes a few seconds at start-up (loading bar), after which the main menu appears
over the live jungle.

## Controls (rebindable in Settings > Controls)

| Action | Default |
|---|---|
| Move | W A S D |
| Sprint (drains stamina, loud) | Shift |
| Sneak (slow, quiet, harder to see) | Ctrl |
| Jump | Space |
| Eat / graze / drink (hold) | E |
| Look | Mouse |
| Camera zoom | Mouse wheel |
| Pause | Esc |

### Touch controls (Android / iOS)

On a phone or tablet the on-screen controls appear automatically:

| Control | Where | How |
|---|---|---|
| Move | left side | touch and drag: the stick appears under your thumb |
| Look | anywhere else | drag |
| Zoom | anywhere else | pinch with two fingers |
| RUN | bottom right | tap to toggle; ends when you let go of the stick |
| SNEAK | bottom right | tap to toggle |
| JUMP | bottom right | tap |
| EAT | bottom right | hold near food, grass or water |
| Pause | top right | tap (the Android back button also pauses) |

Several fingers work at once (move, look and a button together). On a PC you can try them with
Settings > Controls > Touch controls > On; the mouse then acts as one finger.

### Exporting to Android

1. In Godot: Editor > Manage Export Templates > Download and Install.
2. Install Android Studio (for the Android SDK) and a JDK 17, then set their paths in
   Editor Settings > Export > Android. Godot's "Exporting for Android" guide has the details.
3. Project > Export > Add > Android. Keep the default settings (the project already enables
   ETC2/ASTC textures and landscape orientation), then Export Project to get an `.apk`.

The game starts on the Low graphics preset on phones. It is a heavy scene (dense vegetation,
long view distance), so expect it to need a recent mid-range or better phone.

## How to survive

- **Health** regenerates slowly while you are fed and watered, faster inside a safe thicket.
- **Stamina** drains while sprinting or swimming. At zero you are exhausted and slow until it recovers.
- **Food**: hold E at berry bushes, flowering shrubs and leafy plants (they deplete and regrow), or
  graze slowly on open grass (grazing only fills you to 80%).
- **Water**: hold E at the edge of the river or a lake.
- **Stealth**: bushes hide you. Standing still or sneaking in cover makes you nearly invisible;
  trotting is easier to spot and sprinting is both visible and loud. The HUD shows whether you are
  hidden, how aware the nearest predator is, and the current threat level.
- **Safe thickets**: six groves are too dense for predators to enter.
- **Discoveries**: salt licks (+max stamina, heal), elder trees (+max health, faster recovery),
  orchards and lakes.
- **Night** is darker, predators see and hear better, move faster, rest less, and an extra hyena
  pack comes down from the hills until morning. Cheetahs are the exception: they are day hunters.

### The predators

| | Behaviour | How to beat it |
|---|---|---|
| **Lion** | Patrols a fixed circuit in its territory, sleeps much of the day. Roars, then charges at 11.7 m/s. | It tires after ~8 s and will not leave its territory. A fresh deer that runs at the roar gets away. |
| **Tiger** | Lies up in a bush near trails and water. Creeps toward you from behind, freezes when you look at it, pounces from ~11 m (15 m/s burst, heavy damage). Swims. | Keep facing it and keep your distance; a failed pounce is abandoned within seconds. |
| **Cheetah** | Hunts by sight in the clearings. Accelerates to 18.5 m/s. | Turns badly at speed, loses half its speed in dense forest, burns out in ~6 s and then lies panting, harmless. |
| **Hyena** | Roams the whole map in packs, calls pack mates in, and keeps switching tactics: shadow, circle, feint, harass, back off. Bolder when you are weak, tired or it is dark. | Not very fast (9.9 m/s) but tireless. Break line of sight, hide, reach a thicket, or swim — they cannot. |

All predators share one perception model: a vision cone with range scaled by how visible you are,
physics line-of-sight checks against terrain, trunks and rocks, hearing based on how much noise you
make, and an awareness meter that has to fill before they commit. After losing you they search around
your last known position and then return to their patrol.

### The other prey

Herds of **gazelle** graze around the clearings and **boar** root about in the forest. They bolt
from predators (and from a deer that blunders into them), and an idle lion, tiger, cheetah or hyena
that spots one will hunt it. A predator that makes a kill stays to feed for a while and is far less
watchful - a good moment to slip past. A herd suddenly running is a warning that something is near.
Killed animals are replaced elsewhere in the jungle after a while.

## Campaign, rare plants and weather

- **Levels.** *Play* runs an eight-level campaign. Each level asks you to survive a set time and to
  eat a number of rare plants; later levels bring more, faster and harder-hitting hunters, dusk and
  night starts, drought and storms. Levels 7 (*Blood Moon*) and 8 (*Apex*) are meant to be extremely
  hard. *Choose Level* replays any level reached; *Endless Survival* is the original open-ended run.
  The table is `GameState.LEVELS`.
- **Random start.** The deer begins every game somewhere different (dry, open, level ground with no
  hunter nearby).
- **Slow start, speed from food.** A new deer runs at 80 % speed. Every *Swift Clover* adds 3.5 %
  for good, up to about 125 %.
- **Rare glowing plants** (scattered afresh each game, many hidden in cover; walk up and press E):
  Swift Clover (speed), Moonpetal (**night vision**), Ironbark Root (max health), Sunberry (max
  stamina), Ghost Fern (silent steps), Owl-eye Mushroom (sense the nearest hunter), Spring Lily (higher
  jump), Lotus Root (fast, tireless swimming), Healing Herb, Wild Honeycomb - and the poisonous Red
  Toadstool. Gifts are kept from level to level and saved in `user://records.cfg`.
- **Weather.** Clear, overcast, rain and storm come and go: rain streaks and splashes, a darker sky,
  thicker air, a rain loop, thunder and lightning. Rain cuts every hunter's sight and hearing by up to
  a third and slowly quenches thirst.
- **More wildlife.** Wolves (tireless pack, from level 3) and crocodiles (ambush at the water's
  edge) join lion, tiger, cheetah and hyena. Gazelle, boar, goats, buffalo, foxes and junglefowl
  graze the map; hawks soar over the clearings and crows gather above a fresh kill. The HUD counts the
  species you have actually seen (*Wildlife seen n / 14*).
- **HUD.** Health, stamina, food and water are shown with heart, bolt, leaf and droplet icons; a row
  of ability icons lights up as gifts are found; the level goal, weather and clock sit top-left.

## Project layout

```
wild-survival/
  project.godot
  scenes/         main, world, player, predators/*, ui/*, tests/*
  scripts/
    autoload/     settings.gd, game_state.gd, audio_manager.gd
    player/       player.gd, third_person_camera.gd, animal_rig.gd, player_effects.gd
    prey/         prey.gd (gazelle, boar: graze, wander, flee, die), prey_manager.gd (herds)
    predators/    predator.gd (shared brain), lion.gd, tiger.gd, cheetah.gd, hyena.gd, predator_manager.gd
    world/        world.gd, world_data.gd, terrain.gd, vegetation.gd, grass_streamer.gd,
                  flora_library.gd, day_night.gd, ambience.gd, world_effects.gd
    ui/           hud.gd, menus.gd, settings_menu.gd, ui_theme.gd
    tools/        test_runner.gd, bake_resources.gd
  shaders/        terrain, foliage (wind), water, sky, birds, vignette
  models/         animals/*.glb, environment/<category>/*.glb
  textures/       terrain, water, particles
  materials/      terrain_material.tres, water_material.tres
  environments/   jungle_environment.tres
  animations/     anim_meta.json (clip list; the clips themselves are embedded in the animal GLBs)
  audio/          ambience, animals, deer, music, ui
  ui/             wilderness_theme.tres
  resources/      flora_manifest.json
  CREDITS.md
```

## Performance notes

- Vegetation is drawn with per-chunk `MultiMesh` instances with visibility ranges (trees 270 m,
  bushes 135 m, undergrowth 75 m), scaled by the *Vegetation distance* setting. Roughly 8,600 trees,
  12,000 bushes and 23,000 undergrowth plants are placed.
- Grass is streamed around the player in 24 m cells whose `MultiMeshInstance3D`s are pooled and reused.
- Terrain uses two shared plane meshes (near / far LOD) displaced in the vertex shader from one height
  texture, a `HeightMapShape3D` for collision and a coarse `ArrayOccluder3D` for occlusion culling.
- Trunk and rock colliders live in one static physics-server body per 64 m chunk (no nodes).
- Predators think at 4–7 Hz (staggered), and predators further than 170 m from the deer are simulated
  without physics or animation.
- One-shot sounds go through pooled 2D / 3D players.
- Settings > Graphics has Low / Medium / High / Ultra presets plus individual toggles.
- **Low-end PCs.** On first launch the preset is chosen from the graphics adapter and core count
  (integrated graphics start on Low or Medium). *Low* renders 3D at 65 % resolution with FSR
  upscaling, a 1024 px two-split shadow map, no SSAO, no volumetric fog, no animal shadows, 30 % grass,
  55 % vegetation distance and a quarter of the rain particles. *Auto performance* (on by default)
  watches the frame rate in game and, below about 27 fps, lowers render scale and then the preset.
  The UI is always drawn at full resolution.

## Automated tests

`scenes/tests/test_runner.tscn` runs the real game headless and drives it with simulated input
(351 checks: world generation, menus, movement, collisions, survival stats, stealth, each predator's
behaviour, escape / search / return, touch controls, day-night, audio, pause, settings, death and restart,
levels, random spawn, rare plants and abilities, night vision, weather, birds, new hunters, window settings):

```
godot --headless --import
godot --headless --fixed-fps 60 res://scenes/tests/test_runner.tscn
WS_SOAK=20 godot --headless --fixed-fps 60 res://scenes/tests/test_runner.tscn   # 20 min bot soak
```

### What was and was not verified

This project was developed in a sandbox with no GPU or display. Godot 4.7.2 was compiled from source
there and used headless, so:

- **Verified**: every asset imports; all scripts compile; all shaders compile; the test suite above
  passes (351/351); 8-minute unscripted soak runs of campaign level 3 produced no script errors.
- **Not verified on a device**: the Android export and the touch controls on a real touchscreen
  (they are tested with simulated touch events only).
- **Not verified**: anything that needs eyes or ears. The game has never been rendered to a screen,
  so lighting, fog, colour balance, material look, animation quality, particle appearance, UI layout
  and audio mix are untested and will likely need tuning. The synthesised sounds (see CREDITS.md) have
  not been listened to. Frame rate on real hardware is unmeasured.

## License

Code: MIT. Assets: see `CREDITS.md` — most art and audio is CC BY-SA 3.0 (Wildfire Games, 0 A.D.), which
requires attribution and that derived assets stay under the same license.

### Notes on the expansion (levels, weather, new animals)

- The new animals (wolf, crocodile, goat, buffalo, fox, junglefowl, hawk, crow) come from the same
  0 A.D. set as the gazelle and boar and only have Idle and Walk (or flight) clips. Their run is the
  walk cycle played faster, and wolf / crocodile attacks are a procedural lunge rather than a
  dedicated attack animation. The lion, tiger, cheetah and hyena models are unchanged.
- Rain, lightning, night vision brightness, the HUD icons and the window behaviour have been checked
  by the headless tests only (values, state, layout) - never looked at on a screen.
