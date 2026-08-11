# Solo State Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make per-track and per-peer `SOLO` button state survive app restarts (opt-out via two new settings), matching how `MUTE` state already persists.

**Architecture:** `soloed` is added to the same `ValueTree` serialization that already round-trips `muted` for `SonoAudio::ChannelGroupParams` (covers local input tracks and per-peer channel groups) and a new `soloed` field is added to `SonobusAudioProcessor::PeerStateCache` (covers the whole-peer `SOLO` button). Two new processor-level boolean settings gate whether solo values are *applied* when state is loaded — the values are always written to the state file (harmless), but only restored onto live objects if the corresponding "Remember" setting is on. This keeps the change to load-path gating only, avoiding tree surgery on the save path, which minimizes the diff for the upstream PR.

**Tech Stack:** C++17, JUCE (AudioProcessorValueTreeState, ValueTree serialization), existing SonoBus codebase conventions.

## Global Constraints

- Match the exact serialization pattern already used for `muted` in `ChannelGroupParams` — same key-naming style (`static String fooKey("foo")`), same `getValueTree()`/`setFromValueTree()` shape. Do not introduce a new persistence mechanism.
- Match the exact settings-toggle pattern already used for `mDisableKeyboardShortcuts` / `mOptionsDisableShortcutButton` in `OptionsView` — plain member-var-backed `ToggleButton` with `addListener(this)`, not an `AudioProcessorValueTreeState` parameter (these are app-level settings, not automatable plugin parameters).
- Keep the diff minimal and in the project's existing style (no unrelated refactoring, no reformatting) — this is headed for an upstream PR against the original SonoBus project.
- Default both new "Remember" settings to `true` (persistence is the desired new behavior; users who don't want it can turn it off).
- **Main Monitor Solo is out of scope** — do not touch `paramMainMonitorSolo` or anything related to it.
- No automated test suite exists in this codebase (confirmed: no test directories under `Source/`, JUCE audio app with no unit-test harness). Verification is manual build + runtime check, not automated tests. Every task's verification step is a manual, exact procedure — follow it precisely.
- Build system: CMake. First build requires `./setupcmake.sh` (one-time configure) then `./buildcmake.sh` (compile); subsequent changes only need `./buildcmake.sh`. No `build/` directory exists yet in this checkout — the first task's build step will be a full first-time build and will take a while.

---

### Task 1: Persist `soloed` in `ChannelGroupParams`

**Files:**
- Modify: `Source/ChannelGroup.h:43` (no change needed here — `bool soloed = false;` already exists, just confirming context)
- Modify: `Source/ChannelGroup.cpp:24` (add key constant near `mutedKey`)
- Modify: `Source/ChannelGroup.cpp:626-669` (`ChannelGroupParams::getValueTree()`)
- Modify: `Source/ChannelGroup.cpp:671-`  (`ChannelGroupParams::setFromValueTree()`)

**Interfaces:**
- Consumes: nothing new — `ChannelGroupParams::soloed` (`Source/ChannelGroup.h:43`) already exists as a runtime field.
- Produces: `ChannelGroupParams::getValueTree()` now includes a `soloed` property; `ChannelGroupParams::setFromValueTree()` now reads it back into `soloed`. This is consumed by Task 4 (which decides whether to keep or discard the loaded value).

- [ ] **Step 1: Add the key constant**

In `Source/ChannelGroup.cpp`, immediately after line 24 (`static String mutedKey("muted");`), add:

```cpp
static String soloedKey("soloed");
```

- [ ] **Step 2: Serialize `soloed` in `getValueTree()`**

In `Source/ChannelGroup.cpp`, inside `ChannelGroupParams::getValueTree()`, immediately after the existing line:

```cpp
    channelGroupTree.setProperty(mutedKey, muted, nullptr);
```

add:

```cpp
    channelGroupTree.setProperty(soloedKey, soloed, nullptr);
```

- [ ] **Step 3: Deserialize `soloed` in `setFromValueTree()`**

In `Source/ChannelGroup.cpp`, inside `ChannelGroupParams::setFromValueTree()`, immediately after the existing line:

```cpp
    muted = channelGroupTree.getProperty(mutedKey, muted);
```

add:

```cpp
    soloed = channelGroupTree.getProperty(soloedKey, soloed);
```

- [ ] **Step 4: Build**

Run: `cd ~/kb9gxk/sonobus && ./setupcmake.sh && ./buildcmake.sh`
Expected: build completes with no new compiler errors/warnings introduced by this change. (First build will take a long time — this compiles JUCE and all dependencies from scratch.)

- [ ] **Step 5: Commit**

```bash
cd ~/kb9gxk/sonobus
git add Source/ChannelGroup.cpp
git commit -m "Persist soloed state in ChannelGroupParams, matching muted"
```

---

### Task 2: Add whole-peer `soloed` to `PeerStateCache`

**Files:**
- Modify: `Source/SonobusPluginProcessor.h:835-853` (`PeerStateCache` struct)
- Modify: `Source/SonobusPluginProcessor.cpp:6138-6171` (`commitCacheForPeer`)
- Modify: `Source/SonobusPluginProcessor.cpp:6173-` (`findAndLoadCacheForPeer`)
- Modify: `Source/SonobusPluginProcessor.cpp:8877-8909` (`PeerStateCache::getValueTree()`)
- Modify: `Source/SonobusPluginProcessor.cpp:8911-` (`PeerStateCache::setFromValueTree()`)
- Modify: `Source/SonobusPluginProcessor.cpp` near other key constants (e.g. near line 88, where `changeQualForAllKey` is declared) — add `peerSoloedKey`

**Interfaces:**
- Consumes: `RemotePeer::soloed` (existing field, set via `setRemotePeerSoloed()`, declared in the `RemotePeer` struct in `SonobusPluginProcessor.h`).
- Produces: `PeerStateCache::soloed` (new field) — consumed by Task 4.

- [ ] **Step 1: Add the field to `PeerStateCache`**

In `Source/SonobusPluginProcessor.h`, inside the `PeerStateCache` struct (around line 852, right after `int orderPriority = -1;`), add:

```cpp
        bool soloed = false;
```

- [ ] **Step 2: Add the key constant**

In `Source/SonobusPluginProcessor.cpp`, near the other cache key constants (find `static String peerOrderPriorityKey` and add immediately after it):

```cpp
static String peerSoloedKey("peerSoloed");
```

- [ ] **Step 3: Populate it in `commitCacheForPeer`**

In `Source/SonobusPluginProcessor.cpp`, inside `commitCacheForPeer`, immediately after the existing line:

```cpp
    newcache.orderPriority = retpeer->orderPriority;
```

add:

```cpp
    newcache.soloed = retpeer->soloed;
```

- [ ] **Step 4: Restore it in `findAndLoadCacheForPeer`**

In `Source/SonobusPluginProcessor.cpp`, inside `findAndLoadCacheForPeer`, immediately after the existing line:

```cpp
        retpeer->orderPriority  = cache.orderPriority;
```

add:

```cpp
        retpeer->soloed = cache.soloed;
```

- [ ] **Step 5: Serialize it in `PeerStateCache::getValueTree()`**

In `Source/SonobusPluginProcessor.cpp`, inside `PeerStateCache::getValueTree()`, immediately after the existing line:

```cpp
    item.setProperty(peerOrderPriorityKey, orderPriority, nullptr);
```

add:

```cpp
    item.setProperty(peerSoloedKey, soloed, nullptr);
```

- [ ] **Step 6: Deserialize it in `PeerStateCache::setFromValueTree()`**

In `Source/SonobusPluginProcessor.cpp`, inside `PeerStateCache::setFromValueTree()`, immediately after the existing line:

```cpp
    orderPriority = item.getProperty(peerOrderPriorityKey, orderPriority);
```

add:

```cpp
    soloed = item.getProperty(peerSoloedKey, soloed);
```

- [ ] **Step 7: Build**

Run: `cd ~/kb9gxk/sonobus && ./buildcmake.sh`
Expected: build succeeds with no new errors/warnings.

- [ ] **Step 8: Commit**

```bash
cd ~/kb9gxk/sonobus
git add Source/SonobusPluginProcessor.h Source/SonobusPluginProcessor.cpp
git commit -m "Cache and persist whole-peer soloed state in PeerStateCache"
```

---

### Task 3: Add `Remember Local Track Solo` / `Remember Peer Solo` processor settings

**Files:**
- Modify: `Source/SonobusPluginProcessor.h:559-560` area (getter/setter pattern) and `:1021` area (member var pattern)
- Modify: `Source/SonobusPluginProcessor.cpp:88` area (key constants) and `:8515`/`:8645` area (extraTree read/write)

**Interfaces:**
- Consumes: nothing new.
- Produces: `SonobusAudioProcessor::getRememberLocalTrackSolo() const`, `setRememberLocalTrackSolo(bool)`, `getRememberPeerSolo() const`, `setRememberPeerSolo(bool)` — consumed by Task 4 (gating logic) and Task 5 (UI toggle wiring).

- [ ] **Step 1: Add member variables**

In `Source/SonobusPluginProcessor.h`, near `bool mChangingDefaultAudioCodecChangesAll = false;` (around line 1021), add:

```cpp
    bool mRememberLocalTrackSolo = true;
    bool mRememberPeerSolo = true;
```

- [ ] **Step 2: Add getters/setters**

In `Source/SonobusPluginProcessor.h`, near `setChangingDefaultAudioCodecSetsExisting`/`getChangingDefaultAudioCodecSetsExisting` (around line 559-560), add:

```cpp
    void setRememberLocalTrackSolo(bool flag) { mRememberLocalTrackSolo = flag; }
    bool getRememberLocalTrackSolo() const { return mRememberLocalTrackSolo; }
    void setRememberPeerSolo(bool flag) { mRememberPeerSolo = flag; }
    bool getRememberPeerSolo() const { return mRememberPeerSolo; }
```

- [ ] **Step 3: Add key constants**

In `Source/SonobusPluginProcessor.cpp`, immediately after the existing line:

```cpp
static String changeQualForAllKey("ChangeQualForAll");
```

add:

```cpp
static String rememberLocalTrackSoloKey("RememberLocalTrackSolo");
static String rememberPeerSoloKey("RememberPeerSolo");
```

- [ ] **Step 4: Write to `extraTree` on save**

In `Source/SonobusPluginProcessor.cpp`, inside `getStateInformationWithOptions`, immediately after the existing line:

```cpp
    extraTree.setProperty(changeQualForAllKey, mChangingDefaultAudioCodecChangesAll, nullptr);
```

add:

```cpp
    extraTree.setProperty(rememberLocalTrackSoloKey, mRememberLocalTrackSolo, nullptr);
    extraTree.setProperty(rememberPeerSoloKey, mRememberPeerSolo, nullptr);
```

- [ ] **Step 5: Read from `extraTree` on load**

In `Source/SonobusPluginProcessor.cpp`, inside `setStateInformationWithOptions` (around line 8640-8646), find this exact existing code, inside the `if (extraTree.isValid())` block:

```cpp
            bool chqual = extraTree.getProperty(changeQualForAllKey, mChangingDefaultAudioCodecChangesAll);
            setChangingDefaultAudioCodecSetsExisting(chqual);
```

Immediately after it, still inside the same `if (extraTree.isValid())` block, add:

```cpp
            mRememberLocalTrackSolo = extraTree.getProperty(rememberLocalTrackSoloKey, mRememberLocalTrackSolo);
            mRememberPeerSolo = extraTree.getProperty(rememberPeerSoloKey, mRememberPeerSolo);
```

Note: this read must happen *before* `loadPeerCacheFromState()` and the input-channel-groups load loop run (both are later in the same function), since Task 4 relies on `mRememberLocalTrackSolo`/`mRememberPeerSolo` already holding their loaded values by the time those blocks execute. Confirm this ordering holds (the `extraTree` block above is at line ~8640, before the input-channel-groups block at ~8726 and before `loadPeerCacheFromState()` is called at ~8775 — so the existing code order already satisfies this; no reordering needed).

- [ ] **Step 6: Build**

Run: `cd ~/kb9gxk/sonobus && ./buildcmake.sh`
Expected: build succeeds with no new errors/warnings.

- [ ] **Step 7: Commit**

```bash
cd ~/kb9gxk/sonobus
git add Source/SonobusPluginProcessor.h Source/SonobusPluginProcessor.cpp
git commit -m "Add Remember Local Track Solo / Remember Peer Solo settings"
```

---

### Task 4: Gate solo restoration on load

**Files:**
- Modify: `Source/SonobusPluginProcessor.cpp:8726-8743` (`setStateInformationWithOptions`, the block that loads `mInputChannelGroups` from `inputChannelGroupsTree`)
- Modify: `Source/SonobusPluginProcessor.cpp:8965-8977` (`loadPeerCacheFromState()`, called from `setStateInformationWithOptions`)

**Interfaces:**
- Consumes: `ChannelGroupParams::soloed` (Task 1), `PeerStateCache::soloed` (Task 2), `getRememberLocalTrackSolo()`/`getRememberPeerSolo()` (Task 3).
- Produces: final gated behavior — nothing downstream depends on new names here.

- [ ] **Step 1: Locate the input channel groups load loop**

In `Source/SonobusPluginProcessor.cpp`, inside `setStateInformationWithOptions` (around line 8726-8743), find this exact existing block:

```cpp
        if (includeInputGroups) {
            ValueTree inputChannelGroupsTree = mState.state.getChildWithName(inputChannelGroupsStateKey);
            if (inputChannelGroupsTree.isValid()) {
                
                mInputChannelGroupCount = inputChannelGroupsTree.getProperty(numChanGroupsKey, (int)mInputChannelGroupCount);
                
                int i = 0;
                for (auto channelGroupTree : inputChannelGroupsTree) {
                    if (!channelGroupTree.isValid()) continue;
                    if (i >= MAX_CHANGROUPS) break;
                    
                    mInputChannelGroups[i].params.setFromValueTree(channelGroupTree);
                    
                    ++i;
                }
                
            }
        }
```

Immediately after the `for` loop's closing brace, still inside the `if (inputChannelGroupsTree.isValid())` block, add:

```cpp
                if (!mRememberLocalTrackSolo) {
                    for (auto ci = 0; ci < i; ++ci) {
                        mInputChannelGroups[ci].params.soloed = false;
                    }
                }
```

(Reuse the loop's own `i`, which at this point holds the count of channel groups actually populated.)

- [ ] **Step 2: Locate the peer cache load function**

In `Source/SonobusPluginProcessor.cpp`, find `SonobusAudioProcessor::loadPeerCacheFromState()` (around line 8965-8977) — this is the function `setStateInformationWithOptions` calls (via `loadPeerCacheFromState();` around line 8775) to populate `mPeerStateCacheMap`. Its exact existing body:

```cpp
void SonobusAudioProcessor::loadPeerCacheFromState()
{
    ValueTree peerCacheMapTree = mState.state.getChildWithName(peerStateCacheMapKey);
    if (peerCacheMapTree.isValid()) {
        mPeerStateCacheMap.clear();
        for (auto child : peerCacheMapTree) {
            PeerStateCache info;
            info.setFromValueTree(child);
            mPeerStateCacheMap.insert(PeerStateCacheMap::value_type(info.name, info));
        }
    }
    
}
```

Change the loop body to gate on `mRememberPeerSolo` before inserting:

```cpp
        for (auto child : peerCacheMapTree) {
            PeerStateCache info;
            info.setFromValueTree(child);
            if (!mRememberPeerSolo) {
                info.soloed = false;
                for (auto ci = 0; ci < info.numChanGroups && ci < MAX_CHANGROUPS; ++ci) {
                    info.channelGroupParams[ci].soloed = false;
                }
            }
            mPeerStateCacheMap.insert(PeerStateCacheMap::value_type(info.name, info));
        }
```

- [ ] **Step 3: Build**

Run: `cd ~/kb9gxk/sonobus && ./buildcmake.sh`
Expected: build succeeds with no new errors/warnings.

- [ ] **Step 4: Manual verification — persistence ON (default)**

1. Launch the built standalone app (`build/SonoBus_artefacts/Release/Standalone/SonoBus` or equivalent per your platform's build output path).
2. Solo one local input track (click its `SOLO` button).
3. Quit the app fully.
4. Relaunch it.
5. Expected: that track is still shown as soloed.
6. Connect to any peer (or use a second local instance if you have one to connect to), solo that peer's whole-peer `SOLO` button.
7. Quit and relaunch.
8. Expected: that peer's `SOLO` button is still active once reconnected (matched by username, per the existing peer-cache-matching logic).

- [ ] **Step 5: Manual verification — persistence OFF**

1. In Options, turn off both new toggles (once Task 5 lands — if testing before Task 5 exists, set `mRememberLocalTrackSolo`/`mRememberPeerSolo` to `false` via a temporary debugger/manual edit, or defer this verification until after Task 5).
2. Repeat the same solo-then-restart steps as above.
3. Expected: solo state does NOT survive the restart (track/peer come back un-soloed).

- [ ] **Step 6: Commit**

```bash
cd ~/kb9gxk/sonobus
git add Source/SonobusPluginProcessor.cpp
git commit -m "Gate solo state restoration behind Remember Solo settings"
```

---

### Task 5: Add UI toggles to Options view

**Files:**
- Modify: `Source/OptionsView.h` (member declarations)
- Modify: `Source/OptionsView.cpp` (construction, layout, event handling, state sync)

**Interfaces:**
- Consumes: `processor.getRememberLocalTrackSolo()`/`setRememberLocalTrackSolo(bool)`, `processor.getRememberPeerSolo()`/`setRememberPeerSolo(bool)` (Task 3).
- Produces: nothing consumed by later tasks — this is the final UI-facing piece.

- [ ] **Step 1: Declare the two new `ToggleButton` members**

In `Source/OptionsView.h`, immediately after the existing line:

```cpp
    std::unique_ptr<ToggleButton> mOptionsDisableShortcutButton;
```

add:

```cpp
    std::unique_ptr<ToggleButton> mOptionsRememberLocalSoloButton;
    std::unique_ptr<ToggleButton> mOptionsRememberPeerSoloButton;
```

- [ ] **Step 2: Declare the two new `FlexBox` layout members**

In `Source/OptionsView.h`, immediately after the existing line:

```cpp
    FlexBox optionsDisableShortcutsBox;
```

add:

```cpp
    FlexBox optionsRememberLocalSoloBox;
    FlexBox optionsRememberPeerSoloBox;
```

- [ ] **Step 3: Construct the buttons**

In `Source/OptionsView.cpp`, immediately after the existing line:

```cpp
    mOptionsDisableShortcutButton = std::make_unique<ToggleButton>(TRANS("Disable keyboard shortcuts"));
    mOptionsDisableShortcutButton->addListener(this);
```

add:

```cpp
    mOptionsRememberLocalSoloButton = std::make_unique<ToggleButton>(TRANS("Remember Local Track Solo"));
    mOptionsRememberLocalSoloButton->addListener(this);

    mOptionsRememberPeerSoloButton = std::make_unique<ToggleButton>(TRANS("Remember Peer Solo"));
    mOptionsRememberPeerSoloButton->addListener(this);
```

- [ ] **Step 4: Make the buttons visible**

In `Source/OptionsView.cpp`, immediately after the existing line:

```cpp
    mOptionsComponent->addAndMakeVisible(mOptionsDisableShortcutButton.get());
```

add:

```cpp
    mOptionsComponent->addAndMakeVisible(mOptionsRememberLocalSoloButton.get());
    mOptionsComponent->addAndMakeVisible(mOptionsRememberPeerSoloButton.get());
```

- [ ] **Step 5: Lay out the new rows**

In `Source/OptionsView.cpp`, inside `updateLayout()`, immediately after the existing block:

```cpp
    optionsDisableShortcutsBox.items.clear();
    optionsDisableShortcutsBox.flexDirection = FlexBox::Direction::row;
    optionsDisableShortcutsBox.items.add(FlexItem(10, 12).withFlex(0));
    optionsDisableShortcutsBox.items.add(FlexItem(180, minpassheight, *mOptionsDisableShortcutButton).withMargin(0).withFlex(1));
```

add:

```cpp
    optionsRememberLocalSoloBox.items.clear();
    optionsRememberLocalSoloBox.flexDirection = FlexBox::Direction::row;
    optionsRememberLocalSoloBox.items.add(FlexItem(10, 12).withFlex(0));
    optionsRememberLocalSoloBox.items.add(FlexItem(180, minpassheight, *mOptionsRememberLocalSoloButton).withMargin(0).withFlex(1));

    optionsRememberPeerSoloBox.items.clear();
    optionsRememberPeerSoloBox.flexDirection = FlexBox::Direction::row;
    optionsRememberPeerSoloBox.items.add(FlexItem(10, 12).withFlex(0));
    optionsRememberPeerSoloBox.items.add(FlexItem(180, minpassheight, *mOptionsRememberPeerSoloButton).withMargin(0).withFlex(1));
```

Then, in the same file, immediately after the existing line that adds `optionsDisableShortcutsBox` to the master column:

```cpp
    optionsBox.items.add(FlexItem(100, minpassheight, optionsDisableShortcutsBox).withMargin(2).withFlex(0));
```

add:

```cpp
    optionsBox.items.add(FlexItem(100, minpassheight, optionsRememberLocalSoloBox).withMargin(2).withFlex(0));
    optionsBox.items.add(FlexItem(100, minpassheight, optionsRememberPeerSoloBox).withMargin(2).withFlex(0));
```

- [ ] **Step 6: Sync toggle state from processor in `updateState()`**

In `Source/OptionsView.cpp`, inside `updateState(bool ignorecheck)`, immediately after the existing line:

```cpp
    mOptionsDisableShortcutButton->setToggleState(processor.getDisableKeyboardShortcuts(), dontSendNotification);
```

add:

```cpp
    mOptionsRememberLocalSoloButton->setToggleState(processor.getRememberLocalTrackSolo(), dontSendNotification);
    mOptionsRememberPeerSoloButton->setToggleState(processor.getRememberPeerSolo(), dontSendNotification);
```

- [ ] **Step 7: Handle clicks in `buttonClicked()`**

In `Source/OptionsView.cpp`, inside `buttonClicked(Button* buttonThatWasClicked)`, immediately after the existing block:

```cpp
    else if (buttonThatWasClicked == mOptionsDisableShortcutButton.get()) {
        bool newval = mOptionsDisableShortcutButton->getToggleState();
        processor.setDisableKeyboardShortcuts(newval);
        if (updateKeybindings) {
            updateKeybindings();
        }
    }
```

add:

```cpp
    else if (buttonThatWasClicked == mOptionsRememberLocalSoloButton.get()) {
        processor.setRememberLocalTrackSolo(mOptionsRememberLocalSoloButton->getToggleState());
    }
    else if (buttonThatWasClicked == mOptionsRememberPeerSoloButton.get()) {
        processor.setRememberPeerSolo(mOptionsRememberPeerSoloButton->getToggleState());
    }
```

- [ ] **Step 8: Build**

Run: `cd ~/kb9gxk/sonobus && ./buildcmake.sh`
Expected: build succeeds with no new errors/warnings.

- [ ] **Step 9: Manual verification**

1. Launch the app, open Options.
2. Confirm both new toggles are visible, labeled "Remember Local Track Solo" and "Remember Peer Solo", and both default to ON.
3. Turn each off, quit, relaunch, reopen Options — confirm the OFF state itself persisted (these are ordinary settings, covered by the existing `extraTree` save/load already exercised in Task 3).
4. Re-run the Task 4 Step 4/5 verification procedures now that the UI toggles exist, using the actual UI checkboxes instead of a debugger.

- [ ] **Step 10: Commit**

```bash
cd ~/kb9gxk/sonobus
git add Source/OptionsView.h Source/OptionsView.cpp
git commit -m "Add Remember Local Track Solo / Remember Peer Solo toggles to Options view"
```

---

### Task 6: Windows build verification (required before upstream PR)

**Files:** none (verification-only task).

- [ ] **Step 1: Build on Windows**

Follow the project's existing Windows build path (`setupcmakewin.sh` / `setupcmakewin32.sh` per the target architecture, then `buildcmake.sh`, per the repo's existing Windows build docs in `README.md`/`doc/`).

- [ ] **Step 2: Repeat manual verification on Windows**

Repeat Task 4 Step 4/5 and Task 5 Step 9 verification procedures on the Windows build.

- [ ] **Step 3: Confirm no regressions in adjacent behavior**

Manually confirm: `MUTE` still persists as before (unaffected by this change), Main Monitor Solo still behaves as before (out of scope, should be untouched), and normal (non-solo) settings persistence still works (gain, pan, EQ, etc. on both local tracks and peers).

- [ ] **Step 4: Ready for upstream PR**

Once Windows verification passes, the branch is ready to open as a PR against the upstream SonoBus GitHub repository. (Opening the actual PR is a separate, explicit step the user will trigger — do not open it automatically.)
