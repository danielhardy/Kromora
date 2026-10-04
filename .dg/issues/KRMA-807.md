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
updated: 2026-10-04T22:10:09.677Z
depends_on:
  - KRMA-806
blockers: []
order: zzzzq
board: product
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
