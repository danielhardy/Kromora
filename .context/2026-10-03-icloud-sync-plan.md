# iCloud library sync — evaluation and plan (2026-10-03)

> **Status: proposal.** This is a design and sequencing plan, not current behavior or a release
> commitment. Cloud sync is a listed post-MVP boundary in [`PRODUCT_SCOPE.md`](../docs/PRODUCT_SCOPE.md),
> so Phase 0 below starts with a product decision. Current storage authority remains
> [`STORAGE_POLICY.md`](../docs/STORAGE_POLICY.md) until a phase ships and that document is updated.
>
> **Prerequisite:** the [Mac App Store release plan](2026-09-30-app-store-release-plan.md)
> (Workstreams 0–4: sandbox audit, Xcode app target, xcconfig, usage strings, entitlements). Mac App
> Store and TestFlight are the only binary distribution channels, so this plan assumes no Developer ID,
> DMG or notarization path. The CloudKit entitlements land in that plan's `App/Kromora.entitlements`.

## 1. Goal

Run Kromora on more than one Mac signed into the same Apple Account and have the library converge
the way Apple Photos and Lightroom do:

- Imports on one Mac appear on the others: thumbnails within seconds, originals in the background.
- Ratings, flags, edits, named snapshots, virtual copies and removals propagate automatically.
- Each Mac keeps working at full speed offline. Changes reconcile on reconnect without losing work.
- A new Mac can join an existing library from iCloud without a backup/restore step.
- Optional later step: **Optimize Mac Storage**, where originals live in iCloud and download on demand.

It uses Apple frameworks only (CloudKit, Network, CryptoKit, Compression) and no third-party services.
Kromora is macOS-only today. The record design below is platform-neutral, so an iPad client could be a
later product decision. It is not part of this plan.

## 2. Executive summary

**Use CloudKit's private database driven by `CKSyncEngine`, with the package as the local source of
truth on every device. Do not put the package in iCloud Drive, and do not mirror through Core Data
or SwiftData.**

- Every Mac keeps its own complete `.kromoralibrary` package. CloudKit is the replication medium,
  not a remote filesystem. All local behavior stays as it is today: transactions, writer lease,
  recovery, backup, and the rule that the index is a projection.
- Sync works on **semantic records** (asset, culling state, edit head, Look blob, original), not on
  files. Inbound changes go through the same single serialized package writer as local edits.
- Metadata and media use **separate channels.** `CKSyncEngine` handles small metadata records in one
  zone. A separate, resumable media transfer queue moves originals and previews in a second zone,
  so a 100 MB RAW upload never delays a rating change.
- Conflicts resolve deterministically using **hybrid logical clocks (HLC)** and **revision ancestry**.
  Edit revisions are immutable, so a concurrent edit is never lost: the losing branch is kept as a
  labelled snapshot rather than overwritten by a plain last-writer-wins rule.
- Durability follows the codebase's existing approach. The outbound queue is a **projection**
  recomputed from package-vs-ledger state. Inbound records are committed to the package before the
  sync token moves forward.
- Two safety rules are non-negotiable. Sync never permanently deletes a local original outside the
  user-confirmed reclaim flow. An original is never evicted locally until iCloud has a verified copy.

The repository already anticipated this direction. [`LIBRARY_PACKAGE_PLAN.md` §2](../docs/LIBRARY_PACKAGE_PLAN.md)
rejected iCloud Documents over the package and said: *"If sync is ever revisited it should be a
CloudKit record design over this format, scoped as its own project with its own scale spike run
first."* This plan follows that instruction.

## 3. Evaluation of the current codebase

### 3.1 What is already sync-ready

| Property | Where it lives | Why it matters for sync |
| --- | --- | --- |
| Opaque random asset UUIDs | `PortablePhotoAssetID` | Globally unique without coordination; usable directly as CloudKit record names. |
| No path/inode in identity or cache keys | `PortablePhotoIdentity`, `PortablePhotoSourceFingerprint.cacheKey` | Packages on different Macs produce identical identities and cache keys (KRMA-390 acceptance test). |
| Content hash per original | `PortablePhotoSourceFingerprint.contentHash` (SHA-256) | End-to-end integrity check for downloaded originals; duplicate detection. |
| Immutable edit revisions | `PortablePackageEditRevision`, `Edits/<rev>.json` | Append-only history is conflict-friendly; concurrent edits can coexist. |
| Self-contained edits | Content-addressed `Looks/<sha256>.cube` | Look blobs are immutable and deduplicated, so they sync trivially. |
| Mask/analysis rasters are disposable | `MaskStore`, `PhotoAnalysisCache` in Caches | Large derived data never needs to sync; only recipes do (already inside `EditDocument`). |
| Tombstones retained forever | Membership `isTombstone`, `deletedRevision` | Already designed to stop a stale replica (backup) from resurrecting deletions. Same need for sync. |
| Transactional single writer | `PortablePackageTransaction`, `PortablePackageLease.withWriterMutationLock` | Inbound remote changes can be applied atomically through the existing commit path. |
| Unknown-field passthrough | `unknownJSONFields` on manifest, shard, record | Newer syncing builds can add fields without older builds deleting them. |
| Derived caches are optional | `Derived/`, index, launch hints | Each Mac rebuilds its own; none of it needs to sync. |
| One scheduler | `ImageWorkScheduler` lanes incl. `.packageIO`, `.background` | Sync I/O can be admitted below editor work without a second scheduler. |

### 3.2 Gaps sync must close

1. **Edit revision numbers are per-asset local counters** (`nextRevision = max(...) + 1` in
   `commitEditRevisionUnderWriterLock`). Two offline Macs will both create revision 7. Revisions
   need a global `revisionID` (UUID), a `parentRevisionID`, and a causal timestamp. The local
   integer can stay as the local file and ordering key.
2. **No causal or ordering metadata on mutable fields.** Rating and flag live only in the membership
   summary (`updateLibraryState` rewrites the shard and bumps `assetRevision`). There is no record of
   *when* or *where* a value was set, so concurrent changes cannot be merged deterministically.
3. **No device identity.** The lease records a device name and PID for contention messages. Nothing
   durable says which replica authored a change.
4. **Revision compaction is unaware of sync.** `PortablePackageMaintenancePolicy` keeps the newest 20
   revisions plus protected ones. It must also protect revisions that are not yet uploaded, and any
   revision that a pending remote merge still refers to.
5. **Removal and reclaim are local-only semantics.** Trash and quarantine are well designed, but
   they need explicit cross-device meaning: what happens when Mac A reclaims space while Mac B is
   offline and editing the same photo.
6. **Duplicate detection is O(library) and record-backed.** `PortablePackageImportCatalog` opens every
   asset record to build its hash map (known follow-up in `LIBRARY_SCALE_REGRESSION.md`). Sync needs a
   content-hash index that is cheap to query, both for import convergence and for dedupe review.
7. **There is no concept of an original that is not present locally.** `PortablePackageSourceReference`
   has `embedded` and a reserved `referenced`. Optimize Storage needs a third state, "present in iCloud,
   not on this Mac".
8. **Package instance identity.** The package carries `libraryID`, but a Finder copy or restored backup
   has the same `libraryID` with different contents. Sync state must bind to a specific package
   instance, otherwise a restored older package could be treated as current.
9. **Entitlements and signing.** The app has no iCloud, CloudKit or push entitlements. `swift run`
   builds have no entitlements at all, and the production Xcode app target does not exist yet (App
   Store plan Workstream 1). Sync must report "unavailable in this build" cleanly for SwiftPM runs.
   Sync also adds sandbox-sensitive behavior that the App Store plan's Workstream 0 audit must cover:
   staging downloaded originals on the package volume, the persistent bookmark to the package
   location, and device-local sync state under the sandbox container's Application Support.
10. **Product scope.** `PRODUCT_SCOPE.md` lists cloud sync as a post-MVP boundary, and
    `STORAGE_POLICY.md` says iCloud Documents sync is out of scope. Both need an explicit, recorded
    decision (ADR) before implementation.

## 4. Approaches considered

| Approach | Verdict | Reason |
| --- | --- | --- |
| **Package in iCloud Drive** (ubiquity container, `NSFileCoordinator`, `NSMetadataQuery`) | **Rejected** | ~400k–1M files at target scale. A multi-file transaction is not atomic remotely: another Mac can see a new `asset.json` before its `Edits/` file arrives. Concurrent shard writes create "conflicted copy" files. `manifest.lock` would sync across Macs, which is meaningless and harmful. The OS evicts files as dataless placeholders outside Kromora's control, so originals could disappear underneath the renderer. This is the same conclusion the package plan reached. |
| **Originals in iCloud Drive + metadata in CloudKit** | Rejected | Two consistency domains with no transactional link. Users can turn off iCloud Drive for the app separately from CloudKit. Eviction policy is outside app control. `NSMetadataQuery` struggles at 100k items. |
| **`NSPersistentCloudKitContainer` / SwiftData + CloudKit** | Rejected | It would become a second source of truth that competes with the package. Conflict handling is per-object merge policy with no ancestry. Schema constraints apply (no uniqueness, everything optional). Sync scheduling and large-binary handling are opaque. It is hard to test deterministically, and it conflicts with the "package is truth, index is projection" architecture. |
| **`NSUbiquitousKeyValueStore`** | For small preferences only | 1 MB total limit. Fine for a handful of user preferences in a later phase, never for library data. |
| **CloudKit public database / custom server** | Rejected | Wrong privacy model, and the brief rules out third parties. |
| **CloudKit private database + `CKSyncEngine` + custom media queue** | **Recommended** | Apple's current supported path for custom sync over app-owned persistence. Handles change tokens, push subscriptions, scheduling, retry/back-off, batching and account changes. The app keeps full control of storage and conflict resolution. Apple Photos uses CloudKit records, not iCloud Drive, for the same reasons. |

## 5. Target architecture

```text
 ┌──────────────────────────── Mac A ─────────────────────────────┐
 │  UI / AppViewModel ──► EditPersistenceCoordinator ──┐           │
 │                                                     ▼           │
 │                          PortableLibrarySession (single writer) │
 │                                 │  commit                ▲      │
 │                                 ▼                        │ apply│
 │   .kromoralibrary  ◄── package transaction ──────────────┘      │
 │        (truth)                  │                               │
 │                                 │ committed-change signal       │
 │                                 ▼                               │
 │  LibrarySyncCoordinator (@MainActor façade, status, policy)     │
 │        │                                   │                    │
 │        ▼                                   ▼                    │
 │  LibrarySyncEngine (actor)           MediaTransferQueue (actor) │
 │   • owns CKSyncEngine                 • originals + previews    │
 │   • record ⇄ value mapping            • resumable, verified     │
 │   • conflict resolver (pure)          • network/power aware     │
 │        │   device-local: engine state, sync ledger, HLC, inbox │
 └────────┼───────────────────────────────────┼───────────────────┘
          ▼                                   ▼
   CloudKit private DB — zone "Library-<id>"   zone "Media-<id>"
          ▲   (push via CKSyncEngine)          ▲   (on-demand fetch)
 ┌────────┼───────────────────────────────────┼───────────── Mac B ┐
 │        same components, its own package, its own ledger         │
 └──────────────────────────────────────────────────────────────────┘
```

### 5.1 Principles

1. **The package is local truth. CloudKit is a replica of semantic records.** Neither replaces the
   other. Losing iCloud data never loses local data. Losing one Mac never loses iCloud data.
2. **All writes go through one writer.** Remote changes become ordinary package transactions under
   the writer lease, on a package-I/O lane, never on the main actor.
3. **Values cross boundaries; CloudKit objects do not.** `CKRecord`, `CKAsset` and `CKSyncEngine` stay
   inside the sync actors, the same rule `CIImage` follows inside `RenderEngine`. Only `Sendable`
   values cross: `SyncAssetState`, `SyncEditRevision`, `SyncInboundBatch`, `SyncStatus`.
4. **Every queue is either a projection or committed before acknowledgement.** Outbound work is
   recomputed from package state; inbound work is committed before the change token moves.
5. **Metadata first, media second.** A new Mac can show the whole library (with previews) long
   before every original has downloaded.
6. **Editing one photo touches O(1) records.** This mirrors the existing O(1)-files rule.
7. **Sync never competes with the editor.** It yields under editor contention like the idle frame
   warmer, and pauses for Low Power Mode, serious thermal state, and expensive or constrained networks.

### 5.2 CloudKit containers and zones

- Container: `iCloud.com.last8.kromora.photo` (bundle ID from `Info.plist`). Private database only.
- **One pair of custom zones per library**, named from the package `libraryID`:
  - `Library-<libraryID>`: small, frequently changing metadata. Managed by `CKSyncEngine`, fetched
    automatically on push.
  - `Media-<libraryID>`: originals and previews (large `CKAsset`s). **Excluded from automatic fetch.**
    Fetched by record ID on demand and by background download. Uploaded by `MediaTransferQueue`.
- A zone per library supports multiple libraries later, and allows zone-wide `CKShare` if shared
  libraries are ever wanted (currently out of scope) without a format change.
- Optional third zone `History-<libraryID>` (Phase 5): older edit revisions, fetched only when the
  history browser opens for a photo, so bootstrap does not download millions of revision records.

> **Spike gate G1:** confirm on the macOS 26 SDK that `CKSyncEngine` can exclude the Media and
> History zones from automatic fetches (fetch-change scope options / `nextFetchChangesOptions`).
> Fallback: run the engine with `automaticallySync = false` and drive `fetchChanges(_:)` scoped to the
> Library zone on push, activation, wake and a timer. Under no circumstances may originals live in a
> zone that the engine fetches wholesale. A new Mac would try to download the entire library during
> its first fetch.

### 5.3 Record design

All records carry `schemaVersion` and an `hlc` (see §6.1). Sensitive fields use
`CKRecord.encryptedValues`, which gives end-to-end encryption under Advanced Data Protection. Only
fields that must be queryable or referenced are stored in plaintext.

**`Library`** (singleton in Library zone, recordName `library`)
- `libraryID`, `displayName` (encrypted), `createdAt`, `formatVersion`, `minimumReaderVersion`,
  `minimumSyncSchema`. An older build that does not meet `minimumSyncSchema` stops syncing and opens
  read-only for sync, matching the package's existing `minimumReaderVersion` behavior.

**`Asset`** (Library zone, recordName = asset UUID). One record per asset; it is the unit of change.
- Immutable import facts: `sourceFingerprint` (hash, decoder version, geometry), `originalFilename`
  and `originalExtension` (encrypted), `byteCount`, `captureDate`, camera/lens/dimensions (encrypted),
  `importedAt`, `importedByDevice`, `copyOfAssetID` (virtual copies).
- Culling state, each with its own HLC: `rating`/`ratingHLC`, `flag`/`flagHLC`, `label`/`labelHLC`.
- Membership state: `removedAt`/`removedHLC` (trash, reversible) and `reclaimedAt` (hard tombstone, final).
- **Edit head, inline:** `headRevisionID`, `headParentRevisionID`, `headHLC`, `headDevice`,
  `headDocument` (encrypted `EditDocument` JSON compressed with LZFSE; spills to a `headDocumentAsset`
  `CKAsset` above ~256 KB, e.g. heavy brush masks), `headLookHashes`, `headPresentedAspectRatio`.
- Media state: `originalUploaded` (set only after the Media record save succeeds), `previewRevisionID`.

The head edit is inline so that a new Mac bootstraps the whole library, with current edits, by
fetching **one metadata record per asset.** Rating changes upload only changed keys: the record is
rebuilt from cached system fields and only dirty keys are set, so CloudKit sends `changedKeys()`
only. Unknown keys written by a newer client are left untouched on the server.

**`EditRevision`** (History zone in Phase 5; Library zone with tight retention before that).
Immutable, recordName `<assetID>.<revisionID>`. Holds the full document, parent ID, HLC, device,
`snapshotName`, look hashes, and a `CKRecord.Reference` to the Asset. A revision is uploaded as a
history record only when it is meaningful: a named snapshot, a conflict loser, or the
end-of-editing-session head (on navigation away). It is **not** uploaded for every 250 ms
persistence checkpoint.

**`Look`** (Library zone, recordName `sha256-<hash>`). Small `CKAsset` holding cube bytes.
Immutable and content-addressed: uploaded once, never conflicts.

**`Original`** (Media zone, recordName = asset UUID). `CKAsset` holding the original bytes, plus
plaintext `contentHash` and `byteCount` for verification without downloading. Immutable. A virtual
copy has no `Original`; it resolves through `copyOfAssetID` (§6.6).

**`Preview`** (Media zone, recordName = asset UUID). A ~512 px HEIC of the **current presentation**
(edited if edited) tagged with `revisionID`, and optionally a 2048 px variant. This is derived and
rebuildable, with the same contract as the local frame stores. A stale preview is stale-compatible:
show it, then refine. The Mac that commits a new head uploads it, debounced (settled and the user
has navigated away, or 30 s idle). This is what gives a new Mac an immediately browsable grid.

**Never synced:** `manifest.lock`, `Recovery/`, `Derived/` (each Mac regenerates its own),
the local index, launch hints, Caches, CKSyncEngine state, and the sync ledger.

### 5.4 Device-local sync state

Stored under `~/Library/Application Support/Kromora/Sync/<libraryID>/<packageInstanceID>/`.
None of it is package truth, and each item has its own recovery story:

| Artifact | Content | Recovery if lost |
| --- | --- | --- |
| `Engine.state` | `CKSyncEngine.State.Serialization` (change tokens, pending changes), saved on every `.stateUpdate` event | Full refetch of the Library zone; merge is idempotent. |
| `Ledger.store` | Per record: last uploaded HLC/head revision ID, last applied server HLC, encoded CK system fields | Rebuilt by refetch: server state plus package state gives a full re-reconcile. |
| `Device.json` | `deviceID` (random UUID), display name, HLC high-water mark | New device ID; HLC restarts from wall clock plus the max of observed HLCs. |
| `Inbox/` | Optional durable staging for very large inbound batches (bootstrap) | Refetch. |
| `Media/` | Transfer-queue journal and partial downloads | Re-derived from `Asset.originalUploaded` vs local presence. |
| `Binding.json` | Package root file identity (volume UUID + file ID), `packageInstanceID`, iCloud user record ID hash | Rebinding prompt (§6.8). |

`deviceID` must never be stored in the package. A Finder copy of the package would clone it.

### 5.5 New components and where they live

| Component | Kind | Responsibility |
| --- | --- | --- |
| `HybridLogicalClock` | `Models/`, value type + small actor | Monotonic causal timestamps; persisted high-water mark. |
| `SyncRecordMapping` | `Models/`, pure functions | Package values ⇄ `SyncRecordFields` (a `Sendable` field dictionary). Only the engine actor turns fields into `CKRecord`. |
| `SyncConflictResolver` | `Models/`, pure | Field-level LWW, edit ancestry, removal/reclaim rules. Fully unit-testable. |
| `SyncLedger` | `Models/`, actor | Device-local ledger; computes the outbound diff from package summaries. |
| `LibrarySyncEngine` | `Models/`, actor | Owns `CKSyncEngine` and implements `CKSyncEngineDelegate`. Builds batches and handles events. The only place `CKRecord` exists. |
| `MediaTransferQueue` | `Models/`, actor | Original/preview upload and download with `CKModifyRecordsOperation`/`CKFetchRecordsOperation` (long-lived, QoS-tiered). Verifies SHA-256 and stages into the package via a transaction. |
| `PortableLibrarySession+RemoteApply` | `Models/` | `applyRemote(_ batch: SyncInboundBatch)`: one transaction per batch, grouped by shard so each shard is rewritten at most once per batch. |
| `LibrarySyncCoordinator` | `ViewModels/`, `@MainActor` | Enable/disable, account status, published `SyncStatus`, editor holds (§6.4), adoption of remote edits for the active photo, shutdown ordering. |
| `SyncSettingsView`, status-bar sync item, grid badges | `Views/` | UI (§8). |

`AppViewModel` stays the composition root. The coordinator is wired the same way as the other
extracted coordinators: a narrow `LibrarySyncDestination` protocol with no back-reference to the
model. Shutdown order: stop admission, flush engine state, cancel/await the media queue, then the
existing scheduler barrier, then lease release.

## 6. Correctness design

### 6.1 Clocks and causality

- **Hybrid logical clock** per device: `(physicalMillis, logicalCounter, deviceID)`. On each local
  change: `pt = max(now, last.pt)` and the counter increments if `pt` did not advance. On each
  inbound HLC, merge so it is monotonic. This tolerates clock skew between Macs. A Mac with a clock
  set an hour ahead cannot win every future conflict once others have observed its HLC, which is
  better than wall-clock LWW.
- Total order for ties: compare `(pt, counter, deviceID)` lexicographically. Every Mac produces the
  same decision.
- **Edit ancestry:** each revision carries `parentRevisionID`. When remote head R arrives and local
  head L differs:
  - R descends from L: fast-forward (adopt R).
  - L descends from R: local is newer; keep L and upload it.
  - Otherwise the edits are concurrent: the higher HLC becomes head, and the other is preserved as
    a named snapshot such as *"Edited on MacBook Pro · Oct 3, 14:02"*, carrying an
    `isConflictSnapshot` flag.
  Ancestry is checked against locally known revisions. If a parent was compacted, it is treated as
  concurrent, which is the safe direction because nothing is dropped.

### 6.2 Conflict policy

| Data | Policy |
| --- | --- |
| Rating, flag, label | Per-field LWW by HLC. Independent fields merge, so A's rating and B's flag both survive. |
| Edit head | Ancestry, then HLC (above). The loser is always kept as a snapshot. **Edits are never lost.** |
| Named snapshots, history revisions | Union (immutable records). |
| Membership add | Union (UUIDs). Same-content imports converge via §6.5. |
| Trash (`removedAt`) vs restore | LWW by HLC on removal state. Edits to a trashed asset are still accepted and kept. |
| Reclaim (hard delete) | Wins over everything once seen, but receiving Macs quarantine locally rather than delete (§6.7). |
| Look blobs, originals | Immutable, content-verified. A hash mismatch means quarantine and report, never overwrite. |
| `Library` record | LWW per field; `minimumReaderVersion`/`minimumSyncSchema` take the max. |

`CKError.serverRecordChanged` on an `Asset` save is resolved field-by-field with this table, using
the server record CloudKit returns. The merged result is applied locally and re-queued. It never
blindly overwrites.

### 6.3 Outbound pipeline

1. A package transaction commits (edit, rating, import, removal, snapshot, virtual copy). The session
   emits a value-only `CommittedChange(assetID, kinds)` after commit.
2. `LibrarySyncEngine` adds `.saveRecord(Asset/<id>)` (and `Look`/`EditRevision` where applicable)
   to the engine's pending changes. CKSyncEngine deduplicates by record ID, so a burst of edits on
   one photo collapses to one pending save.
3. In `nextRecordZoneChangeBatch`, the record provider reads **current** package state at send time,
   so only the latest head is sent, and builds the record from cached system fields with only dirty
   keys set.
4. On `.sentRecordZoneChanges`: write the ledger (uploaded HLC and new system fields). On failure,
   apply the per-error policy (§6.9).

**Durability without a fragile outbox.** A crash between package commit and the engine's
`.stateUpdate` save could drop a pending change. On every launch, and after any engine-state reset,
`SyncLedger` runs a **reconcile pass**: it compares each membership summary's sync stamp (new field,
§7.1) with the ledger's last-uploaded stamp and re-enqueues anything newer. This uses the 256 shard
reads that index building already does, so it needs zero `asset.json` reads. The outbound queue is
therefore a projection, the same as the index.

### 6.4 Inbound pipeline

1. `.fetchedRecordZoneChanges` delivers modifications and deletions.
2. The engine converts records to `SyncInboundBatch` values and resolves each against local state
   with `SyncConflictResolver` (reading summaries from the index projection and asset records only
   for edit-head conflicts).
3. **Editor holds:** if the active photo has an in-flight gesture or pending persistence, its inbound
   change is held until the gesture ends and persistence flushes. Then it is resolved as a normal
   concurrent edit. Inbound changes never interrupt a slider drag.
4. `applyRemote(batch)` commits one package transaction per batch (bounded, e.g. ≤500 assets),
   grouped by shard, on the package-I/O lane under the writer lease. It publishes index deltas
   through the existing `applyIndexDelta`, so the grid updates incrementally.
5. **Only after the commit returns** does the delegate return from `handleEvent`. The engine's next
   `.stateUpdate` (which moves the change token) is saved after that. A crash at any point replays
   the batch, and apply is idempotent because it is keyed by revision ID and HLC.
6. Ledger update for echo suppression: an applied remote change records its HLC so the reconcile
   pass does not upload it back.
7. Active photo adoption: if a remote head is adopted for the photo open in the editor, the
   coordinator publishes it through the normal document path (`applyHistoryDocument`-style). It is
   pushed onto the undo stack as a boundary, so Cmd-Z returns to the prior local state, which then
   commits as a new revision. A quiet status message names the source Mac.

### 6.5 Imports on more than one Mac

The common real-world case: the same SD card is imported on a laptop in the field and again on the
desktop at home before the laptop syncs.

**Recommendation:** in a sync-enabled library, allocate new import UUIDs deterministically as
`UUIDv5(namespace: libraryID, name: contentHash)`. Keep random UUIDs for "Import anyway" duplicates
and for virtual copies. Both Macs then produce the same asset ID. The second `Asset` and `Original`
saves get `serverRecordChanged` with an identical content hash and resolve to "already present",
with culling and edits merged by §6.2. The UUID stays opaque to every downstream consumer. Only the
allocation function changes, and identity is still never re-derived from a path or bytes after
allocation. This needs an ADR because it refines the KRMA-390 "not derived from bytes" wording.

Imports that are already random (existing libraries) never collide. For those, add a post-sync
**Duplicates review** driven by the new content-hash index (§7.1). It never auto-merges, because
both copies may carry edits.

### 6.6 Originals and virtual copies

- An `Original` is uploaded once per non-copy asset by the Mac that imported it. Upload completion
  sets `Asset.originalUploaded = true` through the metadata channel.
- Downloads are verified: CloudKit hands over a file URL, the queue streams it into transaction
  staging on the package volume while hashing, compares the result with `sourceFingerprint.contentHash`,
  and commits. A mismatch is quarantined and retried. Unverified bytes never reach `Original/`.
- A virtual copy downloads nothing extra. Locally it is materialized from its source's original with
  `clonefile` (free on APFS), as today.
  - If the source was reclaimed remotely while a live copy exists, reclaim keeps the `Original`
    record. The reclaim transaction checks for live copies.
  - If a copy created offline finds its source original gone, the Mac uploads the copy's own bytes as
    an `Original` for the copy.

### 6.7 Removal, reclaim and the "no surprise deletion" rule

- **Remove from library** syncs as `removedAt` and is reversible on any Mac. Each Mac moves the asset
  into its own `Recovery/Quarantine/` exactly as today.
- **Reclaim space** stays explicit and user-confirmed. The confirming Mac sets `reclaimedAt` on the
  `Asset` (which stays forever as a tombstone, like the membership tombstone) and deletes the
  `Original`, `Preview` and history records from CloudKit.
- **Receiving Macs never hard-delete on a remote reclaim.** They move the asset to local quarantine,
  marked "reclaimed on <device>". It is then removed by a later local reclaim, or automatically
  after a retention period (proposed 30 days). This keeps the codebase's invariant that only a
  confirmed reclaim destroys an original, and protects against a mistaken reclaim on one Mac
  destroying the only other copy.
- A reclaimed asset can never be resurrected by a stale replica: `reclaimedAt` beats any edit or
  restore regardless of HLC.

### 6.8 Package instance binding and restores

Sync state binds to `(libraryID, packageInstanceID)`:

- `packageInstanceID` is a new manifest field, regenerated by create, by verified restore (already a
  distinct operation), and by **Join from iCloud**.
- On open, the device-local `Binding.json` compares the package root's file identity and instance ID.
  - Match: normal sync.
  - Different instance with the same `libraryID` (Finder copy, Time Machine restore): discard engine
    state, run a full refetch and reconcile. Nothing is lost: server-newer wins by HLC and
    local-newer is uploaded.
  - Two different packages claiming one `libraryID` on the same Mac: ask which one syncs.
- A restored older backup is safe because HLC merge brings it forward. Its tombstones still prevent
  resurrection.

### 6.9 Error and account handling

| Condition | Behavior |
| --- | --- |
| No account / restricted | Sync off, local library fully usable, setting explains why. |
| Sign out, or switch to a different Apple Account (`.accountChange`) | Stop the engine and keep every local byte (unlike apps that wipe local data). The binding records the account; a different account leaves the library unsynced until the user chooses. |
| `quotaExceeded` | Pause uploads and show a persistent status with the storage needed. Metadata continues if possible; inbound continues. |
| `requestRateLimited`, `zoneBusy`, `serviceUnavailable` | Honor `retryAfterSeconds`. CKSyncEngine already backs off for metadata; the media queue implements the same. |
| `networkUnavailable`, expensive/constrained network (`NWPathMonitor`) | Metadata continues on constrained networks if allowed; media pauses unless the user opts in. |
| `zoneNotFound` / `userDeletedZone` (user deleted iCloud data in Settings) | Stop. Never delete local data. Offer "Upload this library to iCloud again" or "Turn off sync". |
| `serverRecordChanged` | Field merge (§6.2). |
| Asset hash mismatch on download | Quarantine, audit entry, retry from server, critical report if it persists. |
| Low Power Mode, serious thermal state, editor contention | Suspend media transfers and inbound apply batches (the apply resumes promptly when idle). |

## 7. Package format changes

All changes are **additive**, use the existing unknown-field passthrough, bump `writerVersion`, and
keep `minimumReaderVersion` unchanged, so older builds can still open the package. Ship them in
Phase 1, before any CloudKit code, so the format is stable when sync arrives.

### 7.1 Additions

| Location | Field | Purpose |
| --- | --- | --- |
| `manifest.json` | `packageInstanceID` | §6.8 binding. |
| `manifest.json` | `featureFlags["sync.v1"]` | Marks a package that has carried sync metadata (diagnostics and validation only; enabling sync stays device-local). |
| Membership summary | `ratingHLC`, `flagHLC`, `labelHLC`, `removedHLC` | Field-level merge without opening `asset.json`. |
| Membership summary | `syncStamp` (max HLC across synced fields and head) | Cheap outbound reconcile (§6.3). |
| Membership summary | `headRevisionID` | Echo suppression and ancestry fast path. |
| `asset.json` | `importedByDevice`, `importHLC` | Provenance. |
| `asset.json` source | `storage: "cloud"` (Phase 4) | Original lives in iCloud, not present locally. |
| `asset.json` | `reclaimedBy`, `reclaimedAt` | Remote reclaim quarantine state (§6.7). |
| `PortablePackageEditRevision` (schema 2) | `revisionID`, `parentRevisionID`, `hlc`, `deviceID`, `deviceName`, `isConflictSnapshot` | Global identity and ancestry (§6.1). Schema 1 revisions get a deterministic `revisionID = UUIDv5(assetID, localRevision)` on read. |
| Edit pointer | `revisionID`, `uploaded` | Compaction protection. |
| New local index column | content hash | O(1) duplicate lookup; replaces the record-opening `PortablePackageImportCatalog` scan. |

### 7.2 Behavior changes in existing code

- `commitEditRevisionUnderWriterLock`: allocate `revisionID`, record the parent (the current head),
  stamp the HLC, and update summary `syncStamp`/`headRevisionID` in the same transaction it already
  uses for `presentedAspectRatio`.
- `updateLibraryState`: stamp the per-field HLC and `syncStamp`, plus label support if labels become editable.
- Removal, restore and reclaim: stamp `removedHLC`; reclaim writes `reclaimedAt`.
- `PortablePackageMaintenancePolicy`: protect revisions that are un-uploaded, conflict snapshots, and
  the current remote head. Never compact while an inbound batch for that asset is pending.
- Import: the deterministic ID allocator (when the library is sync-enabled) and the content-hash index.
- Verified backup and restore: copy the new fields; restore regenerates `packageInstanceID`.
- Validation: new critical/rebuildable classifications. A missing `Original/` with `storage: "cloud"`
  is not a failure; with `embedded` it stays critical.

## 8. User experience

- **Settings → iCloud:** "Sync this library with iCloud" toggle; library size in iCloud; "Download
  Originals to this Mac" / "Optimize Mac Storage" (Phase 4); "Use cellular / expensive networks for
  originals"; "Pause syncing for one hour". Turning sync off never deletes anything, local or remote.
  A separate, confirmed "Remove library from iCloud" handles the remote side.
- **First Mac:** enabling sync uploads metadata first. Other Macs see the full library with previews
  within minutes; originals upload in the background with progress ("Uploading originals — 1,204 of
  8,311 · 212 GB left"). The upload is resumable across quit and relaunch, and pausable.
- **Join from iCloud** (a new Mac with no package): the welcome flow lists libraries found in iCloud
  ("Kromora Library — 8,311 photos, 412 GB"). Choosing one creates an empty package with that
  `libraryID`, fetches metadata and previews, and downloads originals per the storage setting.
- **Status bar item** (the area that already hosts mask analysis progress): Up to date · Syncing
  N changes · Uploading/Downloading originals · Paused (reason) · Offline · Needs attention.
- **Grid badges:** original not on this Mac; still uploading from another Mac; conflict snapshot present.
- **Editor:** opening a photo whose original is not local starts a high-priority download with
  progress over the synced preview, and editing unlocks when the bytes are verified. Remote edits to
  the open photo cross-fade in with a quiet message ("Updated from Mac Studio"). Conflict snapshots
  appear in the existing history browser with the device name.
- **Honesty:** the status reports partial failures the way imports do. A photo that cannot sync says
  why. Nothing is reported "Up to date" while a reconcile pass is still running.

## 9. Performance plan

### 9.1 Budgets (to be measured in the spike, not promised)

| Scenario | Target to validate |
| --- | --- |
| Rating or edit on Mac A visible on online Mac B | Typically a few seconds (push-bound). Measure p50/p95. |
| Main-actor work per inbound batch | Zero file I/O. Index delta publication only. |
| Editing one photo | 1 Asset record update (+1 history record at session end). |
| Bootstrap metadata, 10k assets | Measure records/s and wall time; first grid page as soon as the first batch is applied. |
| Bootstrap, 100k assets | Must not hold more than one batch of decoded records in memory. File descriptors bounded. |
| Original upload throughput | Adaptive concurrency (1–4); never starve visible thumbnail or editor work. |

### 9.2 Techniques

- **One metadata record per asset with the head edit inline** keeps bootstrap at ~N records instead
  of ~20N.
- **Changed-keys-only saves** from cached system fields keep rating changes tiny even when the head
  document is large.
- **Compressed documents** (LZFSE via Apple's Compression APIs) inside encrypted fields. An
  `EditDocument` is highly compressible JSON.
- **Shard-grouped apply:** one transaction per inbound batch, each touched shard rewritten once. At
  ~390 entries/shard (100k assets) this is the same cost profile as today's
  `production-mutation-reload`.
- **Scheduler integration:** new lanes `.syncApply` (package-I/O priority, below `activeEditor`) and
  `.mediaStage` (the import copy/hash tier). Network transfer runs outside the scheduler, but staging
  writes do not.
- **Media ordering:** download previews before originals; originals for the active photo, then the
  visible grid, then recency, then everything else. Upload originals in import order so the other
  Mac can edit the newest shoot first.
- **Edited previews are debounced** to editing-session end, not every revision.
- **No per-asset CloudKit query on scroll:** previews are fetched in page-sized `CKFetchRecordsOperation`
  batches keyed by the visible window (the same window `LibraryBrowsingCoordinator` already computes),
  with low-priority background prefill.

## 10. Entitlements, signing and environments

- **Distribution is Mac App Store and TestFlight only** (see the App Store release plan). There is no
  Developer ID, DMG or notarization path, so none of that signing work is needed here.
- Add to `App/Kromora.entitlements` (owned by the Xcode app target, not the SwiftPM launcher):
  `com.apple.developer.icloud-container-identifiers = [iCloud.com.last8.kromora.photo]`,
  `com.apple.developer.icloud-services = [CloudKit]`, and the push entitlement for CKSyncEngine's
  subscription (`aps-environment` comes from the provisioning profile under automatic signing).
  Do **not** add `com.apple.developer.icloud-container-environment`; that key is for Developer ID
  builds. Verify against Apple's current documentation when wiring it up.
- Enable the iCloud (CloudKit) and Push capabilities for the App ID in Xcode's Signing & Capabilities
  and create the container. Automatic signing manages the App Store profile.
- The app must call `NSApplication.registerForRemoteNotifications()` at launch when sync is enabled
  (CKSyncEngine manages the subscription itself).
- `swift run` / unsigned / ad-hoc builds: `CKContainer` is unavailable. `LibrarySyncCoordinator`
  detects this up front (no container entitlement) and reports "iCloud sync requires a signed build"
  without touching CloudKit. The SwiftPM launcher stays a development runtime; sync behavior is
  validated in the Xcode app build.
- **Environments:** Xcode Run builds use the CloudKit **Development** environment. TestFlight and App
  Store builds use **Production**, so any sync test on a TestFlight build needs the schema deployed
  to Production first.
- **Schema management:** develop in the Development environment and deploy to Production from the
  CloudKit Console before the first TestFlight build that syncs, and before each release that adds
  fields. The production schema is additive-only (types and fields cannot be removed), so record
  design is reviewed as a format decision and never changed casually. Mark the queryable index on
  `EditRevision.asset` before deploy. Iterate on Development builds until the record design settles.
- Swift 6 gate: the project forbids `@preconcurrency`, `@unchecked Sendable` and
  `nonisolated(unsafe)`. **Spike gate G2** must confirm that `CKSyncEngine`, its delegate protocol,
  `CKRecord` handling and `CKOperation` callbacks compile cleanly in Swift 6 mode under those rules,
  with CloudKit objects confined to actors. If any API forces an opt-out, raise it as a decision;
  do not silence it.

## 11. Testing strategy

Almost all sync logic must be testable **without CloudKit**, in the existing deterministic lanes.

1. **Pure unit tests (`fast` lane):** HLC monotonicity and skew; `SyncConflictResolver` truth tables
   (every row of §6.2, including ancestry fast-forward, concurrent, missing parent); record mapping
   round-trips, including unknown-field preservation; deterministic import UUIDs.
2. **`FakeCloudDatabase` (`fast` lane):** an in-memory actor that models zones, change tokens, system
   field tags, `serverRecordChanged`, partial batch failure, rate limiting, quota, zone deletion and
   account changes. `LibrarySyncEngine` takes a `SyncTransport` seam: production wraps `CKSyncEngine`
   plus the media operations, tests use the fake. The seam is a value-level protocol, so `CKRecord`
   never appears in tests.
3. **Multi-replica convergence simulation (`fast` lane, seeded):** 2–4 simulated Macs, each with a
   real temp package and session, run random operations (import, rate, edit, snapshot, copy, trash,
   restore, reclaim) under random partitions and delivery orders. After healing, assert that every
   package has identical canonical state (membership, culling, heads, snapshot sets, tombstones), that
   no edit revision was lost, and that no original was deleted outside a confirmed reclaim. Seeds are
   logged for reproduction.
4. **Crash-point tests:** reuse `PortablePackageFaultInjector` to crash between inbound commit and
   state save, between package commit and enqueue, and mid media staging. Assert replay idempotence
   and no lost outbound change after the reconcile pass.
5. **Scale tests (optional benchmark lane):** extend the KRMA-410 generator to produce 10k/100k
   inbound batches through the fake transport. Measure apply throughput, memory and index delta
   cost, and gate on zero main-actor I/O and zero `asset.json` reads during reconcile.
6. **Live CloudKit lane (opt-in, never CI):** `KROMORA_CLOUDKIT_TESTS=1` against the Development
   environment with a dedicated test Apple Account, on a signed build. It covers push latency,
   `CKAsset` limits, throughput, and account switching.
7. **Manual two-Mac matrix** (release qualification, like the display-bound captures): offline edits
   on both sides; same-card import on both; reclaim while the other Mac is offline; sign-out/switch
   account; storage full; delete iCloud data from Settings; restore an old backup on one Mac;
   Optimize Storage eviction and re-download.

## 12. Phased delivery

Each phase ships independently and leaves the product in a coherent state.

### Phase 0: decision and spike (go/no-go)

- **Prerequisite:** App Store plan Workstreams 0–4 are done, so a signed, sandboxed Xcode app target
  exists. The spike runs in that target (or a branch of it) rather than a separate throwaway app.
- Product decision to move cloud sync out of the post-MVP boundary. Write an ADR in
  `.dg/decisions/` covering CloudKit over iCloud Drive, local-first replicas, deterministic import
  UUIDs, and remote reclaim → local quarantine.
- Throwaway spike code (not merged), run as a signed, sandboxed build from the Xcode app target, that answers:
  - **G1:** zone exclusion from automatic fetch.
  - **G2:** Swift 6 strict-concurrency compatibility without opt-outs.
  - **G3:** `CKAsset` practical size limit and throughput for 25–150 MB RAWs and the largest
    supported TIFF/PSB-sized sources. Design an `OriginalChunk` fallback **only** if the limit
    requires it.
  - **G4:** bootstrap rate for 10k and 100k metadata records.
  - **G5:** push latency between two Macs.
  - **G6:** App Sandbox + CloudKit + Push work end to end under automatic signing: an Xcode Run build
    syncs against the Development environment, and an archived TestFlight build syncs against
    Production once the schema is deployed.
- Exit: recorded numbers and a go/no-go. Budgets in §9.1 are set from the measurements.

### Phase 1: sync-ready format (no CloudKit, ships alone)

- HLC, device identity, `revisionID`/`parentRevisionID`, per-field clocks, `syncStamp`,
  `packageInstanceID`, content-hash index, compaction protection, deterministic import allocator
  (dormant until sync is enabled).
- Exit: all existing lanes green; relocation/identity tests unchanged; older-build round-trip test
  proves the new fields survive and older readers still open the package.

### Phase 2: metadata sync engine (behind a developer flag)

- `SyncTransport`, `FakeCloudDatabase`, `SyncConflictResolver`, `SyncLedger`, `LibrarySyncEngine`,
  `applyRemote`, and the reconcile pass. Records: `Library`, `Asset` (culling, removal, head edit),
  `Look`.
- Exit: convergence simulation and crash-point suites green. Two signed Macs that already hold
  identical originals (restored from one backup) converge ratings and edits live.

### Phase 3: media and bootstrap (first user-visible release)

- `MediaTransferQueue`, `Original`/`Preview` records, verified download staging, Join from iCloud,
  settings UI, status bar item, grid badges, error/account handling, entitlements and provisioning,
  production schema deploy.
- Default storage mode: **Download Originals to this Mac** (full replica on every Mac).
- Exit: the manual two-Mac matrix passes; first-Mac upload is resumable across relaunch; a new Mac
  joins and edits.

### Phase 4: Optimize Mac Storage

- `storage: "cloud"` source state, LRU eviction under a user-set budget, on-demand original fetch in
  the editor and export, export batch prefetch.
- **Eviction invariant:** evict only when a metadata-only fetch of the `Original` record (desired
  keys excluding the asset) confirms matching `contentHash` and `byteCount`, `originalUploaded` is
  true, and the asset is not pinned, active, selected, or edited in the last N days.
- Exit: eviction/re-download round-trips are byte-identical by hash; export of an evicted photo
  downloads and succeeds or reports clearly.

### Phase 5: history and extras

- `History` zone with lazy per-asset fetch for the history browser; cloud-side revision retention.
- Sync of the user Looks library (`~/Pictures/Kromora Looks`) as `UserLook` records, separate from
  edit-embedded Look blobs.
- A few preferences via `NSUbiquitousKeyValueStore` (export defaults).
- Duplicates review UI for pre-sync random-ID duplicates.

### Explicitly deferred (separate product decisions)

- **Smart-preview editing without originals** (Lightroom's model). A proxy cannot faithfully drive
  `CIRAWFilter` RAW-domain controls (white balance, highlight recovery, demosaic-dependent settings),
  so edits made on a proxy could render differently from the RAW. This needs its own renderer design.
- iPad/iPhone client, shared libraries via `CKShare`, referenced (non-embedded) originals in sync.

## 13. Risks

| Risk | Mitigation |
| --- | --- |
| `CKSyncEngine` lacks a needed control (zone exclusion, batch shaping) | Gate G1 with a defined manual-fetch fallback; media is outside the engine in either case. |
| iCloud storage quota: RAW libraries are large (hundreds of GB to TB) | Clear sizing before enabling; metadata and previews still sync when originals are paused; Optimize Storage in Phase 4. |
| CloudKit rate limiting during the initial upload of a large library | Respect `retryAfterSeconds`, adaptive concurrency, long-lived operations, resumable journal. |
| Production schema is permanent | Treat record design as a format review; reserve `schemaVersion`; additive-only evolution. |
| Silent data loss from a merge bug | Immutable revisions, conflict snapshots, the convergence simulation, and the no-delete rule mean a bug produces extra snapshots, not lost edits. |
| A mistaken reclaim propagates | Receiving Macs quarantine for 30 days rather than delete. |
| Swift 6 / CloudKit sendability friction | Gate G2; confine CloudKit objects to two actors. |
| User expectation "Photos-level" polish | Phase 3 scope is explicit; Optimize Storage and history come later; status reporting is honest. |
| App Sandbox + CloudKit + TestFlight (Production environment) setup complexity | Gate G6 before Phase 1 work depends on it; the App Store plan's Xcode target lands first. |

## 14. Documentation to update when phases ship

- `PRODUCT_SCOPE.md`: move cloud sync from post-MVP boundaries into scope with stated limits.
- `STORAGE_POLICY.md`: add rows for engine state, ledger, device identity, binding, media journal,
  and CloudKit records. Revise the "iCloud Documents sync is out of scope" paragraph to say a
  package placed in iCloud Drive is still unsupported and CloudKit sync is the mechanism.
- `LIBRARY_PACKAGE_FORMAT.md`: new fields (§7.1) and edit revision schema 2.
- `APP_ARCHITECTURE.md`: the `LibrarySyncCoordinator` boundary row and shutdown order.
- `PACKAGING.md`: entitlements in `App/Kromora.entitlements`, container, automatic signing, schema
  deploy step (Development to Production) before TestFlight.
- `TESTING.md`: new lanes (convergence simulation, opt-in live CloudKit, two-Mac matrix).
- A new durable `docs/ICLOUD_SYNC.md` contract once Phase 3 ships. Retire this proposal to historical
  status in `DOCUMENTATION_AUDIT.md`.
