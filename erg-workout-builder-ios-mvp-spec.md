# ERG Workout Builder (iOS) — MVP Spec

**Purpose:** A lightweight iOS app to **create and run structured ERG workouts** on a Tacx Neo–class smart trainer, using **%FTP** targets and showing **Watts (target + actual), Cadence, and Heart Rate** in real time.

---

## 1. Product scope

### 1.1 Goals
- Build and edit a small library of custom structured workouts (typically ~12–30).
- Execute workouts in **ERG mode** on a smart trainer over Bluetooth.
- Display live telemetry: **Target W, Actual W, Cadence, HR**, plus step timer and workout progress.
- Work **offline** with **local storage**. No account required.

### 1.2 Non-goals (MVP)
- No free-ride/resistance mode.
- No routes/virtual world/social.
- No training plans, coaching, or LLM integration (added later).
- No deep analytics (basic summary only).

---

## 2. User stories

### Workout creation
1. As a user, I can set my **FTP** once and update it anytime.
2. As a user, I can create a workout from **steps** (steady, ramp, repeats) using **%FTP**.
3. As a user, I can duplicate a workout and tweak a few steps quickly.

### Workout execution
4. As a user, I can connect my **trainer**, **HR strap**, and optionally a cadence sensor.
5. As a user, I can run the workout in **ERG** and see **target vs actual power** plus cadence and HR.
6. As a user, I can **pause/resume** and **skip steps** if needed.
7. As a user, I can save a simple **ride summary** after completion.

---

## 3. Functional requirements

### 3.1 Settings
- **FTP (watts)**: integer, editable, default prompt on first launch.
- Optional (MVP): units/locale handled by iOS defaults (no special settings).

### 3.2 Workout library
- List workouts (name, duration).
- Actions:
  - Create new
  - Edit
  - Duplicate
  - Delete (confirm)
- Sort:
  - Recently updated (default)
  - Name (optional)

### 3.3 Workout builder
#### Step types
- **Steady**: `durationSec`, `intensityPctFtp`
- **Ramp**: `durationSec`, `startPctFtp`, `endPctFtp`
- **Repeat block**: `repeatCount`, `subSteps[]`  
  - Nesting depth: **1 level** (repeat contains steady/ramp only)

#### Builder UX
- Step list with:
  - Add step (Steady / Ramp / Repeat)
  - Reorder (drag)
  - Edit inline or via detail sheet
  - Delete step (swipe)
- Show:
  - Total workout duration
  - Optional mini “step chart” (nice-to-have)

#### Validation rules
- `durationSec >= 5`
- `%FTP` bounds: `30–200`
- `repeatCount`: `2–50`
- Total duration max (config): `3 hours`
- Repeat block must contain at least 1 sub-step

### 3.4 Device connectivity
- Bluetooth LE pairing and connection for:
  - **Trainer** (required)
  - **Heart rate** (optional)
  - **Cadence** (optional; prefer trainer cadence when available)

#### Services (expected)
- Trainer control: **FTMS (Fitness Machine Service)** when available
- Trainer power (read): FTMS and/or Cycling Power Service
- HR: BLE Heart Rate Service
- Cadence: trainer-provided cadence or BLE Cycling Speed & Cadence

### 3.5 Workout execution (ERG-only)
- Convert %FTP to target watts using the current FTP:
  - `targetW = round(ftpW * pct / 100)`
- Apply targets to trainer in ERG:
  - For **Steady**: set target at step start (and keepalive as needed)
  - For **Ramp**: linearly interpolate and update target at **1 Hz**

#### Player UI (required)
- Large readouts:
  - **Target W**
  - **Actual W**
- Medium readouts:
  - **Cadence**
  - **HR**
- Step info:
  - Step label/type + %FTP
  - Time remaining in step
  - Next step preview (name + %FTP + duration)
- Progress:
  - Overall elapsed/remaining
  - Step timeline/progress bar

#### Controls (required)
- Start (once devices connected)
- Pause / Resume
- Skip to next step
- Skip to previous step (restart current step or go back one step)
- End workout early (confirm)

#### Behavior rules
- If trainer disconnects while running:
  - Auto-pause
  - Show reconnect UI
  - Attempt reconnect periodically
  - Resume at the same step/time when reconnected
- Missing HR/cadence:
  - Show “—” but allow workout to continue
- Prevent screen auto-lock while running (keep display awake)

---

## 4. Ride summary (MVP-lite)
When a workout ends (complete or aborted), store a ride record with:
- Workout reference
- Start/end timestamps
- FTP used
- Duration completed
- Basic averages (where available):
  - Avg power
  - Avg HR
  - Avg cadence
- Completion status: `completed | aborted`

**Optional (still small):** store 1 Hz samples (power/target/cadence/hr) for a simple target-vs-actual chart later.

---

## 5. Data model (suggested)

### 5.1 Entities

#### AppSettings
- `ftpWatts: Int`
- `createdAt: Date`
- `updatedAt: Date`

#### Workout
- `id: UUID`
- `name: String`
- `notes: String?`
- `steps: [WorkoutStep]`
- `createdAt: Date`
- `updatedAt: Date`

#### WorkoutStep
- `id: UUID`
- `type: StepType` (`steady | ramp | repeat`)
- `label: String?`
- `durationSec: Int` (steady/ramp only; repeat derived from children)
- Steady fields:
  - `intensityPctFtp: Int?`
- Ramp fields:
  - `startPctFtp: Int?`
  - `endPctFtp: Int?`
- Repeat fields:
  - `repeatCount: Int?`
  - `children: [WorkoutStep]?` (steady/ramp only)

#### Ride
- `id: UUID`
- `workoutId: UUID?`
- `startedAt: Date`
- `endedAt: Date`
- `ftpWattsUsed: Int`
- `status: RideStatus` (`completed | aborted`)
- Summary fields:
  - `avgPower: Double?`
  - `avgHr: Double?`
  - `avgCadence: Double?`
  - `durationSec: Int`

#### (Optional) RideSample
- `rideId: UUID`
- `tSec: Int`
- `targetWatts: Int`
- `powerWatts: Int?`
- `hrBpm: Int?`
- `cadenceRpm: Int?`

### 5.2 Persistence
- Local-only persistence using **Core Data** (recommended) or SQLite.
- No cloud sync in MVP.

---

## 6. System design

### 6.1 Modules
- **Workout Engine**
  - Step expansion (repeat → flattened timeline)
  - Target computation (steady/ramp)
  - Timer + state machine
- **BLE Device Layer**
  - Scanning, pairing, reconnect logic
  - FTMS control commands (set target power)
  - Sensor subscriptions (power/cadence/hr)
- **UI Layer (SwiftUI)**
  - Library, Builder, Devices, Player, Summary
- **Storage Layer**
  - CRUD for workouts/settings/rides

### 6.2 State machine
- `Idle`
- `Connecting`
- `Ready`
- `Running`
- `Paused`
- `Finished`
- `Error` (recoverable; e.g., Bluetooth off)

---

## 7. UI spec (screens)

### 7.1 Library
- Workout list
- “New workout” CTA
- Tap workout → details
- Swipe actions: duplicate, delete

### 7.2 Workout details
- Step list preview + total duration
- Start workout
- Edit workout

### 7.3 Builder
- Name + notes
- Step list with add/reorder/edit/delete
- Save (validates)

### 7.4 Devices
- Trainer card (required): connect/disconnect/status
- HR card (optional)
- Cadence source (auto; show which source is active)

### 7.5 Player
- Telemetry tiles (target/actual/cadence/hr)
- Step timer + next step
- Timeline/progress
- Controls (pause/skip/end)

### 7.6 Summary
- Completion status
- Duration
- Avg power/HR/cadence
- Done (back to library)

---

## 8. Error handling & edge cases
- Bluetooth off → prompt to enable; block starting workout.
- Trainer connected but control unsupported → show “ERG control not available” and block start.
- Reconnect loop should back off (e.g., 1s → 2s → 5s) to reduce battery drain.
- If app is backgrounded:
  - Keep workout running if allowed; otherwise pause and inform user on return (implementation decision).

---

## 9. Testing plan (minimum)
1. Connect trainer + start steady ERG @ 60% FTP.
2. Ramp 50→90% over 10 min: verify target updates are smooth (1 Hz).
3. Repeat block transitions are correct (timing + targets).
4. Pause/resume retains step timing and target.
5. Skip forward/back changes targets immediately.
6. Mid-workout trainer disconnect → auto-pause → reconnect → resume.
7. HR missing/unpaired → workout still runs.
8. Validate builder rejects invalid durations/%FTP/repeats.

---

## 10. Delivery milestones
1. **BLE FTMS control**: connect trainer, set ERG target watts, read power.
2. **Workout player**: steady steps only, %FTP conversion.
3. **Ramp + repeats**: step expansion + 1 Hz ramp updates.
4. **Builder + library**: CRUD + validation + persistence.
5. **Sensors + summary**: HR/cadence + ride summary.

---

## 11. Future extension hooks (not in MVP)
- ERG bias slider (±%) during ride
- Import/export (ZWO/JSON)
- Charts using stored 1 Hz samples
- LLM workout generation + coaching
