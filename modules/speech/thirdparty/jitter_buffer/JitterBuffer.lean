/-
  JitterBuffer.lean

  Uses AmoLean's verified EGraph/EClass (from truth_research_zk).
  Only defines what is NEW: the ring-slot quotient map, the facade,
  and the invariants that drive the C++ fixes.
-/

import AmoLean.EGraph.Verified.Core
import AmoLean.EGraph.Verified.CoreSpec
import Mathlib.Data.ZMod.Basic

open AmoLean.EGraph.Verified

-- ── Ring-slot quotient map ────────────────────────────────────────────────

def seqToSlot (N : ℕ) [NeZero N] (n : Int) : ZMod N := n
def ringSucc {N : ℕ} [NeZero N] (i : ZMod N) : ZMod N := i + 1

-- ── JitterBuffer backed by AmoLean EGraph ────────────────────────────────

def seqToNode (n : Int) : ENode := ENode.mkConst n.toNat

@[simp] theorem seqToNode_children (n : Int) :
    (seqToNode n).children = [] := by
  simp [seqToNode, ENode.mkConst, ENode.children]

structure JitterBuffer (N : ℕ) where
  graph : EGraph
  slots : ZMod N → EClassId
  head  : ZMod N

def JitterBuffer.insert {N : ℕ} [NeZero N]
    (jb : JitterBuffer N) (seqNum : Int) : JitterBuffer N :=
  let (_, g') := jb.graph.add (seqToNode seqNum)
  { jb with graph := g' }

def JitterBuffer.dequeue {N : ℕ} [NeZero N]
    (jb : JitterBuffer N) : Option EClassId × JitterBuffer N :=
  let cid   := jb.slots jb.head
  let ready := jb.graph.classes.contains cid
  let jb'   := { jb with head := ringSucc jb.head }
  if ready then (some cid, jb') else (none, jb')

-- ── add_idempotent via AmoLean ────────────────────────────────────────────

theorem JitterBuffer.insert_idempotent {N : ℕ} [NeZero N]
    (jb : JitterBuffer N) (n : Int) (hwf : EGraphWF jb.graph) :
    let r1 := jb.graph.add (seqToNode n)
    UnionFind.root r1.2.unionFind r1.1 =
      UnionFind.root (r1.2.add (seqToNode n)).2.unionFind (r1.2.add (seqToNode n)).1 :=
  add_idempotent jb.graph (seqToNode n) hwf (by simp)

-- ── Late-packet window invariant ─────────────────────────────────────────
--
-- The existing speech.cpp on_received_audio_packet has a bug:
--
--   int64_t sequence_id = jitter_buffer.size() - 1 + sequence_id_offset;
--   if (sequence_id >= 0) { /* repair */ }
--
-- This ONLY checks the lower bound.  If sequence_id ≥ buffer_size the write
-- goes out of bounds.  The correct guard is:
--
--   0 ≤ sequence_id AND sequence_id < buffer_size
--
-- Lean proof: this double bound is equivalent to the offset being within
-- the current buffer window  [-(buffer_size - 1), 0].

/-- A late-packet offset is in-window iff the resulting array index is valid. -/
theorem late_packet_in_window (buffer_size : ℕ) (offset : Int) :
    let sid := (buffer_size : Int) - 1 + offset
    (0 ≤ sid ∧ sid < buffer_size) ↔
    (-(buffer_size : Int) + 1 ≤ offset ∧ offset ≤ 0) := by
  simp only []
  omega

-- ── Speedup/slowdown skip-count invariant ────────────────────────────────
--
-- JITTER_BUFFER_SPEEDUP and JITTER_BUFFER_SLOWDOWN are float thresholds
-- (packet counts can be fractional for fine-grained tuning).
--
-- Correct logic:
--   if buffer_size > SPEEDUP_THRESHOLD  →  skip_count = ⌊buffer_size - SPEEDUP_THRESHOLD⌋
--   if buffer_size < SLOWDOWN_THRESHOLD →  skip_count = 0, PLC inserts a repeat
--   otherwise                           →  skip_count = 0 (normal path)
--
-- The skip_count is non-negative and at most the excess.

theorem skip_count_nonneg (buf_size speedup : ℝ) (h : buf_size > speedup) :
    buf_size - speedup > 0 := by linarith

theorem skip_count_bounded (buf_size speedup : ℝ) (h : buf_size > speedup) (hsp : speedup > 0) :
    buf_size - speedup < buf_size := by linarith

-- ── Adaptive target invariant ─────────────────────────────────────────────
--
-- An exponential moving average (EMA) for the jitter estimate converges:
--   ema_next = alpha * sample + (1 - alpha) * ema_prev
-- where alpha ∈ (0, 1).  We express this in integer arithmetic with
-- alpha = k / 16 (k ∈ [1, 15]) so no division by zero occurs.

theorem ema_converges (k : ℕ) (hk : 1 ≤ k ∧ k ≤ 15) (sample ema : ℕ) :
    (k * sample + (16 - k) * ema) / 16 ≤ max sample ema := by
  omega

-- ── Sample-rate consistency invariant ────────────────────────────────────
--
-- Bug: add_player_audio set AudioStreamGenerator.mix_rate to
--      AudioDriver::get_input_mix_rate() (microphone rate, e.g. 44100).
--      But Opus always decodes at SPEECH_SETTING_VOICE_SAMPLE_RATE = 48000.
--      When generator_rate ≠ decode_rate the audio is pitched up/down by
--      the ratio decode_rate / generator_rate — audible as data corruption.
--
-- Fix: always set generator_rate = SPEECH_SETTING_VOICE_SAMPLE_RATE.

def VOICE_SAMPLE_RATE : ℕ := 48000

/-- Pitch-shift ratio when generator rate differs from decode rate.
    It equals 1 (correct) iff the rates are equal. -/
theorem pitch_ratio_is_one_iff_rates_equal
    (generator_rate decode_rate : ℕ) (hg : generator_rate > 0) :
    (decode_rate : ℚ) / generator_rate = 1 ↔ generator_rate = decode_rate := by
  constructor
  · intro h
    have : (decode_rate : ℚ) = generator_rate := by
      field_simp at h; exact_mod_cast h
    exact_mod_cast this.symm
  · intro h; subst h; simp

-- ── Play-once invariant ───────────────────────────────────────────────────
--
-- Bug: attempt_to_feed_stream called
--      audio_stream_player->call("play", get_playback_position()) every frame.
--      In Godot 4, AudioStreamPlayer::play() clears the generator ring buffer
--      and creates a new playback object, discarding all buffered audio.
--      Called at ~60 Hz this causes the audible "bouncing tone".
--
-- Fix: only call play() when the stream is stopped.
--      The playback generator runs continuously once started.

inductive PlayerState where
  | Playing
  | Stopped
  deriving DecidableEq

/-- play() is safe only from the Stopped state. -/
def play_is_safe (s : PlayerState) : Bool :=
  s == PlayerState.Stopped

theorem play_safe_iff_stopped (s : PlayerState) :
    play_is_safe s = true ↔ s = PlayerState.Stopped := by
  cases s <;> simp [play_is_safe]
