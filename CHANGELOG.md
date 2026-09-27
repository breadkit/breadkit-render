# Changelog

## Unreleased

- Allow validated custom color palettes and embedded fonts in breadboard output.
- Resolve named switch states directly and reject HTML viewers that exceed the 256-state budget.
- Render safe custom SVG part bodies from `render.svg` fragments in part YAML.
- Add optional headless Chrome PNG rendering with checked output dimensions.
- Add opt-in right-angle routes around component bodies and flat jumper styling.
- Export APNG animations from assembly steps or switch states with configurable frame timing.
- Draw TO-92 transistor and trimmer potentiometer bodies instead of generic rectangles.
- Add an optional `resvg` PNG backend and a source-built container image with librsvg and Noto fonts.
- Reject APNG switch animations that exceed the 256-frame state budget instead of silently omitting states.
- Require Breadkit 0.2.x and use a sibling core checkout during development and CI.
- Show all circuit diagnostics on stderr, including warnings and errors when `--force` is used.
- Fall back to visible colors for invalid wire and LED colors.
- Mark on-board pins and offboard module targets in lint annotations, and outline large nets instead of circling every hole.
- Reduce SVG hole markup with reusable shapes and show the hole ID and net on occupied or connected hole hover.
- Add `--state` and `--layer` for selected switch states and static layer output; hide markers and net labels from omitted layers.
- Limit external raster conversion time with `--render-timeout`.
- Draw model-specific seven-segment displays and RGB LEDs from the expanded core part catalog.
- Add `--focus` and `--highlight-net` to emphasize selected components and nets.
- Add a standalone HTML viewer with zoom, pan, layer controls, and net hover.
- Add `--diff OLD NEW` with colored added and removed wires in a two-panel HTML viewer.

## 0.1.0 — 2026-09-27

- Initial release.
