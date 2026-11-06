# Design notes

Units are mm and kg; coordinates are in the station world frame unless stated otherwise.

## 1. Layout

| Element | Position / size | Notes |
|---|---|---|
| Robot IRB 1600-10/1.45 | Base at (0, 0, 0), rotated 135° about Z | Puts the ±180° limit of axis 1 in the gap between the two pallets, so no motion sequence has to cross it |
| Conveyor 1 (box 1) | Enters from +Y, axis x ≈ +340, end y ≈ 650, belt at z 768 | |
| Conveyor 2 (box 2) | Enters from +Y, axis x ≈ −350, end y ≈ 650, belt at z 768 | |
| Euro pallet (1200 × 800 × 144) | x 600…1400, y −600…600 | Next to conveyor 1 |
| Half pallet (800 × 600 × 144) | x −400…400, y −1200…−600 | |
| Stacking table (500 × 600 × 770) | x −1100…−600, y 0…600 | Next to conveyor 2: the conveyor 2 → table move is made 72 times per pallet, so it is the shortest |
| Liner stand (800 × 540 × 500) | x −1300…−500, y −700…−160 | Low, so the blocks can pass over it; stack of 10 liners (800 × 540 × 10) |

Pallets and liners sit on the perimeter of the cell, so they are replaced without entering it.

## 2. Robot and tool

- **Tool `toolVacuum`:** 6 bellows cups Ø50 at x = −160 / 0 / +160, y = ±100, one valve per cup. TCP on the cup lips,
  175 mm from the flange.
- **Box 2 is picked with one corner cup** (`Cup21`): the box (130 × 130) is smaller than the cup pattern, and using the
  centre of the gripper would put the other cups on the neighbouring boxes on the table.
- **Home:** `jointtarget` [0, 0, 0, 0, 90, 0], with the gripper vertical.

## 3. Work objects (`CalibData.mod`)

| Work object | Origin | X / Y |
|---|---|---|
| `wobjEuroPallet` | Corner nearest the robot and conveyor 1, top of the pallet | X along the long side, away from the conveyors; Y away from the robot |
| `wobjHalfPallet` | Corner nearest the robot and the Euro pallet, top of the pallet | X along the long side, towards the liner stand; Y away from the robot |
| `wobjConveyor1`, `wobjConveyor2` | End of the conveyor next to the robot, centred on the belt | X along the conveyor, against the flow |
| `wobjTable` | Corner next to the end of conveyor 2, table top | User frame; the object frame (55, 170) centres the 3×2 block on the table |
| `wobjLinerStack` | Corner nearest the robot and the half pallet, top of the stand | X along the 800 mm side of the liner |

## 4. Payload check

**Tool mass.** RobotStudio only has the graphics of the gripper, so its mass was estimated from the measured parts in
aluminium (2700 kg/m³), with the column as a tube and the main plate hollow (5 mm walls): **4.7 kg**, centre of gravity
on the tool axis 100 mm from the flange. As a solid block it would weigh 9.6 kg, which together with the 2.4 kg block
would exceed the 10 kg payload of the robot.

**Loads** (centre of gravity relative to the TCP; inertia about the load's own centre of gravity, as a solid box):

| Load | Mass | CoG | Ix / Iy / Iz (kg·m²) |
|---|---|---|---|
| `loadBox1` (500 × 250 × 200) | 2.0 | (0, 0, 100) | 0.0171 / 0.0483 / 0.0521 |
| `loadBox2` (130 × 130 × 200) | 0.4 | (−160, −100, 100) | 0.0019 / 0.0019 / 0.0011 |
| `loadBox2Stack` (390 × 260 × 200) | 2.4 | (0, 0, 100) | 0.0215 / 0.0384 / 0.0439 |
| `loadLiner` (800 × 540 × 10) | 0.52 | (0, 0, 5) | 0.0126 / 0.0277 / 0.0404 |
| `toolVacuum` | 4.7 | (0, 0, 100) from the flange | 0.0274 / 0.0462 / 0.0605 |

**Load diagram** (*Product specification IRB 1600/1660*, ABB 3HAC023604-001). Tool plus load, with Z measured from
the flange along axis 6:

| Case | Total mass | Z | Standard diagram | Vertical wrist (±10°) |
|---|---|---|---|---|
| Tool + 3×2 block | 7.1 kg | 159 mm | Outside | Inside |
| Tool + box 1 | 6.7 kg | 152 mm | Outside | Inside |
| Tool + box 2 | 5.1 kg | 114 mm | Inside | Inside |
| Tool + liner | 5.2 kg | 108 mm | Inside | Inside |

The vertical-wrist diagram applies because the gripper always works vertically (every target has the tool pointing
down). The wrist inertia limits are met in every case, with the block as the worst one:
J5 = 0.49 ≤ 0.6 kg·m² and J6 = 0.10 ≤ 0.4 kg·m².

## 5. Motion strategy

- One base target per station; every other position is computed with `Offs`.
- `ApproachPoint` does every pick and place: `MoveJ` to an approach point above the target, vertical `MoveL` down,
  vacuum on or off, `GripLoad`, and vertical `MoveL` up. Transit moves are `MoveJ` at a common transit height
  (1100 mm in the world frame); only the vertical moves are linear.
- `ApproachHeight(station)` holds one formula per station, so each approach height is defined in one place; above the
  pallets it depends on the current layer and never drops below 250 mm over the target.
- On the stacking table the far row is filled first and each row from high to low X, so the box being carried never
  passes over the boxes already placed.
- Box 1 and box 2 each have their own layer and position counters, so the two products are independent.

## 6. Operator interaction

| Event | Output | Operator action (input) | Robot behaviour |
|---|---|---|---|
| Euro pallet full | `DO_EuroPalletFull` + message | Swap the pallet, press *Euro pallet replaced* (`DI_EuroPalletReplaced`) | Keeps working with box 2 |
| Half pallet full | `DO_HalfPalletFull` + message | Swap the pallet, press *Half pallet replaced* (`DI_HalfPalletReplaced`) | Keeps working with box 1; one more block can be finished on the table and waits there |
| Liner stack empty | `DO_LinerStackEmpty` + message | Refill the stack, press *Liners refilled* (`DI_LinersRefilled`) | Keeps working until a liner is needed; then box 2 waits |

The three buttons are connected to interrupts. The `TRAP` only accepts a press when it makes sense (pallet full or
stack empty), switches the light off at once and sets a flag; `Main` resets the counters and, if needed, places the
missing liner and the waiting block when the robot is free. The messages are shown once with `TPWrite`, without
stopping the robot.

## 7. Safety equipment (modelled in the station)

- Safety fence around the cell, with tunnels for the two conveyors.
- Maintenance door with an interlock sensor.
- Emergency stops inside and outside the cell, and operator stations with reset buttons at each access point.
- Light curtains with muting sensors and muting lamps on the conveyor tunnels.
- Light curtains and safety mats at the Euro pallet, half pallet and liner access points; pallet stops and bumpers.
- Operator buttons and status lamps outside the fence; IRC5 cabinet.

## 8. Simulation

- **Conveyors** (`SC_Conveyor1`, `SC_Conveyor2`): a source creates boxes that a linear mover carries to a plane sensor
  at the end (`DI_Box1Arrived`, `DI_Box2Arrived`). Each box placed on a pallet is queued; when the operator confirms
  the swap, a repeater deletes the boxes of the full pallet (12 or 72), so the box waiting on the conveyor stays.
- **Gripper** (`SC_Gripper`): a line sensor and attach/detach logic per cup, driven by the cup signals
  `DO_Cup11`…`DO_Cup23`.
- **Liners** (`SC_Liners`): ten sources build the stack; the two liners of a full half pallet are removed together with
  its boxes, and the refill button rebuilds the stack.
- **Collision set:** robot and tool against the conveyors, table, liner stand and pallets, with a 50 mm near-miss
  zone. The boxes and liners are not in the set, because they are meant to touch.
- Saved state **`Inicio_04-11`**: empty pallets, full liner stack, robot at home.
