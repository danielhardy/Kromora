---
id: KRMA-807
title: "Prepare App Store Connect submission material: privacy answers, review notes, metadata"
type: task
status: done
priority: medium
verification_agent: claude
human_review_required: false
verification_model: sonnet
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Document contains every section; claims cite repo files or are marked Human to provide/confirm
      result: pass
      notes: All scoped sections present; citations checked against Base.xcconfig, Info.plist, entitlements, sample manifest, sandbox audit, LOOKS.md, ONBOARDING.md, APP_STORE_ACCEPTANCE.md, LICENSE.
    - criterion: Privacy answer supported by code/partner audit without relying on PrivacyInfo.xcprivacy; encryption answer matches ITSAppUsesNonExemptEncryption
      result: pass
      notes: No URLSession/network calls in Sources; only SHA256 hashing via CryptoKit, no AES/SecKey/etc. ITSAppUsesNonExemptEncryption=NO is generated from Base.xcconfig (not source Info.plist), and the doc states this accurately; scripts/verify-xcode-app.sh asserts it.
    - criterion: No source or script changes, no secrets/team IDs/account details
      result: pass
      notes: Commit d770d7d1 touches only the new doc; git diff --check clean.
  checks_run:
    - Read docs/APP_STORE_SUBMISSION.md in full
    - Spot-checked 10+ citations against repo files
    - grep Sources for URLSession/NWConnection and non-hash crypto APIs
    - git diff --check HEAD~1 HEAD
    - git show --stat confirms docs-only commit
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T00:18:32.593Z
  session: 01MUUI42ATVGO0K9ZG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - appstore
  - docs
  - submission
created: 2026-10-03T19:24:48.096Z
updated: 2026-10-05T00:18:32.598Z
depends_on:
  - KRMA-806
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T00:12:44.343Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Write down everything App Store Connect will ask for that can be derived from the repository, so the human submitter only has to enter it.

## Context

Part of the Mac App Store plan (.context/2026-09-30-app-store-release-plan.md, "Mac App Store release"). Facts available: target platform and privacy scope (`Package.swift`, `Xcode/Kromora.xcodeproj/project.pbxproj`, `docs/APP_STORE_SANDBOX_AUDIT.md`), entitlements (`App/Kromora.entitlements`), product scope (`docs/PRODUCT_SCOPE.md`, `README.md`), starter Look licensing (`Sources/KromoraKit/Resources/StarterLooks/manifest.json`, About view), and `BRANDING.md`. Kromora is a native macOS local RAW photo editor with no accounts, network requests, analytics, or third-party dependencies. Do not rely on or require an app privacy manifest for App Store Connect's data-collection answers: verify those answers against the app's code and any third-party partners, and keep human-only answers explicitly marked "Human to provide" or "confirm". Apple's [App Store Connect privacy guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) says the answers describe practices across platforms; Apple's [privacy-manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) distinguishes data-collection declarations from required-reason APIs, which it lists for iOS, iPadOS, tvOS, visionOS, and watchOS, not native macOS.

## Scope

Create `docs/APP_STORE_SUBMISSION.md` containing:

- App information: name, subtitle options (30-char limit), category (Photography; secondary optional), bundle ID, copyright, support and privacy-policy URL placeholders marked "Human to provide".
- App Privacy answers ("Data Not Collected" only if the code and integrated-partner audit support it), citing the repository evidence for collection practices and the official App Store Connect guidance. These answers are independent of `PrivacyInfo.xcprivacy`; do not make a manifest a prerequisite for them. Also document the export-compliance answer with evidence from the encryption grep.
- Age-rating questionnaire answers derived from the product (no user-generated content, no web access, etc.), marked "confirm".
- App Review notes: how to exercise the app without an account (what to import, that Photos access is optional, how bundled Looks work), what each entitlement is for in one line, and the RAW formats supported (from product docs, not guessed).
- Description and keywords draft (clearly marked draft) and a screenshot plan (required Mac sizes, which screens, which sample images; samples must be redistributable, see `realworldtest/` rules in CLAUDE.md).
- A short "Human-only steps" list: Apple Developer Program, App ID, App Store Connect record, certificates/profiles, upload from Xcode Organizer, TestFlight internal group, submit for review.

## Acceptance criteria

- [ ] The document contains every section above, and every factual claim cites a repository file or is marked "Human to provide" or "confirm".
- [ ] The privacy answer is supported by the app and integrated-partner data-practice audit, without relying on `App/PrivacyInfo.xcprivacy`; the encryption answer matches `Info.plist` (`ITSAppUsesNonExemptEncryption`).
- [ ] No source or script changes, and no secrets, team IDs, or account details are included.

## Verification

- Spot-check five citations and the privacy and encryption answers against the repo and Apple's App Store Connect privacy guidance.

## Out of scope

- Anything outside the stated scope. If you find a separate defect, file a new backlog issue with the `appstore` label instead of fixing it here.
- Adding fallbacks for earlier macOS releases or Intel hardware (project rule), third-party dependencies, `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.


### Comment — codex @ 2026-10-05T00:12:41.003Z

Prepared docs/APP_STORE_SUBMISSION.md with sourced App Store information, a code- and partner-audit-backed Data Not Collected recommendation, export-compliance evidence including SHA-256 usage and the generated Info.plist setting, confirm-marked age-rating answers, review notes and entitlement purposes, RAW support caveat, metadata drafts, CC0 screenshot plan, and human-only release steps. Spot-checked repository and Apple citations, validated local links, and passed git diff --check. No source or script changes; no tests run for this documentation task. Commit: d770d7d1.

## Agent log

- 2026-10-05T00:18:32.593Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Document contains every section; claims cite repo files or are marked Human to provide/confirm (pass) — All scoped sections present; citations checked against Base.xcconfig, Info.plist, entitlements, sample manifest, sandbox audit, LOOKS.md, ONBOARDING.md, APP_STORE_ACCEPTANCE.md, LICENSE.
- [x] Privacy answer supported by code/partner audit without relying on PrivacyInfo.xcprivacy; encryption answer matches ITSAppUsesNonExemptEncryption (pass) — No URLSession/network calls in Sources; only SHA256 hashing via CryptoKit, no AES/SecKey/etc. ITSAppUsesNonExemptEncryption=NO is generated from Base.xcconfig (not source Info.plist), and the doc states this accurately; scripts/verify-xcode-app.sh asserts it.
- [x] No source or script changes, no secrets/team IDs/account details (pass) — Commit d770d7d1 touches only the new doc; git diff --check clean.
Checks run:
- Read docs/APP_STORE_SUBMISSION.md in full
- Spot-checked 10+ citations against repo files
- grep Sources for URLSession/NWConnection and non-hash crypto APIs
- git diff --check HEAD~1 HEAD
- git show --stat confirms docs-only commit
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUUI42ATVGO0K9ZG
Summary: Verified docs/APP_STORE_SUBMISSION.md: all sections present, citations spot-checked, privacy and encryption answers supported by repo evidence.
