# Install RAGDOLL CRASH PHYSICS into Roblox Studio

This guide is written for another Claude agent (for example Claude desktop with computer use, or Claude Code with the Roblox Studio MCP server). A person can follow it just as well. Do the steps in order. Every step says what you should see when it worked, and what to do when it did not.

- Repository: `zeringflix/Interstellar`
- Branch: `claude/ragdoll-crash-physics-research-j5nvbr`
- Folder: `ragdoll-crash-physics/`

The rest of the repository is an unrelated web project. Leave it alone.

## What you are installing

| File | What it is | Size | SHA-256 |
|---|---|---|---|
| `ragdoll-crash-physics/RagdollCrashPhysics.rbxlx` | The complete Studio place: every script, the UI, audio, the dummies and the baked Test Grounds map | 1,914,054 bytes | `5e7fb4d2db00801bf1a7cfdedf7630f6673857c01b9a6492d51a6f25952e8a90` |
| `ragdoll-crash-physics/blender/out/AllVehicles.glb` | All 17 detailed, textured vehicle models with their interiors and steering wheels, in one file | 75,279,616 bytes | `11c11c256ba5878fc6d950fe60a23aab7c3450aa1bdc8d1e30baaca0e8cbbd5b` |
| `ragdoll-crash-physics/roblox/tools/verify_install_studio.luau` | Install check you paste into Studio's Command Bar. It prints `INSTALL OK` or a list of problems | small | |
| `ragdoll-crash-physics/blender/out/<Vehicle>.glb` | The same vehicles as single files, used only if the big import fails | 1.6 to 6.9 MB each | |

The place works without the models: every vehicle then shows as a blocky stand-in that drives the same. The models add the detailed bodies, the textures, the researched interiors, and the steering wheel that turns and is held in first person.

## Before you start

1. **Roblox Studio** must be installed and signed in. Import 3D uploads the meshes and textures to the signed-in account, so it needs an internet connection.
2. **Tools you need:**
   - Studio's UI, for File > Open, File > Import 3D, dragging in the Explorer and Game Settings. You need computer use for these, or the person does them.
   - The **Command Bar** (View > Command Bar), to run the check script. If you have the Roblox Studio MCP server, its run-code tool can run the same script.
3. **Do not:**
   - Do not rename, regroup or merge any imported mesh. The game finds every mesh by its exact name, for example `Sedan_Steer`.
   - Do not move scripts between containers.
   - Do not edit `VehicleMeshInfo`, `VehicleSpecs` or `Cockpit` in `ReplicatedStorage.Shared`; they are generated.

## Step 1: Download the files

The repository may be private. Use `git` with GitHub access; this needs no Git LFS, because the 72 MB file is a normal git file.

```bash
git clone --depth 1 --branch claude/ragdoll-crash-physics-research-j5nvbr https://github.com/zeringflix/Interstellar.git
cd Interstellar/ragdoll-crash-physics
```

On Windows, run the same two commands in PowerShell or Git Bash. If `git` asks for credentials, sign in with the GitHub account that can see the repository, or use `gh repo clone zeringflix/Interstellar -- --depth 1 --branch claude/ragdoll-crash-physics-research-j5nvbr`.

If the repository is public, the files can be downloaded directly instead:
- https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/RagdollCrashPhysics.rbxlx
- https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/blender/out/AllVehicles.glb
- https://github.com/zeringflix/Interstellar/raw/claude/ragdoll-crash-physics-research-j5nvbr/ragdoll-crash-physics/roblox/tools/verify_install_studio.luau

**Check:** compare the sizes, or the SHA-256 hashes, with the table above.
- macOS / Linux: `shasum -a 256 RagdollCrashPhysics.rbxlx blender/out/AllVehicles.glb`
- Windows: `Get-FileHash RagdollCrashPhysics.rbxlx, blender\out\AllVehicles.glb`

A file of a few KB is a GitHub error page, not the real file. Download it again while signed in.

## Step 2: Open the place

1. Open Roblox Studio > File > **Open from File** > `RagdollCrashPhysics.rbxlx`.
2. **Check in the Explorer:**
   - `Workspace` > `Map`: the pre-built map, with no Baseplate.
   - `ReplicatedStorage` > `Shared`: 7 ModuleScripts.
   - `ReplicatedStorage` > `VehicleMeshes`: an empty Folder.
   - `ServerScriptService` > `Server`: a Script named `Main` and 10 ModuleScripts.
   - `StarterPlayer` > `StarterPlayerScripts` > `Client`: a LocalScript named `Main` and 13 ModuleScripts.
3. Save it as your own place with File > Save to File As, so the original download stays untouched.

## Step 3: Import the vehicle models

1. File > **Import 3D** > select `blender/out/AllVehicles.glb`.
2. In the import window:
   - Keep the defaults. Texture and material import must stay on.
   - If there is a rig option, choose no rig.
   - If there is a "merge meshes" option, leave it off.
   - Click **Import**.

   There are 17 vehicles and 162 meshes, 131 of them textured, so the import and asset upload can take several minutes. Wait until the model appears in the Explorer.
3. The import lands in `Workspace`, usually as a Model named `AllVehicles`. Move it into the folder by dragging `AllVehicles` onto `ReplicatedStorage` > `VehicleMeshes` in the Explorer, or by running this in the Command Bar:
   ```lua
   for _, m in workspace:GetChildren() do if m.Name ~= "Map" and m:FindFirstChild("Sedan_Body", true) then m.Parent = game.ReplicatedStorage.VehicleMeshes; print("moved", m.Name) end end
   ```
   It moves only the imported model, which is the one containing `Sedan_Body`, and prints `moved AllVehicles`.
4. **Check the layout.** `VehicleMeshes` must contain one Model per vehicle, nested one level down is fine:
   - The 17 Models are named `Sedan`, `SportsCar`, `PoliceCar`, `MuscleCar`, `PickupTruck`, `MonsterTruck`, `CityBus`, `DumpTruck`, `Tank`, `ArmoredTruck`, `SmallPlane`, `CargoPlane`, `Helicopter`, `Train`, `Bulldozer`, `GoKart` and `RocketSled`.
   - Each holds MeshParts named like `Sedan_Body`, `Sedan_Trim`, `Sedan_Glass`, `Sedan_Lights`, `Sedan_Interior`, `Sedan_Steer` and `Sedan_Wheel1` to `Sedan_Wheel4`. Some have `..._Interior2`, `..._Trim2`, `..._Spin1` (propellers and rotors) or `Tank_Turret`.
   - Textured meshes each have a `SurfaceAppearance` child. `_Glass` and `_Lights` meshes have none, on purpose.

**If the big import fails or times out:** import the single files `blender/out/Sedan.glb`, `SportsCar.glb` and so on, one at a time. Move each imported Model, named after its file, into `ReplicatedStorage.VehicleMeshes`. The result is the same.

## Step 4: Run the install check

1. View > **Command Bar**.
2. Open `roblox/tools/verify_install_studio.luau` in a text editor, copy the whole file, paste it into the Command Bar and press Enter. Stay in Edit mode, not Play.
3. Read the Output window (View > Output):
   - `[RCP check] note: vehicles complete: 17 of 17 (... meshes found)` followed by `[RCP check] INSTALL OK` means you are done with the setup.
   - `[RCP check] PROBLEM: ...` lines name exactly what is wrong:

| Problem line | Fix |
|---|---|
| `missing ReplicatedStorage.Shared...` (or any script) | The wrong file was opened. Reopen `RagdollCrashPhysics.rbxlx` from Step 1. |
| `<Vehicle>: no model named '<Vehicle>'` | That vehicle's Model is not inside `VehicleMeshes`. Finish Step 3, or import `<Vehicle>.glb`. |
| `<Vehicle>: missing meshes ...` | The listed meshes were renamed (for example `Sedan_Steer.001`) or skipped. Rename them back to exactly the listed name, or re-import that vehicle's `.glb`. |
| `meshes without a SurfaceAppearance` | Textures were not imported. Delete that vehicle's Model and re-import with texture import on. |
| `no <Vehicle>_Steer mesh` | The steering wheel mesh is missing. Re-import that vehicle. |

   Notes, not problems:
   - "game pass id is 0" is expected until Step 6.
   - "Avatar type is R6" is explained in Step 5.

Run the check again after each fix until it prints `INSTALL OK`.

## Step 5: Game settings

Open Home > **Game Settings**. These settings save to the published experience, so publish first with File > Publish to Roblox.
1. **Security** > turn on **Enable Studio Access to API Services**. Crash points and unlocks save to a DataStore. Without it the game still runs, with progress for the session only.
2. **Avatar** > Avatar type **R15**, or Player Choice. First person works on any avatar, but only R15 avatars hold the steering wheel with their hands.
3. **Places** > this place > Max Players = **1**. Each player gets their own sandbox server.

## Step 6: Robux vehicles (optional, needed before going live)

The three paid vehicles are Monster Truck R$ 99, Tank R$ 149 and Rocket Sled R$ 199.
1. Creator Dashboard > your experience > **Monetization** > **Passes**. Create three passes with exactly these prices.
2. Copy each pass ID.
3. In Studio, open `ReplicatedStorage` > `Shared` > `GameConfig` and replace the `0`s:
   ```lua
   Paid = { -- coolest last
       { vehicle = "MonsterTruck", passId = 0, price = 99 },   -- 0 -> Monster Truck pass id
       { vehicle = "Tank", passId = 0, price = 149 },          -- 0 -> Tank pass id
       { vehicle = "RocketSled", passId = 0, price = 199 },    -- 0 -> Rocket Sled pass id
   },
   ```
4. Publish again.

## Step 7: Play test (what you should see)

To try every vehicle, set `StudioUnlockAll = true` in `GameConfig`. It only works in Studio and never in live servers. Then press **Play** (F5).

1. You spawn on the plaza with a **blue sedan** parked next to you and grey test dummies nearby. Walk to the car and press **E** (the "Drive" prompt). The driving panel appears bottom-right, with speed and key binds.
2. Drive with W/S/A/D into the dummies. A damage bar appears at the bottom, the dummies ragdoll, and their faces react.
3. **First person:** press **V**, or the FIRST PERSON button on the driving panel.
   - The camera moves to your avatar's eyes in the driver's seat and looks out of a clear windscreen.
   - The steering wheel is in front of you, with the speedometer and tachometer visible through the top of it.
   - With an R15 avatar, both hands are on the wheel, and the wheel turns when you press A or D.
   - Hold the right mouse button and move to look around; the view returns to straight ahead.
   - Press V again for the normal camera.
4. Open **VEHICLES** on the left and spawn several vehicles. Press V in each. Expected views:

| Vehicle | First-person view |
|---|---|
| Sedan, Police Car, Muscle Car, Sports Car, Pickup | Driver's seat on the left, wheel and gauges ahead, wide windscreen |
| Monster Truck | Centred seat inside the roll cage, small wheel, switch panel |
| City Bus | High seat, big near-flat wheel, large windscreen |
| Dump Truck, Armored Truck | High cab, big wheel, rows of gauges; the armoured truck looks through framed thick panes |
| Tank | Head out of the open driver's hatch above the hull, gun above to the right, T-bar handlebars below |
| Small Plane | Left seat, six-gauge panel and yoke, high wing visible above |
| Cargo Plane | Captain's seat on the flight deck, displays and yoke |
| Helicopter | Right seat in the glass bubble, console to the left |
| Train | Engineer's seat on the right of the cab, looking along the boiler through the front window |
| Bulldozer | Centred in the glass cab, looking over the engine hood |
| Go-Kart | Low seat, small wheel, front wheels either side |
| Rocket Sled | Open seat behind a small windscreen over the nose |

5. The Output window must show **no red errors**.
6. Set `StudioUnlockAll` back to `false` when you are done testing.

## If something looks wrong in play

| What you see | Cause and fix |
|---|---|
| A vehicle is blocky | Its Model is not in `VehicleMeshes`, or a mesh name changed. Run the Step 4 check. |
| Vehicles are white or untextured | Textures were not imported. Re-import with texture import on. |
| The steering wheel does not turn, or no hands in first person | The `_Steer` mesh is missing (Step 4 check), or the avatar is R6 (Step 5). |
| A first-person view is inside the roof or behind something | Note the vehicle and send a screenshot. Each eye point is one line in `blender/vehicles_spec.py` (`COCKPITS`) and in `ReplicatedStorage.Shared.VehicleSpecs` (`cockpit.eye`). |
| Other players see a tall avatar's head through a car roof | Known. The seat fitting that keeps your own view inside the cab is applied on your screen only. |
| Red errors in Output | Copy them exactly and send them back. Nothing here has been run in Studio before. |

## Reporting back

When finished, report:
1. The last lines of the Step 4 check output, ideally `INSTALL OK`.
2. Whether each Step 7 point worked.
3. Any red Output errors, copied exactly.
4. A screenshot of the first-person view of any vehicle that looked wrong.

## For developers (not needed to install)

- Rebuild the place from source:
  ```bash
  cd roblox && rojo build -o place.rbxl && lune run tools/bake_place.luau place.rbxl ../RagdollCrashPhysics.rbxlx
  ```
- Run the tests with `lune run tests/<name>.luau`:
  - syntax_check
  - damage_spec
  - builders_spec
  - map_spec
  - place_spec
  - integration_spec
  - verify_install_spec
- Rebuild the models with `cd blender && python3 vehicles_spec.py && python3 build_realistic.py`, then:
  - `python3 texture_vehicles.py apply all=1`
  - `python3 export_all.py`
  - `python3 export_mesh_info.py`
  - `python3 check_cockpits.py`
  - `python3 fp_render.py`
