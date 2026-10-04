---
id: KRMA-807
title: "Prepare App Store Connect submission material: privacy answers, review notes, metadata"
type: task
status: ready
priority: medium
verification_agent: claude
human_review_required: false
verification_model: sonnet
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - docs
  - submission
created: 2026-10-03T19:24:48.096Z
updated: 2026-10-03T19:25:55.489Z
depends_on:
  - KRMA-806
  - KRMA-798
blockers: []
order: zzzzq
board: product
---

## Objective

Write down everything App Store Connect will ask for that can be derived from the repository, so the human submitter only has to enter it.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Mac App Store release"). Facts available: privacy manifest (`App/PrivacyInfo.xcprivacy`), entitlements (`App/Kromora.entitlements`) and sandbox audit (`docs/APP_STORE_SANDBOX_AUDIT.md`), product scope (`docs/PRODUCT_SCOPE.md`, `README.md`), starter Look licensing (`Sources/KromoraKit/Resources/StarterLooks/manifest.json`, About view), `BRANDING.md`. Kromora is a local RAW photo editor with no accounts, no network, and no analytics. An agent must not invent claims; anything not verifiable from the repo becomes an explicit "Human to provide" item.

## Scope

Create `docs/APP_STORE_SUBMISSION.md` containing:

- App information: name, subtitle options (30-char limit), category (Photography; secondary optional), bundle ID, copyright, support and privacy-policy URL placeholders marked "Human to provide".
- App Privacy answers ("Data Not Collected" if the audit and manifest support it) with the evidence for each answer, and the export-compliance answer with the evidence from the encryption grep.
- Age-rating questionnaire answers derived from the product (no user-generated content, no web access, etc.), marked "confirm".
- App Review notes: how to exercise the app without an account (what to import, that Photos access is optional, how bundled Looks work), what each entitlement is for in one line, and the RAW formats supported (from product docs, not guessed).
- Description and keywords draft (clearly marked draft) and a screenshot plan (required Mac sizes, which screens, which sample images; samples must be redistributable, see `realworldtest/` rules in CLAUDE.md).
- A short "Human-only steps" list: Apple Developer Program, App ID, App Store Connect record, certificates/profiles, upload from Xcode Organizer, TestFlight internal group, submit for review.

## Acceptance criteria

- [ ] The document contains every section above, and every factual claim cites a repository file or is marked "Human to provide" or "confirm".
- [ ] The privacy answer and encryption answer match `App/PrivacyInfo.xcprivacy` and `Info.plist` (`ITSAppUsesNonExemptEncryption`).
- [ ] No source or script changes, and no secrets, team IDs, or account details are included.

## Verification

- Spot-check five citations and the privacy and encryption answers against the repo.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
