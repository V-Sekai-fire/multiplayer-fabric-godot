# Multiplayer Fabric MMOG — For Sponsors

**Early.** Godot has no native MMOG networking. Unity and Unreal
outsource this to middleware (Photon, PlayFab, Pragma) that charges per
peak CCU and owns the session. V-Sekai's Multiplayer Fabric puts zone
authority, interest filtering, and entity migration into the Godot scene
tree. No competing native solution exists on the platform. The zone
partitioning, interest relay, and migration protocol are implemented.
The VR demo, asset streaming, and load testing are not done.

**10x better (not yet measured).** A 30-bit Hilbert partition is
designed to replace the coordinator, match-maker, and session database
that competing stacks require. Interest relay copies each packet once
per physical link, not once per subscriber. The target is 1,000
concurrent players across five commodity machines with 12.5% headroom,
100-byte entity state, zero orchestrator. Fan-out has not been
measured. The 1,000-player target has not been load-tested.

**Survives longer.** V-Sekai ships as a Godot module under MIT. No
per-seat fee, no runtime royalty, no vendor kill-switch. The Hilbert
transforms are formally verified in Lean 4 and code-generated to C and
Rust, so the core math does not rot when the engine upgrades. Asset
delivery is planned to use content-addressed chunk stores served by Uro
with ReBAC permissions. Uro asset streaming is not implemented yet.
