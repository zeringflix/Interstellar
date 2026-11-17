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
   Each vehicle also has `<Vehicle>_Interior` meshes (the researched cockpit) and one `<Vehicle>_Steer` mesh (its steering wheel, yoke or handlebars). Keep those names: the game turns the `_Steer` mesh with the steering and puts the driver's hands on it in first person.
4. Press Play. Expected: you spawn at the plaza with a car parked facing a row of grey dummies, and the VEHICLES / DUMMIES-style buttons are on the left. Drive into the dummies; a two-line damage bar appears at the bottom. Press **V** (or FIRST PERSON on the driving panel) for the first-person view: the camera should sit in the driver's seat looking out of the windscreen, with your avatar's hands on the wheel.
5. File > Publish to Roblox; Game Settings > Max Players = 1; Game Settings > Security > Enable Studio Access to API Services (progress saving).
6. Robux vehicles: create three game passes (Monster Truck R$ 99, Tank R$ 149, Rocket Sled R$ 199) under Creator Dashboard > Monetization > Passes and paste the ids into `Config.Progression.Paid` (ReplicatedStorage > Shared > GameConfig). To try every vehicle while testing, set `StudioUnlockAll = true` there (Studio only).
7. Optional: paste uploaded icon / Folk UI image ids into `StarterPlayerScripts.Client.UIAssets`.

## If something looks wrong
- A vehicle looks blocky: its model was not imported under `VehicleMeshes`, or the part names changed.
- Meshes import white / without `SurfaceAppearance`: re-import with textures enabled, or import the single `<Vehicle>.glb` files.
- Imported meshes are the wrong way round or white: tell me the vehicle; orientation and vertex colours are not yet verified in Studio.
- First person shows the inside of the roof or the avatar's body in the way: tell me the vehicle; the eye points are in `blender/vehicles_spec.py` (`COCKPITS`) and in `ReplicatedStorage.Shared.VehicleSpecs` (`cockpit.eye`).
- Output window errors: send them back; nothing here has been run in Studio yet (see README "What has and has not been tested").
