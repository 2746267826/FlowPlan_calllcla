# FlowPlan Development Constraints（2026-04-26）

## 1. Codex Command Constraint

Codex must not run `flutter` or `dart` commands in this repository.

Reason: these commands may hang in the current environment. If such validation is required, Codex should list the exact command and ask the user to run it manually.

Examples Codex must not run:

```text
flutter analyze
flutter test
flutter pub get
dart format
dart run build_runner build
```

Allowed fallback:

- Inspect files with PowerShell.
- Edit files with `apply_patch`.
- Use non-Flutter/non-Dart validation where it does not change project state.
- Clearly report which Flutter/Dart command the user should run.

## 2. P0 Code Scope

P0 code may add skeletons and local infrastructure only:

- client API boundary
- local sync metadata tables
- offline mutation queue
- conflict candidate storage
- server skeleton
- web admin skeleton

P0 code must not implement full P1 synchronization behavior, production authentication, real server persistence, or full Web admin workflows.
