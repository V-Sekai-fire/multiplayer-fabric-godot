# Multiplayer Fabric MMOG — How Zones Replace Shards

Traditional MMOs split the world into shards — isolated copies with
hard player caps. When a shard fills, players queue or get bounced to
another copy of the same world. Multiplayer Fabric replaces shards
with zones: each zone owns a slice of a single continuous 30-bit
Hilbert code space (Skilling 2004). Zones share boundaries, not walls.
Entities migrate across those boundaries automatically, so the player
never sees a loading screen or a "server full" message.

The AOI (area of interest) band for a zone is derived directly from
its Hilbert range, extended by `AOI_CELLS` on each side. Neighbor
topology falls out of band overlap — no hand-authored adjacency
tables. The Hilbert curve's tighter spatial locality (cluster diameter
O(n^(1/3)) vs Morton's O(n^(2/3)), Bader 2013) means shorter AOI
bands for the same coverage, which is why interest relay can copy each
packet once per physical link instead of once per subscriber.

The forward and inverse Hilbert transforms are formally verified in
Lean 4 (`PredictiveBVH/Spatial/HilbertRoundtrip.lean`) and
code-generated to C and Rust — no hand-written bit manipulation to
audit or port.

Wire channels separate concerns cleanly: channel 0 carries Godot's
built-in RPC/spawner/synchronizer traffic, while `CH_INTEREST`,
`CH_PLAYER`, and `CH_MIGRATION` carry Fabric-specific streams.
Neither side inspects the other's packets. One pcap filter per channel
yields exactly one semantic stream, making debugging straightforward.
