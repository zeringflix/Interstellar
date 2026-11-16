# Install RAGDOLL CRASH PHYSICS into Roblox Studio (for Claude desktop)

Repo: `zeringflix/Interstellar`, branch `claude/ragdoll-crash-physics-research-j5nvbr`, folder `ragdoll-crash-physics/`.

## Download links
(The repo may be private: if a link returns 404, open it while signed in to GitHub, or use `git clone --branch claude/ragdoll-crash-physics-research-j5nvbr https://github.com/zeringflix/Interstellar`.)

| File | Link |
|---|---|
| Studio place (all scripts, UI, audio, map) | https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/RagdollCrashPhysics.rbxlx |
| All 17 vehicle models in one file | https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/blender/out/AllVehicles.glb |
| Single vehicles | `https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/blender/out/<Vehicle>.glb` (Sedan, SportsCar, PoliceCar, MuscleCar, PickupTruck, MonsterTruck, CityBus, DumpTruck, Tank, ArmoredTruck, SmallPlane, CargoPlane, Helicopter, Train, Bulldozer, GoKart, RocketSled) |
| Source (Blender scripts, Luau, tests) | https://github.com/zeringflix/Interstellar/tree/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics |

## Steps
1. Download `RagdollCrashPhysics.rbxlx` and `AllVehicles.glb` (e.g. `curl -L -o RagdollCrashPhysics.rbxlx <link>`).
2. Open `RagdollCrashPhysics.rbxlx` in Roblox Studio (File > Open from File). Confirm `Workspace.Map`, `ServerScriptService.Server`, `StarterPlayer.StarterPlayerScripts.Client` and `ReplicatedStorage.Shared` exist.
3. File > **Import 3D** > `AllVehicles.glb` (default options). Drag the imported model into `ReplicatedStorage.VehicleMeshes` so that it contains one child per vehicle (`Sedan`, `Tank`, ...). Each child's parts are named like `Sedan_Body`, `Sedan_Wheel1`.
   The models are textured: in the import window keep textures / materials enabled, and check that each mesh (e.g. `Sedan_Body`) has a `SurfaceAppearance` child after import. Glass and lamp meshes have none on purpose.
4. Press Play. Expected: you spawn at the plaza, a yellow sports car is parked facing a row of grey dummies, and the VEHICLES / DUMMIES-style buttons are on the left. Drive into the dummies; a two-line damage bar appears at the bottom.
5. File > Publish to Roblox; Game Settings > Max Players = 1.
6. Optional: paste uploaded icon / Folk UI image ids into `StarterPlayerScripts.Client.UIAssets`.

## If something looks wrong
- A vehicle looks blocky: its model was not imported under `VehicleMeshes`, or the part names changed.
- Meshes import white / without `SurfaceAppearance`: re-import with textures enabled, or import the single `<Vehicle>.glb` files.
- Imported meshes are the wrong way round or white: tell me the vehicle; orientation and vertex colours are not yet verified in Studio.
- Output window errors: send them back; nothing here has been run in Studio yet (see README "What has and has not been tested").
