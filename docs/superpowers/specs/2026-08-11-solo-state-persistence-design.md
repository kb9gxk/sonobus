# Solo state persistence

Date: 2026-08-11
Status: Approved for implementation

## Problem

Muted state for both local input channel groups and remote peers is persisted
across app restarts and peer reconnects. Soloed state is not. This is
inconsistent and surprising: an operator who solos a track expects it to
still be soloed after a restart, the same way a muted track stays muted.

Two distinct places are affected:

1. **Local input channel groups / per-peer channel groups**
   (`SonoAudio::ChannelGroupParams`, `ChannelGroup.h`/`.cpp`): `muted` is
   serialized in `getValueTree()`/`setFromValueTree()`; `soloed` is not.
   This struct backs both the user's own input channel groups and (via
   `PeerStateCache`) each remote peer's channel groups, so the gap affects
   both.

2. **Whole-peer solo** (`RemotePeer::soloed`, set via
   `setRemotePeerSoloed()` — the per-row `SOLO` button next to each peer in
   the peer list): this field isn't part of `PeerStateCache`
   (`SonobusPluginProcessor.h`) at all, so it isn't restored even on a
   same-session drop/reconnect via the cache-matching mechanism
   (`commitCacheForPeer`/`findAndLoadCacheForPeer`), let alone a full app
   restart.

Out of scope: **Main Monitor Solo** (`paramMainMonitorSolo`) is already a
registered `AudioProcessorValueTreeState` parameter and already round-trips
through the existing state save/restore automatically. No change needed.

## Existing persistence mechanism (reused, not replaced)

- `commitCacheForPeer`/`findAndLoadCacheForPeer` already fire on real peer
  disconnect/reconnect events within a running session (matched by
  username), independent of app restart. Once `soloed` is added to
  `PeerStateCache`, both same-session reconnects and full app restarts go
  through this same path.
- The on-disk file is written via the existing JUCE standalone-app state
  save (the same pipeline that already persists `muted`, gain, pan, EQ,
  etc.) — no new persistence mechanism is introduced.

## Design

### 1. `ChannelGroupParams` (ChannelGroup.h / ChannelGroup.cpp)

Add a `soloedKey` identifier and serialize/deserialize `soloed` in
`getValueTree()`/`setFromValueTree()`, following the exact pattern already
used for `muted`. This single change covers both local input-group solo and
per-peer channel-group solo, since both reuse this struct.

### 2. `PeerStateCache` (SonobusPluginProcessor.h / .cpp)

Add a `soloed` field to the `PeerStateCache` struct. Wire it into:
- `commitCacheForPeer` — copy `retpeer->soloed` into the cache entry.
- `findAndLoadCacheForPeer` — restore `cache.soloed` onto the peer.
- `PeerStateCache::getValueTree()`/`setFromValueTree()` — serialize/
  deserialize alongside the other cached fields.

### 3. Two "remember" toggles

Two independent boolean settings, following the existing pattern used for
similar app-level toggles (e.g. `mChangingDefaultAudioCodecChangesAll`),
persisted in `extraTree` alongside the other misc settings (so the toggle
choice itself is remembered the normal way):

- `Remember Local Track Solo` — gates whether local input-channel-group
  `soloed` is written to the on-disk state.
- `Remember Peer Solo` — gates whether remote-peer `soloed` (both the
  whole-peer toggle and per-peer channel-group solo) is written to the
  on-disk state.

**Behavior:**
- In-memory / same-session drop-reconnect: solo always survives via the
  existing cache copy-by-value mechanism, unaffected by these toggles —
  exactly like gain/pan today.
- On-disk (app restart): each toggle independently gates whether `soloed`
  is included in that category's serialized `ValueTree`. When OFF, the
  field is omitted on save, so a restart resets that category to unsoloed.
  When ON, it round-trips exactly like `muted` already does. Turning a
  toggle back on later needs no migration — loads simply read the field if
  present.

## Testing plan

- Manual verification on Linux (dev machine) first: solo a local track and
  a peer, restart the app, confirm state.
- **Windows testing required before opening the upstream PR** (per user
  request) — build and manually verify the same scenarios on Windows before
  submitting.

## Out of scope

- Any change to Main Monitor Solo.
- The Rust rewrite of SonoBus (tracked separately; deferred, not part of
  this change).
