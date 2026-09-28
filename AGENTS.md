# Kromora agent instructions

Kromora targets macOS 26+ on Apple Silicon only. Prefer current-platform APIs and simplicity over
backwards compatibility. Do not implement fallbacks for earlier macOS releases or Intel hardware.
Focus on exceptional code quality using the modern API, and recommend current best practices.

[`CLAUDE.md`](CLAUDE.md) is the canonical source for this repository's project, coding, and
workflow guidance. Read it before making changes; keep shared instructions there rather than
duplicating them in this file.

When working with DispatchGraph issues or handoffs, also read [`.dg/AGENTS.md`](.dg/AGENTS.md),
which adds the issue lifecycle and verification requirements. Follow the most specific applicable
repository guidance, unless it conflicts with the user's current instruction.
