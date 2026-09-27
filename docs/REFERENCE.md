# breadkit-render reference

Start with the [README](../README.md) for installation and the first SVG.
Run `bkrender --help` for the complete option list.

## Views and formats

The default breadboard view shows physical placement and jumper routes.
`--view schematic` draws components and their resolved net connections;
`--view netlist` groups terminals by net. These electrical views do not show
physical jumper positions. They accept SVG, PNG, JPEG, WebP, and PDF, but not
HTML or breadboard-only controls.

<p align="center">
  <img src="images/led-schematic.png" width="700" alt="Schematic showing a USB supply, switch, resistor, and LED connected by named nets">
</p>

<p align="center">
  <img src="images/led-netlist.png" width="700" alt="Netlist view grouping component terminals by resolved net">
</p>

Output format follows the extension passed to `-o`. SVG requires no external
converter; `--format svg` also writes to standard output. Breadboard HTML
pairs the breadboard and schematic with zoom, pan, layer controls, net
highlighting, and switch-state selection.

```sh
bkrender circuit.bk.rb --theme dark -o circuit.svg
bkrender circuit.bk.rb -o circuit.html
bkrender circuit.bk.rb --view schematic -o schematic.svg
bkrender circuit.bk.rb --view netlist -o netlist.svg
```

## Breadboard controls

| Option | Effect |
| --- | --- |
| `--rail-pattern '+--+'` | Set left outer, left inner, right inner, and right outer rail polarities. Also accepts `+-+-`, `-+-+`, and `-++-`. |
| `--orientation landscape`, `--crop none` | Arrange named boards side by side or show the complete board. |
| `--theme dark`, `--theme colorblind` | Choose a built-in palette; `colorblind` is breadboard-only. `--color-by net` colors wires by resolved net. |
| `--label-density compact`, `--legend` | Reduce body labels or print a pin legend. |
| `--wire-routing auto`, `--wire-style flat` | Route on-board wires around bodies or use thin jumper lines. |
| `--state SW1`, `--layer "2 I2C"` | Show selected switch connectivity or one named visual layer. |
| `--focus R1`, `--highlight-net VCC` | Emphasize a part or a resolved net. |
| `--annotations lint.json` | Draw targets from `bklint --format json`. |
| `--diff old.bk.rb new.bk.rb -o changes.html` | Compare added and removed wires in an HTML viewer. |

`--rail-pattern` applies to one unnamed breadboard; named-board circuits
use each board's own rail definition. A circuit's `layer:` values group
components and wires for SVG and HTML. `--watch -o diagram.html circuit.bk.rb`
updates output when the input or a nearby part file changes, and reloads an
open HTML viewer after a successful render.

A custom JSON palette inherits a built-in theme:

```json
{"base":"dark","colors":{"board":"#17251f","text":"#f3f8f4"}}
```

Pass it with `--theme-file palette.json` for breadboard output. Values are
six-digit hexadecimal colors. `--font-file font.woff2` embeds a licensed font
in a standalone SVG.

## Assembly and print output

Numbered `step` blocks in the [Breadkit DSL](https://github.com/breadkit/breadkit/blob/main/docs/dsl.md#assembly-steps)
mark assembly stages. Declarations outside steps appear in every stage.

```sh
bkrender circuit.bk.rb --step 1 -o step-1.svg
bkrender circuit.bk.rb --assembly-guide -o guide.html
bkrender circuit.bk.rb --animate steps --frame-delay 800 -o assembly.apng
bkrender circuit.bk.rb --print-template -o template.pdf
```

An assembly guide needs at least one step. APNG needs at least two frames;
`--animate states` uses switch states and rejects more than 256 frames.
`--print-template` uses 2.54 mm hole spacing and must be printed at 100%;
it requires `rsvg-convert`.

## Custom part bodies

A part definition can draw a small SVG fragment around its placed pins:

```yaml
render:
  shape: generic
  fill: "#304050"
  svg: '<circle cx="0" cy="0" r="5" fill="{{fill}}"/>'
```

The available variables are `{{ref}}`, `{{value}}`, `{{fill}}`,
`{{stroke}}`, and `{{text_color}}`. Basic SVG shapes, paths, groups, and
text are allowed; scripts, event handlers, URLs, styles, and external
references are rejected. Physical leads and pins remain visible.

## Raster backends

PNG and APNG use the first available backend: `rsvg-convert`, `resvg`,
`ruby-vips`, ImageMagick, then Chrome. JPEG and WebP use `ruby-vips` or
ImageMagick. PDF requires `rsvg-convert` and retains vector content. Install
librsvg with `brew install librsvg` or `apt install librsvg2-bin` for PDF.
Choose a backend with `--backend NAME`; `--render-timeout SECONDS` limits
external conversion. `--scale` sets raster size.

The [container image](https://github.com/breadkit/breadkit-render/pkgs/container/breadkit-render)
includes Ruby, Breadkit core, librsvg, and Noto fonts:

```sh
docker run --rm -v "$PWD:/work" ghcr.io/breadkit/breadkit-render:main \
  circuit.bk.rb --theme dark -o circuit.png
```

Pin a `sha-<render commit>` image tag for reproducible output. Ruby DSL
files execute code; render only files you trust. JSON IR is data-only.
