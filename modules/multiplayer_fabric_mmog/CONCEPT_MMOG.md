# Jellygrid: Zone-Based Jellyfish Energy System

Hydrozoa is a coastal research station studying bioluminescent jellyfish as a renewable energy source. The Jellygrid system guides jellyfish swarms through currents to power nodes, converting their movement into usable energy. This document outlines the technical design for a scalable multiplayer implementation where players automate jellyfish routing to sustain station operations.

---

## System Architecture

The Jellygrid consists of:

- A distributed simulation handling thousands of jellyfish entities
- Optional VR interface for current placement and monitoring
- Self-hostable infrastructure with open-source tooling
- Hilbert-coded zone boundaries for seamless transitions
- Dynamic asset streaming for performance optimization

---

## Core Components

### 1. Zone Implementation

The ocean environment divides into Hilbert-coded zones (Zone 0, Zone 1, etc.). Each zone:

- Runs as a separate server process
- Shares entity state via Multiplayer Fabric
- Uses Area of Interest bands to limit data transmission to nearby entities

### 2. Entity Migration System

Jellyfish movement between zones features:

- Lag-free boundary crossing
- Migration buffer (MIGRATION_HEADROOM = 400) to handle swarm spikes
- Performance target: 511+ jellyfish through 3-zone loops without data loss

### 3. Environmental Physics

The simulation includes:

- Rip currents that disrupt player-created flow patterns
- Predator jellyfish (Chironex fleckeri) that interact with swarms
- Bloom decay causing jellyfish expiration after 30 seconds without reaching power nodes

### 4. Power Generation

Power nodes convert jellyfish movement to energy with:

- Efficiency bonuses for synchronized bioluminescent pulses
- Overload protection triggering temporary shutdowns
- Energy output measurement in kilowatts (kW)

### 5. Asset Streaming

The Uro integration handles:

- Jellyfish meshes loaded based on proximity and swarm density
- Procedurally generated current visuals to optimize bandwidth
- Power node models that load high-detail assets only during interaction
- Per-zone biome assets for environmental variety

---

## Implementation Status

| Component        | Status      | Implementation Notes              |
| ---------------- | ----------- | --------------------------------- |
| Zone networking  | Working     | fabric_zone.cpp                   |
| Entity migration | Working     | SCENARIO_JELLYFISH_ZONE_CROSSING  |
| VR interface     | Testing     | Hand-based current placement      |
| Asset streaming  | In progress | Jellyfish meshes and biome assets |
| Power simulation | Prototype   | Custom Node3D scripts             |
| Current visuals  | Not started | Procedural generation             |

---

## Test Scenarios

### 1. Hydrozoa Core Sustainability

- Objective: Generate 10,000 kW
- Method: Guide jellyfish through 3-zone loop
- Streaming test: 1,000-entity swarm without performance drops

### 2. Bloom Defense Protocol

- Objective: Protect grid from predator jellyfish during storms
- Method: Deploy repellent fields while managing currents
- Streaming test: Dynamic predator asset loading in AOI

### 3. Infinite Bloom Challenge

- Objective: Maintain 1,000-jellyfish swarm for 5 minutes
- Method: Optimize current placement for efficiency
- Streaming test: High-detail models for close observation

---

## Reference Documents

- Sponsorship information
- Zone architecture details
- Jellyfish physics implementation (TODO_MMOG items 4, 5, 6)
- Uro streaming integration
