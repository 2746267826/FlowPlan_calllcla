# Selector Policy

Web admin tests prefer accessible role and name selectors when they identify a target unambiguously. Use `data-testid` for duplicated Ant Design controls, icon-only controls, generated table actions, chart regions, modal confirmations, and drawer/tab content.

Flutter tests use stable `Key` constants from `client_flutter/lib/core/ui/app_keys.dart` and semantic labels when user accessibility also benefits.
