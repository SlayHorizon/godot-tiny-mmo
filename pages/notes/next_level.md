# Technical Note #1: Upgrading to a Byte-Level Networking Protocol for MMO Scalability

## Context

This note documents an upgrade to the networking system of an open‑source MMO built with Godot.  
Because this is open-source and based on a real experiment, the changes can be traced in the repository itself: the old main branch contains the string-based system, while a newer branch introduces the ID-based, byte-packed protocol.

To keep the demo simple and reproducible in few steps with minimal setup, the project deliberately uses a **single-tool stack**: both client and server run in Godot, with no external networking backends (e.g., Nakama, Steam), no external databases, and no separate servers in C++, Rust, Go, TS, or Python. This is not because those are bad choices, I actually think they are actual viable alternatives but because of the goal here, I prefered a setup requiring only Godot Engine.

## Abstract

In the process of building a scalable and competitive indie MMO demo,  
I redesigned our networking layer from a string‑heavy, high‑level RPC approach to an **ID‑based, byte‑packed synchronization protocol** built on `PackedByteArray`. The intent is to cut bandwidth, reduce CPU and memory overhead, and provide predictable replication suitable for MMO‑scale play. This document summarizes motivation, format choices at a high level, expected impact, and next steps.

> **Scope:** This note is conceptual and intentionally code‑free. It explains *what* changed and *why*, not implementation details.

---

## Motivation

Our earlier approach relied on string identifiers, dynamic dictionaries, and Godot’s default `MultiplayerAPI`. That worked for prototypes but became expensive at scale:

* Verbose string serialization and parsing
* Dynamic typing and reflection‑like dispatch
* Larger payloads (bandwidth cost)
* Increased CPU and memory pressure (temporary allocations, GC)

To support high CCU and real‑time synchronization, I shifted to **integer IDs** and **compact binary payloads**. I still use Godot RPC/WebSocket for transport; the key change is **owning the payload format**.

---

## Prior Approach (String‑Based Updates)

Updates were identified by strings and typically bundled into dictionaries keyed by property names (e.g., `update_animation`, `position`). While Godot ultimately serializes RPC arguments, the upstream work incurred overhead from string handling, dynamic lookups, and larger on‑wire representations.

---

## New Approach (ID‑Based, Byte‑Packed)

Updates are now represented as pairs of **property ID** and **encoded value** within a compact binary structure. A **registry** maps each property ID to a **codec** (e.g., unsigned integers, enums via ID tables, 2D vectors), yielding predictable, strongly‑typed decoding without runtime string parsing.

**Design principles**

* Deterministic decoding via fixed codecs per property
* No runtime string parsing; constant‑time integer lookups
* Uniform binary layout that compresses well
* Schema evolution: forward/backward‑friendly patterns

**Godot transport**

Internally, Godot RPC encodes arguments using its binary Variant serialization. While efficient, sending dynamic dictionaries and strings still incurs per-call allocations and lookups. By pre-packing our payloads into PackedByteArray, I eliminate that overhead and keep the message format fully under our control.

---

## Comparative Size Examples (rule of thumb)

| Event (example)              | String‑based (approx.) |               ID‑based (approx.) |
| ---------------------------- | ---------------------: | -------------------------------: |
| Animation update “run\_left” |             \~26 bytes |           \~2 bytes (ID + value) |
| Cast attack with string name |             \~39 bytes |                \~2–6 bytes (IDs) |
| Position update “30x 40y”    |            \~20+ bytes | \~8 bytes (compact numeric form) |

**Aggregate per event/entity:** \~**30–50 bytes** → \~**4–12 bytes**.

---

## Performance Impact (estimates)

* **Bandwidth:** \~**70–90%** raw size reduction.
  Example at 100k entities × 5 updates/s: **\~20 MB/s → \~3 MB/s** (≈ **17 MB/s saved**).
* **CPU:** \~**50–90%** less CPU per message (integer lookups; codec‑driven decode; no string parsing).
* **Memory:** \~**30–50%** lower peaks (fewer temporary objects; byte‑level parsing; reuse where safe).
* **Latency:** **3–5× faster** update path (e.g., \~10–25 ms → \~2–5 ms).

Note: these figures are rough order-of-magnitude projections, not benchmarks. Actual results depend on workload, entity count, update rate, and network conditions.

### Scalability (Estimated CCU)

| Metric                | String‑based |       ID‑based |          Gain |
| --------------------- | -----------: | -------------: | ------------: |
| CCU per server core   |      \~1,000 |  \~3,000–5,000 |        \~3–5× |
| Bandwidth per 10k CCU |     \~2 GBps | \~300–500 MBps |  \~≈80% lower |
| Update latency        |     10–25 ms |         2–5 ms | \~3–5× faster |



---

## Registry & Codec Overview

* **Registry**: stable mapping of `property_id → metadata (name, codec, ownership, flags)`
* **Codecs**: type‑specific encoders/decoders (e.g., `u8/u16/u32`, `bool`, `enum_id`, `string_id`, `vector2` with compact numeric encoding)
* **Compatibility**: unknown property IDs are ignored gracefully (skip/metrics), enabling forward compatibility; new properties get new IDs; reserve ID ranges for core vs. game modules.

---

## Compatibility & Versioning

* **Breaking change** from v1: string‑identified updates and dynamic dict payloads are replaced by the ID‑based, byte‑packed protocol.
* **v1 clients are not compatible** with v2 servers.
* Include a light **message/version tag** to negotiate schema where needed.

---

## Robustness & Security Considerations

* Input validation and bounds checks (lengths/varints) before allocation
* Defensive behavior for malformed data (drop/skip with metrics)
* Per‑peer rate/bandwidth limiting
* Server‑authoritative state; client inputs validated

---

## Limitations & Risks

* Requires disciplined **registry hygiene** (stable IDs, clear ownership)
* Misconfigured codecs can cause divergence; automated tests and fixtures are recommended
* Without interest management, bandwidth still scales with visible entities, even if way less

---

## What’s Next (aligned with PR)

* Improve schema versioning/tagging and compatibility checks
* Interest management for large instances/maps
* Explore client‑side prediction and rollback

---

## Acknowledgments

This design was inspired by patterns seen in large-scale MMOs that rely on compact binary replication:

- **RuneScape (2001–)**: lightweight, byte-oriented updates that worked even on dial-up.  
- **World of Warcraft (2004–)**: ID-driven, schema-controlled message formats for massive CCU.  
- **Albion Online (2017–)**: modern example of efficient serialization and interest management.

The approach here is tailored to Godot and our open-source MMO context, not a direct copy of any single system.  
Special thanks to a generous sponsor for supporting the work and making it public.

---

*Any mistakes or limitations in this design are my own.*

**Author:** SlayHorizon  
**Project:** [Godot Tiny MMO](https://github.com/SlayHorizon/godot-tiny-mmo)  
**Status:** Draft (2025-09-15)  
