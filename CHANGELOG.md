# Changelog

## Unreleased

- Require Breadkit 0.2.x and use a sibling core checkout during development and CI.
- Show all circuit diagnostics on stderr, including warnings and errors when `--force` is used.
- Fall back to visible colors for invalid wire and LED colors.
- Mark on-board pins and offboard module targets in lint annotations, and outline large nets instead of circling every hole.
- Reduce SVG hole markup with reusable shapes and show the hole ID and net on occupied or connected hole hover.
- Add `--state` and `--layer` for selected switch states and static layer output; hide markers and net labels from omitted layers.
- Limit external raster conversion time with `--render-timeout`.
- Draw model-specific seven-segment displays and RGB LEDs from the expanded core part catalog.

## 0.1.0 — 2026-09-27

- Initial release.
