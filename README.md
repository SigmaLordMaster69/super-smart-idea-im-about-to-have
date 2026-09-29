# Infinite Scenic Road (Roblox)

A [slowroads.io](https://slowroads.io)-style endless driving game for Roblox. One road goes on forever, and the world around it is generated as you drive:

- **Mountains** with snowy peaks, rock cuts and **tunnels** through the ridges
- **Coastal cliff roads** above the ocean, with beaches, coves, sea stacks, headland tunnels and bridges over river mouths
- **Canyons**: tiered red-rock walls with rock strata, mesas and buttes, a river along the canyon floor, and big **bridges** over gorges
- **Lakes** with sandy shores and islands, beside a flat lakeside road
- **Rivers**: river valleys where the river winds beside the road and crosses under it, plus rivers that cross the road at an angle
- **Forests** (some sections in autumn colours) and **meadows** with flowers
- **Trees and plants** matched to each region: pines, snowy pines, oaks, birches, wind-swept coastal cypresses, cacti, bushes, dry shrubs, flowers and rocks
- **Road furniture**: guard rails wherever the road drops away or runs along water, bridge parapets, lit tunnels with portals, delineator posts, and signs (curve warnings, chevrons around sharp bends, tunnel ahead, speed limits, falling rocks, deer crossings, km markers, and green "Entering ..." signs for every region)

On top of that:

- **Four seasons**: spring blossom and drifting petals, green summer, autumn leaves falling from orange trees, and a snowy winter with bare trees, frozen lakes and rivers, and lower grip
- **Weather**: clear, cloudy, rain, storm (lightning bolts, screen flash, delayed thunder), fog and snow. It blends smoothly, and in Auto mode it changes every few minutes with odds that suit the season
- **Wet roads**: asphalt darkens and turns reflective in the rain, tyres throw up spray, grip drops, and the road dries out afterwards
- **Sky**: dynamic clouds, sun rays, and colour grading that turns warm at sunrise and sunset and cool at night
- **Car or motorcycle**: the bike leans into corners, and its rider is your own avatar
- **Settings menu** (gear button): vehicle, season, weather, time of day, quality, camera

It also includes a slowroads-style **autodrive**, chase, hood and **cinematic roadside** cameras, a day/night cycle, and a "km driven" leaderboard.

| Coast: cliffs, beach, sea stacks, a headland tunnel (red) and river bridges (yellow) | Canyon, then coast | River valley: the river crosses under the road on bridges |
|---|---|---|
| ![coast](docs/map-coast.png) | ![canyon](docs/map-canyon-coast.png) | ![river valley](docs/map-river-valley.png) |

| Canyon floor with river | Lakeside road | Tunnel portal |
|---|---|---|
| ![canyon](docs/preview-canyon.png) | ![lake](docs/preview-lake.png) | ![tunnel](docs/preview-tunnel.png) |

> These images are **not in-game screenshots**. They come from the offline tools in `tools/`, which run the real generator code and draw its output with a simple software renderer. Roblox will look better: real lighting, water, smooth terrain and actual 3D trees.

---

## Getting started

### Option A: open the place file
1. Open **`InfiniteScenicRoad.rbxl`** in Roblox Studio.
2. Press **Play**.

The place is already set up (streaming off, Future lighting, spawn platform).

### Option B: Rojo
```bash
rojo build default.project.json -o InfiniteScenicRoad.rbxl   # build a place file
# or, for live syncing into Studio:
rojo serve
```

### Updating a place you already have open
- **Nothing changed in Studio yet?** Close it and open the new `InfiniteScenicRoad.rbxl`.
- **Made changes you want to keep?** Run `rojo serve` and connect the Rojo plugin: the scripts sync into your open place and your own models stay put.

### Required place settings
If you copy the scripts into your own place instead:
- **Workspace.StreamingEnabled = false.** The world is generated on each client, and streaming would delete that client-made terrain.
- Lighting.Technology = Future (recommended).
- Put `src/shared` in ReplicatedStorage as a folder named `InfiniteRoad`, `src/client` in StarterPlayerScripts as a LocalScript, and `src/server` in ServerScriptService as a Script (see `default.project.json`).

## Controls

| | Keyboard | Gamepad | Touch |
|---|---|---|---|
| Drive / brake / reverse | W / S (or arrows) | RT / LT | GAS / BRAKE |
| Steer | A / D (or arrows) | Left stick | ◀ ▶ |
| Handbrake | Space | A | |
| Autodrive | F | X | AUTO |
| Camera (chase, hood, cinematic) | C | Y | CAM |
| Look around | Right-drag, wheel to zoom | Right stick | |
| Put the car back on the road | R | B | RESET |
| Time of day | T | D-pad up | |
| Hide HUD | H | D-pad down | |
| Car / motorcycle | V | D-pad left | menu |
| Season (Auto, Spring, Summer, Autumn, Winter) | N | | menu |
| Weather (Auto, Clear, Cloudy, Rain, Storm, Fog, Snow) | G | D-pad right | menu |
| Settings menu | M or the ⚙ button | Select | ⚙ |
| Stats overlay (FPS, chunks, workers, frame budget) | F3 | | |

Pressing any drive key turns autodrive off. A car that flips or ends up in the water is put back on the road automatically.

---

## Using asset packs (premade models)

Everything the game builds from parts can be replaced by premade models from the Toolbox or Creator Store. There's no code to edit:

1. In Studio, open **ReplicatedStorage → InfiniteRoadAssets**. It has one folder per slot, and a `README` script inside explains each one.
2. Insert an asset pack from the Toolbox, then drag the individual models into the matching slot folder:

   | Slot | What to put in it | Toolbox search ideas |
   |---|---|---|
   | `Trees/Pine`, `SnowPine`, `Oak`, `OakAutumn`, `Birch`, `BirchAutumn`, `Cypress`, `Cactus` | tree models (several per folder = random variants) | "low poly tree pack", "pine tree", "stylized nature pack" |
   | `Plants/Bush`, `DryBush`, `Flowers` | small plants | "bush pack", "flower patch" |
   | `Rocks` | boulders | "rock pack", "low poly rocks" |
   | `Signs/CurveLeft`, `CurveRight`, `ChevronLeft`, `ChevronRight`, `Tunnel`, `SpeedLimit`, `FallingRocks`, `Deer`, `Guide`, `Marker` | road sign models (front facing -Z) | "road sign pack", "traffic signs" |
   | `Road/GuardRail` | one straight guard rail segment, repeated along every rail | "guard rail", "highway barrier" |
   | `Road/Delineator`, `Road/RoadEnd` | roadside post, barrier | "road post", "road barrier" |
   | `Car/Body` | any car model, nose towards -Z | "car model", "low poly car" |
   | `Motorcycle/Body` | any motorbike model, front towards -Z | "motorcycle", "motorbike" |

3. Press Play. The Output window prints which slots were picked up.

Each model is **cleaned** before use: scripts, sounds, seats, humanoids, welds and constraints are removed, so scripts inside free models never run. It is then anchored, pivoted at its base, and auto-scaled (trees 18–48 studs, plants, rocks; signs only if way off).

A car body is scaled to 15 studs and welded onto the physics chassis. Parts named *wheel/tire/tyre/rim* are found and attached to the suspension, so they spin and steer, and the collision box resizes to fit the body. A motorcycle body is scaled to 8 studs. Its front and rear wheel parts spin (the front one also steers), the whole bike leans, and the rider stays on top.

Empty slots keep the built-in version. You can tweak individual models with attributes, set on the model or on its slot folder:

| Attribute | Type | Use |
|---|---|---|
| `KeepSize` | bool | keep the model's own size |
| `Scale` | number | extra scale factor |
| `YawOffset` | number | degrees to turn it (fix a sign facing backwards, or a car driving sideways) |
| `HeightOffset` | number | raise (+) or sink (-) it, e.g. -1 to bury roots |
| `Collide` | bool | whether the car hits it |

Terrain textures come from Roblox materials, so a `MaterialVariant` pack in **MaterialService** (e.g. realistic grass, rock or sand) restyles the whole world too.

**Sounds:** paste audio ids from the Toolbox into `Config.Sounds`:
- `Engine`, `MotorcycleEngine`: the pitch follows your speed.
- `Wind`: the volume follows your speed.
- `Rain`: the volume follows the rain, and it is muffled in tunnels.
- `Thunder`: plays after each lightning strike, delayed by its distance.
- `Ambience`: background loop.

**Particle textures:** rain, snow and leaves use built-in engine textures. Paste your own image ids into `Config.Textures` for nicer raindrops or leaf shapes.

---

## How it works

### One world per player
Every client generates its own copy of the world from a **shared seed** that the server picks, so everyone on a server drives the same road. The server does almost nothing (it picks the seed and runs the leaderboard). This keeps terrain replication off the network and lets each client move its own floating origin. Other players' avatars are hidden, because they are driving in their own copy of the world.

### The road (`src/shared/RoadPath.luau`)
- The road is stored as samples every 4 studs. The heading comes from layered noise and is limited to a minimum turn radius.
- The heading always stays within ±74° of +X. That guarantees the road never crosses itself, and that samples are sorted by X, so finding the nearest point on the road is a quick binary search followed by a small scan.
- Elevation starts from a target (terrain height, or a region-specific level such as cliff shelf height or lake level). That target is gaussian-smoothed and capped at a 7.5% grade. Because the road is smoothed while the ground is not, ridges come out higher than the road (tunnels) and valleys lower (bridges).
- Along the finished road, a streaming run detector turns raw measurements into clean runs, with a minimum length, merged small gaps and padded ends:
  - **tunnel** where there is more than 34 studs of rock above the road,
  - **bridge** where the road is more than 20 studs above the ground or crosses water,
  - **guard rail** where the ground next to the road drops away or there is water close by.

### Regions and landforms (`Sections.luau`, `TerrainSampler.luau`)
- The road is divided into **sections** (Meadow, Forest, Mountains, Coast, Canyon, Lake, RiverValley), each 2–6k studs long, which cross-fade over 900 studs. They are generated lazily from the seed, and each one gets a name ("Redrock Canyon", "Lake Serene", ...).
- Each region has its own height function, defined relative to the road (distance to the side `d`, arc length `s`). Mountain relief is damped close to the road, so the road runs along valleys with the peaks beside it.
- **Crossings** are landforms laid across the road at an angle: *ridges* force tunnels, and *rivers* and *gorges* force bridges.
- Then the road corridor is applied: cuts and embankments with slopes that suit the material, tunnel voids with an arched profile (plus cut-and-cover where the rock is thin), and natural ground left under bridges.

### Streaming and performance (`ChunkManager.luau`, `WorkerPool.luau`, `GenWorker/`)
- The world is built in 128×128-stud chunks around a point just ahead of the car. Each chunk gets voxel terrain, road parts and decoration. Chunks ahead of the car are loaded before those beside and behind it.
- **Parallel terrain:** sampling the height model is the expensive part. It runs on 2–4 `GenWorker` Actors (Parallel Luau), so it uses other CPU cores. Each worker samples in short parallel slices, then writes its voxels in the serial phase. If the workers fail to start, time out or keep erroring, the game quietly falls back to building on the main thread.
- The rest of the work runs in one coroutine with an **adaptive frame budget**. The budget shrinks when the frame rate drops below about 50 FPS and grows while there is work queued and the game runs smoothly, so generation never causes a big frame spike.
- Terrain is sampled on nested 16/8/4-stud lattices aligned to the world grid. Columns far from the road are interpolated, while columns near the road are sampled exactly. Voxels are written in four small quadrant pieces per chunk, reusing row tables to save memory churn. The hot modules are compiled with `--!native`. Together, a chunk now takes about 40% less time to build than before.
- Trees switch between a one-part far version and a full near version, with a little hysteresis so chunks on the boundary don't flip back and forth. Placement is seeded per cell, so nothing moves when a chunk changes detail.
- **Quality presets** (`Low`, `Medium`, `High`, `Ultra`, or `Auto`) set the view distance, tree density, tree shadows, the number of workers and the frame budget limits. Auto picks `Low` on touch devices, and otherwise follows the Roblox graphics quality slider.
- **Floating origin:** once the car is 16k studs from the Roblox origin, the world is recentred. Terrain is copied to its new place over a few frames (out of sight), then every part, the car and the camera shift in a single frame. That keeps physics precise however far you drive.

### Weather and seasons (`Weather.luau`, `Seasons.luau`, `Environment.luau`)
- `Weather` blends the clouds, atmosphere, brightness, sun rays and colour grading between presets, then grades the result by time of day. Rain and snow come from an emitter that follows the camera and switches off under a roof (tunnels, bridge undersides). Storms throw lightning bolts made of neon segments, with a flash and thunder delayed by distance.
- Road wetness builds up during rain and dries out slowly afterwards. Asphalt parts (tagged `IR_Asphalt`) are recoloured in batches of 500 per frame, so a change of weather never hitches.
- `Seasons` sets the terrain colours and flags for the terrain builder (snow on flat ground, frozen water above sea level, a lower snow line), plus tree styles and grip. When the season changes, the loaded chunks are rebuilt in the background, nearest first, and the decoration is redone.
- `Environment` runs the Auto modes. By default the seasons roll every 10 minutes, and the weather changes every 2–4 minutes, weighted by the season. Rain turns to snow in winter.

### The car (`Car.luau`, `Motorcycle.luau`)
A raycast-suspension car. Each wheel casts a ray, and a spring/damper plus tyre friction are applied through a VectorForce. Grip is limited by a friction circle, steering lock shrinks with speed, the handbrake lets the rear slide, the car holds itself on hills when stopped, and there are headlights (at night) and brake lights. Autodrive steers with pure pursuit and slows for bends ahead based on their curvature.

The motorcycle uses the same physics with a narrow footprint and its own tuning (`Config.Motorcycle`). Its four ray corners act like invisible outriggers, so it can't fall over. What you see hangs off a "lean root" that tilts into corners by `atan(speed × yaw rate / g)` around the tyre contact line. The rider is a posed clone of your R15 avatar, or a helmeted blocky rider if that isn't possible. Tyre grip follows the season and the road wetness.

### Project layout
```
src/shared/     ReplicatedStorage.InfiniteRoad (pure Luau, no DataModel access)
  Config.luau          every tunable
  Noise.luau           seeded Perlin / fbm / ridged noise (math.noise)
  Sections.luau        regions, names, crossings
  RoadPath.luau        the infinite road: path, elevation, tunnels/bridges/rails, projection
  TerrainSampler.luau  height model per column
  World.luau           wires the above together for one seed
src/client/     StarterPlayerScripts.InfiniteRoadClient
  init.client.luau     entry point
  ChunkManager.luau    streaming + floating origin
  TerrainBuilder.luau  voxels + materials per chunk
  RoadBuilder.luau     road, markings, rails, bridges, tunnels, signs
  Decorator.luau       vegetation placement
  Props.luau           procedural trees, rocks, signs (no assets needed)
  WorkerPool.luau      dispatches terrain jobs to the GenWorker actors
  GenWorker/           Actor + Worker script (parallel terrain sampling)
  Weather.luau, Seasons.luau, Environment.luau   weather, seasons, auto modes
  Car.luau, Motorcycle.luau, AutoDrive.luau, CameraController.luau
  Input.luau, Hud.luau, SettingsMenu.luau, Quality.luau, Atmosphere.luau
  AssetLibrary.luau    premade model slots (asset packs)
src/server/     ServerScriptService.InfiniteRoadServer (seed + leaderboard)
assets/         README shown inside ReplicatedStorage.InfiniteRoadAssets
tools/          offline tests and preview renderers (Lune + Python)
```

## Tuning

Everything lives in `src/shared/Config.luau`. The most useful settings:

| Setting | What it does |
|---|---|
| `Seed` | 0 = random per server. Set a number to always get the same road. |
| `Road.MinRadius`, `Regions.*.Twist` | how curvy the road is |
| `Road.MaxGrade`, `Road.ElevationSmoothing` | how hilly the road is; less smoothing means fewer tunnels and bridges |
| `Tunnel.CoverThreshold`, `Bridge.GapThreshold` | when a cut becomes a tunnel, and when an embankment becomes a bridge |
| `Regions.*.Weight` / `Length` | how often each region appears and how long it lasts |
| `Decor.Density` | trees per region |
| `Quality.Default` and the presets | `Auto` or a preset name. Each preset sets view distance, tree density and shadows, parallel workers (0 turns them off) and the frame budget range |
| `Car.*`, `Motorcycle.*` | top speed, acceleration, grip, suspension; `Motorcycle.LeanMax` caps the lean angle |
| `Weather.Start`, `Seasons.Start` | `Auto`, or lock one weather / season |
| `Weather.MinDuration`/`MaxDuration`, `Seasons.CycleMinutes` | how often the weather and the season change in Auto mode |
| `Sky.DayLengthMinutes` | 0 freezes time |

## Offline tests

The generator and the chunk builders are tested outside Roblox with [Lune](https://github.com/lune-org/lune), which provides Luau, Luau's own `math.noise`, and Roblox's real class and property definitions. Invalid property names or types fail the tests.

```bash
lune run tools/check_syntax                 # every source file compiles; the place file has the right hierarchy and settings
lune run tools/test_road [seed] [studs]     # road invariants: monotonic X, min radius, max grade, flags, determinism, projection
lune run tools/test_chunks [seed]           # full chunk pipeline: voxels, road, tunnels, bridges, decoration, rebase
lune run tools/test_assets                  # fake asset packs: cleaning, scaling, placement, guard rails, car + bike bodies and wheels
lune run tools/test_scenic [seed]           # seasons (snow, ice, tree styles), weather/environment, motorcycle, parallel worker path
lune run tools/bench                        # terrain build time per chunk
lune run tools/curve_stats [seed]           # curve radius distribution
lune run tools/list_sections [seed]         # region sequence

# pictures (needs python3 with numpy + pillow)
lune run tools/render_map 12345 0 12000 1400 10 map.bin && python3 tools/render_map.py map.bin map.png
lune run tools/render_view 12345 3000 view.bin && python3 tools/render_view.py view.bin view.png
```

## Limitations and notes
- **Not yet playtested in Roblox Studio.** The generator, chunk building and every instance/property it creates run in the offline tests above. Things only the engine can show still need a playtest: how the car and bike handle, camera feel, lighting and weather looks, how smooth terrain meshes the voxels, and frame rate on real devices. The numbers in `Config.Car` and `Config.Motorcycle` will probably need tuning.
- The parallel workers can't run outside Roblox. The offline tests cover the same path with a fake worker pool that answers asynchronously. If the Actors don't work in your place, the Output window says so and generation continues on the main thread.
- The sound ids in `Config.Sounds` are empty by default (silence). Add your own from the Toolbox.
- Players on the same server share a seed but don't see each other, because each world is local to its player.
- The road starts at a "ROAD ENDS" barrier behind the spawn point. It's infinite forwards only.
- Generation runs on the client. On weak devices, pick the `Low` quality preset (the menu, or `Config.Quality.Default`).
