# Credits and licenses

## 0 A.D. — Wildfire Games (CC BY-SA 3.0)

Art and audio from **0 A.D.** © Wildfire Games — <http://www.wildfiregames.com/> —
licensed under Creative Commons Attribution-ShareAlike 3.0: <http://creativecommons.org/licenses/by-sa/3.0/>
Source: <https://github.com/0ad/0ad> (`binaries/data/mods/public/art` and `.../audio`).
Some 0 A.D. textures derive from CGTextures images, distributed under CC BY-SA by special permission
granted to Wildfire Games.

Used and **modified** for this project (the modified files are likewise released under CC BY-SA 3.0):

- `models/animals/deer.glb`, `lion.glb`, `tiger.glb`, `cheetah.glb` — meshes, skeletons, textures and
  animation clips converted from COLLADA to glTF, rescaled, subdivided, clips merged into one file.
  The lion and cheetah "Attack" clip and the deer "Jump" clip were derived from existing clips.
- `models/environment/**` — trees, palms, bushes, plants, grass, water plants, rocks, cliffs and logs,
  converted from 0 A.D. actors to static glTF.
- `textures/terrain/*`, `textures/water/*`, `textures/particles/*` — resized / converted.
- `audio/music/*` — menu (*Mirage*), day (*Mountain Idyll*), night (*Harvest Moon*), chase (*Taiko 1*),
  game over (*Dried Tears*).
- `audio/ambience/*` except the two files listed under "Original" below.
- `audio/animals/lion_*` — original recordings.
- `audio/animals/tiger_*`, `cheetah_attack*`, `cheetah_growl`, `hyena_attack*`, `hyena_growl` —
  **derived** from the 0 A.D. lion recordings by pitch shifting and filtering. They are stand-ins, not
  recordings of those species.
- `audio/deer/step_*` — 0 A.D. footstep recordings. `audio/deer/eat`, `drink`, `splash`, `hurt*`,
  `death`, `land`, `bush_rustle*` — **derived** from 0 A.D. footstep, river, animal and foliage
  recordings (cut, pitch shifted, filtered, layered).

## Hyena

- **"Spotted hyena"** by Poly by Google — CC BY 3.0 — <https://poly.pizza/m/0yU1LU3Nkpu>
- Rigged onto the **Quaternius** "Ultimate Animated Animals" wolf skeleton and animations (CC0),
  as prepared in <https://github.com/g0ddest/renethack>.
- File: `models/animals/hyena.glb`.

## Original (generated for this project)

Synthesised procedurally, no source recordings: `audio/ambience/night_crickets.ogg`,
`audio/ambience/owl_hoot.ogg`, `audio/animals/hyena_whoop.ogg`, `audio/animals/hyena_giggle.ogg`,
`audio/animals/cheetah_chirp.ogg`, `audio/deer/breath_pant.ogg`, `audio/deer/breath_calm.ogg`,
`audio/deer/snort.ogg`, and everything in `audio/ui/` (click, hover, heartbeat, alert sting, discover).
The hyena whoop and giggle layer a synthesised voice with filtered noise from a 0 A.D. lion recording,
so those two files are also CC BY-SA 3.0.

Code, shaders, UI, sky and the bird-flock silhouettes are original.

## Engine

Godot Engine — MIT — <https://godotengine.org>
