# External Services Acceptance

Automated tests mock AI providers, Microsoft Graph, Kopia, file picker, notification APIs, Windows shell/input, Android usage stats, and real external credentials.

Real credential and device checks are manual acceptance items recorded in `docs/test-governance/manual-acceptance.csv`.

Required manual coverage:

- Outlook OAuth and read-only sync with a Microsoft account test calendar.
- Real AI provider connection, draft creation, approval, and audit evidence.
- Windows file transfer interruption recovery with hash comparison.
- Android usage stats import with usage access granted.
- Windows client task create, complete, sync, and audit verification against a local server test database.

Each run records scenario id, date, environment, evidence path, result, and follow-up issue id when failing.
