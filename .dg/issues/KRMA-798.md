---
id: KRMA-798
title: Document native macOS required-reason privacy scope
type: task
status: review
priority: high
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - privacy
  - xcode
created: 2026-10-03T19:24:32.332Z
updated: 2026-10-04T22:20:18.127Z
depends_on:
  - KRMA-785
  - KRMA-796
blockers:
  - id: evt_muu87p3p_w0fobg
    type: human
    reason: "Apple’s approved file-timestamp reasons do not clearly cover Kromora’s timestamp reads and writes for its library package in Pictures and generated preview caches: C617.1 is limited to app/app-group/CloudKit containers, 3B52.1 to files the user specifically granted access to, and DDA9.1 to timestamps displayed to the user. The audit flags this scope mismatch, and declaring a reason without a fit would violate the ticket’s reason-code requirement."
    action: "Decide how to handle the package/cache timestamp uses: authorize a scope change that brings them under an Apple-approved reason, or provide a documented Apple-accepted reason for their current use; then resume KRMA-798."
    created_at: 2026-10-04T19:41:01.525Z
    resolved_at: 2026-10-04T22:01:58.110Z
    resolved_by: cli
  - id: evt_muudcd8s_h6vfaj
    type: human
    reason: "The prior blocker was resolved without recording a choice or Apple basis. The default library is created in Pictures and its derived caches use timestamps there. Apple’s listed reasons do not fit: C617.1 is container-only, 3B52.1 requires user-granted files, and DDA9.1 requires displaying timestamps. I can’t declare a reason without a fit."
    action: Authorize a code change that removes package/cache metadata calls outside an allowed scope (such as moving app-managed data into the app container or removing timestamp use), or provide Apple documentation accepting the current use; then resume KRMA-798.
    created_at: 2026-10-04T22:04:37.516Z
    resolved_at: 2026-10-04T22:05:55.262Z
    resolved_by: cli
  - id: evt_muudwj0v_cqbqfm
    type: human
    reason: The requested documentation changes and checks are complete, but this workspace grants read-only access to .git. Git staging failed to create .git/index.lock with Operation not permitted, so I cannot make the required implementation commit or hand off to review.
    action: Provide a checkout where .git is writable, or have a maintainer commit only the KRMA-798-related files from this working tree; then resume KRMA-798 so it can proceed through review.
    created_at: 2026-10-04T22:20:18.127Z
order: zzy
board: product
blocked_reason: The requested documentation changes and checks are complete, but this workspace grants read-only access to .git. Git staging failed to create .git/index.lock with Operation not permitted, so I cannot make the required implementation commit or hand off to review.
blocked_action: Provide a checkout where .git is writable, or have a maintainer commit only the KRMA-798-related files from this working tree; then resume KRMA-798 so it can proceed through review.
blocked_from_status: ready
---

## Objective

Document whether Kromora's native macOS target needs a privacy manifest for required-reason API use, and align the App Store audit and submission checklist with Apple's current platform scope. Do not add `PrivacyInfo.xcprivacy` or change package/cache storage for required-reason APIs.

## Context

Apple's [privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) covers data-collection practices on all platforms, while required-reason API declarations apply to iOS, iPadOS, tvOS, visionOS, and watchOS. Apple's [App Store Connect privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) treats App Privacy answers as a separate account of the app's data practices. Kromora targets native macOS 26 only: `Package.swift` declares `.macOS(.v26)` and the Xcode `Kromora` target supports `macosx` only.

The source audit found `UserDefaults`, file-timestamp metadata, and `ProcessInfo.systemUptime` use. Kromora's default library and derived caches are created under Pictures. Those APIs do not create a required-reason manifest obligation for the current macOS target, and the Apple-approved timestamp codes do not need to be forced to cover those macOS paths. Keep the evidence and platform boundary clear in `docs/APP_STORE_SANDBOX_AUDIT.md`.

## Scope

- Update the required-reason inventory in `docs/APP_STORE_SANDBOX_AUDIT.md` to preserve source evidence while stating that required-reason declarations do not apply to the native macOS-only target. Record the current timestamp-code limitations for future covered platforms without calling them a current Mac App Store blocker.
- Update `.context/2026-09-30-app-store-release-plan.md` and `.dg/issues/KRMA-808.md` so the release checklist reflects Apple's platform scope and separates required-reason declarations from data-collection disclosures.
- Update `.dg/issues/KRMA-807.md` so its App Store Connect privacy answer is audited against Kromora's code and any integrated partners, does not rely on an app manifest, and has no dependency on this issue.
- Update the pending Xcode bundle-verifier and packaging-guide checklists (`KRMA-799`, `KRMA-805`) so they do not reintroduce a required-reason manifest prerequisite for the native macOS target; remove the obsolete KRMA-798 dependency from KRMA-799.
- Keep privacy claims fact-based. Cite Apple's official documentation and the local `Package.swift` and Xcode target settings.

## Acceptance criteria

- [ ] The sandbox audit says native macOS file-timestamp calls are not a required-reason blocker and retains the source locations plus Apple reason-code scope for future covered platforms.
- [ ] The release plan and App Store epic no longer require a `PrivacyInfo.xcprivacy` solely for macOS required-reason APIs.
- [ ] KRMA-807's privacy answer depends on repository and partner data-practice evidence, not `App/PrivacyInfo.xcprivacy`, and its dependency on KRMA-798 is removed.
- [ ] KRMA-799 and KRMA-805 no longer require a privacy manifest for macOS required-reason APIs, and KRMA-799 no longer depends on KRMA-798.
- [ ] The local package and Xcode target settings confirm Kromora is macOS-only; Apple's official platform guidance is cited.
- [ ] No privacy manifest, package/cache code change, or App Store Connect upload is made.

## Verification

- Review Apple's official privacy-manifest and App Store Connect privacy documentation.
- Inspect `Package.swift`, `Xcode/Kromora.xcodeproj/project.pbxproj`, and `Xcode/Config/Base.xcconfig` to confirm the product supports only `macosx` with a macOS 26 deployment target; optionally confirm the effective values using `xcodebuild -showBuildSettings` when the environment permits.
- Search the audit, release plan, epic, KRMA-799, KRMA-805, and KRMA-807 for stale claims that required-reason entries or a privacy manifest are needed for the current macOS target.
- Run `dg validate` and `git diff --check`.

## Out of scope

- Creating or bundling `PrivacyInfo.xcprivacy`; changing package/cache locations or timestamp behavior; changing App Store Connect records or uploading a build.
- Adding fallbacks for earlier macOS releases or Intel hardware, third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
