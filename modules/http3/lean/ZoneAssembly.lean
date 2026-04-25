/-!
# Zone Assembly Invariants

Proves the key properties established by direct commits to `multiplayer-fabric`
(session 2026-04-25) that are not captured in any feat branch.

These proofs are the machine-checked memory of what was implemented.
Whoever re-assembles the branch must re-establish every theorem here:

1. **Port assignment** — zone server owns UDP 7443 locally and UDP 443
   externally; zone-backend owns TCP 443; port 17500 was the wrong
   default and is now retired.

2. **Packet layout** — CH_INTEREST and CH_PLAYER share a 100-byte layout;
   payload starts at byte 44 and holds 14 × uint32 (56 bytes), summing
   to exactly 100.

3. **Observer** — connects to the zone server, collects entities from
   CH_INTEREST datagrams, exits 0 iff at least one entity was received
   before the frame deadline, exits 1 on timeout.

4. **Player** — sends CH_PLAYER datagrams; cmd byte distinguishes heartbeat
   (0), jellyfish spawn (1), and stroke knot (3); commands are distinct.

5. **Operator camera swing invariant** — SWING_ELEVATION is a constant;
   no input transition (rotate, zoom, follow, exit-follow) changes it.
-/

set_option autoImplicit false

-- ---------------------------------------------------------------------------
-- § 1  Port assignment
-- ---------------------------------------------------------------------------

/-- UDP port the zone server listens on locally. -/
def ZONE_SERVER_PORT_LOCAL : Nat := 7443

/-- UDP port the zone server is reachable on externally (Cloudflare, UDP 443). -/
def ZONE_SERVER_PORT_EXTERNAL : Nat := 443

/-- TCP port the zone-backend (Phoenix/Bandit) listens on. -/
def ZONE_BACKEND_PORT : Nat := 443

/-- The old wrong default that was hardcoded before this session. -/
def RETIRED_PORT : Nat := 17500

theorem zone_server_local_not_retired :
    ZONE_SERVER_PORT_LOCAL ≠ RETIRED_PORT := by decide

theorem zone_server_local_not_backend_port :
    ZONE_SERVER_PORT_LOCAL ≠ ZONE_BACKEND_PORT := by decide

/-- fabric_client.gd and headless_log_observer.gd use 7443 locally. -/
theorem correct_local_port : ZONE_SERVER_PORT_LOCAL = 7443 := by decide

-- ---------------------------------------------------------------------------
-- § 2  Packet layout (CH_INTEREST and CH_PLAYER)
-- ---------------------------------------------------------------------------

/-- Both CH_INTEREST and CH_PLAYER are exactly 100 bytes. -/
def PACKET_SIZE : Nat := 100

/-- Byte offset of payload[0] within each packet entry. -/
def PAYLOAD_OFFSET : Nat := 44

/-- Number of uint32 payload words. -/
def PAYLOAD_COUNT : Nat := 14

/-- Bytes occupied by the payload region. -/
def PAYLOAD_BYTES : Nat := PAYLOAD_COUNT * 4

/-- Header region: gid(4) + xyz f64(24) + vel i16×3(6) + accel i16×3(6) + hlc(4) = 44. -/
def HEADER_BYTES : Nat := 44

theorem packet_layout_exact :
    HEADER_BYTES + PAYLOAD_BYTES = PACKET_SIZE := by decide

theorem payload_offset_matches_header :
    PAYLOAD_OFFSET = HEADER_BYTES := by decide

/-- payload[1..13] start at byte 48 and end exactly at byte 100. -/
def EXTRA_PAYLOAD_START : Nat := PAYLOAD_OFFSET + 4
def EXTRA_PAYLOAD_END   : Nat := PAYLOAD_OFFSET + PAYLOAD_BYTES

theorem extra_payload_fits : EXTRA_PAYLOAD_END = PACKET_SIZE := by decide

-- ---------------------------------------------------------------------------
-- § 3  Observer model
-- ---------------------------------------------------------------------------

structure ObserverState where
  frame    : Nat   -- frames elapsed
  maxFrame : Nat   -- timeout threshold (default 600)
  entities : Nat   -- total entities seen so far
  deriving Repr

inductive ObserverResult | pass | timeout
  deriving DecidableEq, Repr

/-- Advance one frame, adding any newly received entities. -/
def observerStep (s : ObserverState) (newEntities : Nat) : ObserverState :=
  { s with frame := s.frame + 1, entities := s.entities + newEntities }

/-- Outcome: pass as soon as any entity arrives; timeout at maxFrame. -/
def observerOutcome (s : ObserverState) : Option ObserverResult :=
  if s.entities > 0 then some .pass
  else if s.frame ≥ s.maxFrame then some .timeout
  else none

/-- Receiving entities produces a pass outcome (exit 0). -/
theorem observer_pass_on_entities (s : ObserverState) (h : s.entities > 0) :
    observerOutcome s = some .pass := by
  simp [observerOutcome, h]

/-- Timeout can only be produced when no entities have been received. -/
theorem observer_timeout_means_no_entities (s : ObserverState)
    (h : observerOutcome s = some .timeout) : s.entities = 0 := by
  unfold observerOutcome at h
  split at h <;> simp_all <;> omega

/-- Pass and timeout are mutually exclusive. -/
theorem observer_pass_not_timeout (s : ObserverState) :
    observerOutcome s ≠ some .pass ∨ observerOutcome s ≠ some .timeout := by
  cases hv : observerOutcome s with
  | none   => left; simp
  | some r => cases r with
    | pass    => right; simp
    | timeout => left;  simp

/-- step strictly increases the frame count. -/
theorem observerStep_advances_frame (s : ObserverState) (n : Nat) :
    (observerStep s n).frame = s.frame + 1 := by
  simp [observerStep]

/-- step never decreases entity count. -/
theorem observerStep_entities_nondecreasing (s : ObserverState) (n : Nat) :
    s.entities ≤ (observerStep s n).entities := by
  simp [observerStep, Nat.le_add_right]

-- ---------------------------------------------------------------------------
-- § 4  Player model
-- ---------------------------------------------------------------------------

/-- CH_PLAYER command codes, matching fabric_client.gd send_player_input. -/
inductive PlayerCmd
  | heartbeat   -- cmd=0: XR head-pose position update
  | spawnJelly  -- cmd=1: spawn jellyfish entity
  | strokeKnot  -- cmd=3: pen stroke knot
  deriving DecidableEq, Repr

/-- The low byte of payload[0] that the zone server demultiplexes on. -/
def cmdByte : PlayerCmd → Nat
  | .heartbeat  => 0
  | .spawnJelly => 1
  | .strokeKnot => 3

/-- All command codes are distinct — the server can unambiguously demultiplex. -/
theorem cmd_heartbeat_ne_spawnJelly : cmdByte .heartbeat ≠ cmdByte .spawnJelly := by decide
theorem cmd_heartbeat_ne_strokeKnot : cmdByte .heartbeat ≠ cmdByte .strokeKnot := by decide
theorem cmd_spawnJelly_ne_strokeKnot : cmdByte .spawnJelly ≠ cmdByte .strokeKnot := by decide

/-- cmd byte fits in a single byte (< 256). -/
theorem cmdByte_fits (c : PlayerCmd) : cmdByte c < 256 := by
  cases c <;> decide

/-- A player packet is valid if its size matches PACKET_SIZE and the cmd byte
    occupies a known offset. -/
structure PlayerPacket where
  size      : Nat   -- must equal PACKET_SIZE
  cmdOffset : Nat   -- must equal PAYLOAD_OFFSET
  cmd       : Nat   -- low byte of payload[0]

def mkPlayerPacket (c : PlayerCmd) : PlayerPacket :=
  { size := PACKET_SIZE, cmdOffset := PAYLOAD_OFFSET, cmd := cmdByte c }

theorem playerPacket_size_correct (c : PlayerCmd) :
    (mkPlayerPacket c).size = PACKET_SIZE := by
  simp [mkPlayerPacket]

theorem playerPacket_cmd_at_payload_offset (c : PlayerCmd) :
    (mkPlayerPacket c).cmdOffset = PAYLOAD_OFFSET := by
  simp [mkPlayerPacket]

-- ---------------------------------------------------------------------------
-- § 5  Operator camera swing invariant
-- ---------------------------------------------------------------------------

/-- SWING_ELEVATION = 153/1000, the fixed pitch of the operator camera.
    Stored as a numerator; denominator is 1000 throughout. -/
def SWING_NUM : Nat := 153
def SWING_DEN : Nat := 1000

/-- Camera state: twist and zoom change on input; swing is always SWING_NUM. -/
structure CameraState where
  twist : Nat   -- [0, 3] representing quarters of [0, 1)
  zoom  : Nat   -- spring arm length (arbitrary units)
  swing : Nat   -- always SWING_NUM; denominator implicit SWING_DEN
  deriving Repr

def initialCamera : CameraState := { twist := 0, zoom := 400, swing := SWING_NUM }

def rotateLeft  (s : CameraState) : CameraState := { s with twist := (s.twist + 3) % 4 }
def rotateRight (s : CameraState) : CameraState := { s with twist := (s.twist + 1) % 4 }
def zoomIn      (s : CameraState) : CameraState := { s with zoom  := max s.zoom 50 - 50 }
def zoomOut     (s : CameraState) : CameraState := { s with zoom  := min s.zoom 600 + 50 }
def enterFollow (s : CameraState) : CameraState := s
def exitFollow  (s : CameraState) : CameraState := s

-- Struct update only touches the named field; swing is the third field.
-- `cases s` exposes the three fields explicitly so `rfl` reduces cleanly.

theorem rotateLeft_preserves_swing  (s : CameraState) : (rotateLeft  s).swing = s.swing := by cases s; rfl
theorem rotateRight_preserves_swing (s : CameraState) : (rotateRight s).swing = s.swing := by cases s; rfl
theorem zoomIn_preserves_swing      (s : CameraState) : (zoomIn      s).swing = s.swing := by cases s; rfl
theorem zoomOut_preserves_swing     (s : CameraState) : (zoomOut     s).swing = s.swing := by cases s; rfl
theorem enterFollow_preserves_swing (s : CameraState) : (enterFollow s).swing = s.swing := rfl
theorem exitFollow_preserves_swing  (s : CameraState) : (exitFollow  s).swing = s.swing := rfl

inductive Op | RotL | RotR | ZoomI | ZoomO | Follow | Unfollow

def applyOp (s : CameraState) : Op → CameraState
  | .RotL     => rotateLeft  s
  | .RotR     => rotateRight s
  | .ZoomI    => zoomIn      s
  | .ZoomO    => zoomOut     s
  | .Follow   => enterFollow s
  | .Unfollow => exitFollow  s

theorem applyOp_preserves_swing (s : CameraState) (op : Op) :
    (applyOp s op).swing = s.swing := by
  cases s; cases op <;> rfl

def applyOps (s : CameraState) : List Op → CameraState
  | []           => s
  | op :: rest   => applyOps (applyOp s op) rest

theorem applyOps_preserves_swing (s : CameraState) (ops : List Op) :
    (applyOps s ops).swing = s.swing := by
  induction ops generalizing s with
  | nil          => rfl
  | cons op rest ih =>
    simp only [applyOps]
    rw [ih (applyOp s op), applyOp_preserves_swing]

/-- No matter what inputs the operator gives, the camera pitch never changes. -/
theorem swing_always_swing_elevation (ops : List Op) :
    (applyOps initialCamera ops).swing = SWING_NUM := by
  rw [applyOps_preserves_swing]
  rfl
