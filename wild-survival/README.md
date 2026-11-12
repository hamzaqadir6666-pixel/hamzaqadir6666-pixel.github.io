# Wild Survival

A third-person 3D wildlife survival game for **Godot 4.7** (GDScript, Forward+ renderer).
You are a deer in a 1 km² procedurally laid-out jungle. Eat, drink, stay hidden and stay alive while
lions, tigers, cheetahs and hyenas hunt you through a full day / night cycle.

## Running the game

1. Install **Godot 4.7.x** (standard build, not .NET) from <https://godotengine.org/download>.
2. In the Project Manager choose **Import**, select `wild-survival/project.godot`, and open it.
   The first open imports all models, textures and audio (about a minute or two).
3. Press **F5** (Run Project). The main scene is `res://scenes/main.tscn`.

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

## Project layout

```
wild-survival/
  project.godot
  scenes/         main, world, player, predators/*, ui/*, tests/*
  scripts/
    autoload/     settings.gd, game_state.gd, audio_manager.gd
    player/       player.gd, third_person_camera.gd, animal_rig.gd, player_effects.gd
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

## Automated tests

`scenes/tests/test_runner.tscn` runs the real game headless and drives it with simulated input
(169 checks: world generation, menus, movement, collisions, survival stats, stealth, each predator's
behaviour, escape / search / return, day-night, audio, pause, settings, death and restart):

```
godot --headless --import
godot --headless --fixed-fps 60 res://scenes/tests/test_runner.tscn
WS_SOAK=20 godot --headless --fixed-fps 60 res://scenes/tests/test_runner.tscn   # 20 min bot soak
```

### What was and was not verified

This project was developed in a sandbox with no GPU or display. Godot 4.7.2 was compiled from source
there and used headless, so:

- **Verified**: every asset imports; all scripts compile; all shaders compile; the test suite above
  passes (169/169); a 20-minute unscripted soak run produced no script errors.
- **Not verified**: anything that needs eyes or ears. The game has never been rendered to a screen,
  so lighting, fog, colour balance, material look, animation quality, particle appearance, UI layout
  and audio mix are untested and will likely need tuning. The synthesised sounds (see CREDITS.md) have
  not been listened to. Frame rate on real hardware is unmeasured.

## License

Code: MIT. Assets: see `CREDITS.md` — most art and audio is CC BY-SA 3.0 (Wildfire Games, 0 A.D.), which
requires attribution and that derived assets stay under the same license.
