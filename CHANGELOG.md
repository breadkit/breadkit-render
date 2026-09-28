# Changelog

## 0.2.0 — 2026-09-28

### Breadboard diagrams

- Draw custom left and right rail strips vertically and center rails horizontally, including named boards; show rail-mounted parts as logical edge pin maps at their declared holes.
- Show DIP functional pin names in SVG hover titles and optional printed legends; draw TO-92 transistors, trimmer potentiometers, model-specific seven-segment displays, and RGB LEDs.
- Render safe custom SVG part bodies from `render.svg` fragments in part YAML.
- Add optional right-angle routes around component bodies, flat jumper styling, a colorblind palette, validated custom palettes, and embedded fonts. `--color-by net` overrides declared wire colors.
- Highlight the exact routes reported by short-circuit annotations; mark on-board pins and offboard module targets in lint annotations, and outline large nets instead of circling every hole.
- Reduce SVG hole markup with reusable shapes and show the hole ID and net on occupied or connected hole hover.
- Add `--focus` and `--highlight-net` to emphasize selected components and nets.
- Fall back to visible colors for invalid wire and LED colors.

### Viewers and assembly guides

- Add a standalone HTML viewer with zoom, pan, layer controls, and net hover. Resolve named switch states directly and reject viewers that exceed the 256-state budget.
- Add `--state` and `--layer` for selected switch states and static layer output; hide markers and net labels from omitted layers.
- Add `--diff OLD NEW` with colored added and removed wires in a two-panel HTML viewer.
- Export printable assembly guides with bills of materials and staged diagrams, excluding nonphysical annotation wires.
- Reload watched HTML after successful changes.

### Image export

- Add optional headless Chrome PNG rendering with checked output dimensions, an optional `resvg` PNG backend, and `--render-timeout` for external raster conversion.
- Export APNG animations from assembly steps or switch states with configurable frame timing; reject switch animations above the 256-frame budget.
- Provide a source-built container image with librsvg and Noto fonts.

### Compatibility and diagnostics

- Require Breadkit 0.2.x.
- Show all circuit diagnostics on stderr, including warnings and errors when `--force` is used.

## 0.1.0 — 2026-09-26

- Initial release.
