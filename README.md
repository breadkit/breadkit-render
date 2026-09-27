<p align="center">
  <img src="site/favicon.svg" width="72" height="72" alt="">
</p>

<h1 align="center">breadkit-render</h1>

<p align="center">
  <strong>Turn breadboard circuits into clear, shareable diagrams.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/breadkit-render"><img src="https://img.shields.io/gem/v/breadkit-render.svg" alt="RubyGems version"></a>
  <a href="https://github.com/breadkit/breadkit-render/actions/workflows/ci.yml"><img src="https://github.com/breadkit/breadkit-render/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D.svg" alt="Ruby 3.3 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#example-output">Example</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#diagram-controls">Controls</a> ·
  <a href="#options">Options</a> ·
  <a href="https://breadkit.github.io/breadkit-render/">Website</a>
</p>

---

`bkrender` draws a [Breadkit](https://github.com/breadkit/breadkit) circuit
from a Ruby DSL file or resolved JSON IR. It produces SVG, PNG, and JPEG,
including diagrams with offboard modules and separately viewable wire layers.

## Example output

The [RP2040 sensor demo](https://github.com/breadkit/breadkit/blob/main/examples/05_sensor_demo.bk.rb)
uses a full-size breadboard, OLED, two SHT31 modules, switches, and IR receiver
and emitter connections.

<p align="center">
  <img src="docs/images/sensor-demo.png" width="800" alt="RP2040 sensor circuit on a full-size breadboard with OLED, two SHT31 modules, switches, and IR modules">
</p>

<p align="center">
  <a href="https://breadkit.github.io/breadkit-render/images/sensor-demo.svg">Open the interactive SVG</a>
</p>

The SVG's layer controls isolate power, I2C, switches, IR, and an optional 5 V
emitter connection. The 5 V layer is a visual alternative: remove the emitter's
3.3 V rail wire before using that connection. The receiver stays at 3.3 V.

## Quick start

Install the gem with Ruby 3.3 or newer. The compatible Breadkit core gem is
installed automatically.

```sh
gem install breadkit-render
bkrender circuit.bk.rb -o circuit.svg
```

Choose a theme, add net labels, or export a raster image:

```sh
bkrender circuit.bk.rb -o circuit.svg --theme dark --show-nets --legend
bkrender circuit.bk.rb -o circuit.png --scale 3
bkrender circuit.bk.rb -o circuit.webp --quality 85
bkrender circuit.bk.rb -o circuit.pdf
bkrender circuit.bk.rb --print-template -o board-template.pdf
bkrender circuit.bk.rb -o circuit.html --theme dark
bkrender circuit.bk.rb --view netlist --theme dark -o netlist.svg
bkrender --diff before.bk.rb after.bk.rb -o changes.html
bkrender circuit.bk.rb --format svg > circuit.svg
```

PNG, JPEG, WebP, and PDF need a conversion backend; SVG works without one.

## Netlist view

`--view netlist` draws the resolved netlist as one bus per net. Every component
and supply terminal appears under the net it actually connects to. The layout
stays readable for large circuits by keeping each net in its own row; it does
not attempt conventional electronic symbols or show the physical wire route.

<p align="center">
  <img src="docs/images/led-netlist.png" width="700" alt="Dark netlist view of a switch, resistor, LED, and USB supply grouped by four connected nets">
</p>

Use `--state SW1` to render the switch's closed-state connectivity. Netlist
view supports SVG, PNG, JPEG, WebP, and PDF. HTML, diff, and breadboard-only
controls such as `--layer`, `--rail-pattern`, and `--focus` are unavailable.

## Diagram controls

- `--rail-pattern` assigns polarity to the four rails in portrait order:
  left outer, left inner, right inner, right outer. Choose `+--+`, `+-+-`,
  `-+-+`, or `-++-`; connected wires move with their rail.
- `--orientation landscape` gives a wide view. `--crop auto` keeps the
  diagram focused on used rows; `--crop none` shows the full board.
- Circuit `layer:` values group wires and components into interactive SVG
  views. `route: :edge` keeps long wires around the outside of the board.
- Offboard modules use their own pin definitions. Pin `type:` values such as
  `power`, `ground`, `clock`, and `data` mark each connection. Resistors use
  four color bands by default; `bands: 5` selects five.
- Footprint module bodies follow the DSL's `rotate:` and `mirror:` placement
  options, including asymmetric body offsets and labeled pins.
- The built-in `sc56_11ewa` seven-segment display and `wp154a4sureqbfzgc`
  RGB LED have dedicated diagram shapes.
- Occupied holes and connected holes have different markers. LED colors accept
  CSS names and hexadecimal values such as `#6d5af0`. Hover over an occupied
  or connected hole in the SVG to see its hole ID and net.
- `--state SW1` shows the selected switch as closed and uses that state's nets.
  `--layer "2 I2C"` keeps one named layer in static SVG, PNG, JPEG, WebP, or PDF output.
- `--focus R1` dims other components and unrelated wires.
  `--highlight-net VCC` emphasizes the selected net and its connected parts.
- HTML output provides a standalone viewer with zoom, pan, layer controls, and
  net highlighting on hover. Use the State menu or click a switch to see its
  open and closed wiring states.
- `--diff OLD NEW` creates a two-panel HTML viewer. Removed wires are red in
  the old view and added wires are green in the new view; matching wires use
  their normal colors.
- `--print-template` makes a PDF with 2.54 mm hole spacing, the complete board,
  and the print palette. Print at 100% scale; the option fixes the output scale
  to 1 and requires `rsvg-convert`.

The demo was generated with:

```sh
bkrender ../breadkit/examples/05_sensor_demo.bk.rb \
  -o docs/images/sensor-demo.png --crop auto --rail-pattern '+--+' --scale 2
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `-o, --output PATH` | stdout | Write to a file; `.svg`, `.html`, `.png`, `.jpg`, `.jpeg`, `.webp`, and `.pdf` select the format. |
| `-f, --format FORMAT` | inferred or `svg` | `svg`, `html`, `png`, `jpeg`, `webp`, or `pdf`. Conflicting extensions are errors. |
| `--view NAME` | `breadboard` | `breadboard` or `netlist` (resolved net buses). |
| `--scale N` | `2` | Image and PDF output scale. |
| `--theme NAME` | `light` | `light`, `dark`, or `print`. |
| `--orientation NAME` | `portrait` | `portrait` or `landscape`. |
| `--rail-pattern PATTERN` | board layout | Set rail polarity with `+--+`, `+-+-`, `-+-+`, or `-++-`. |
| `--color-by MODE` | `wire` | Use declared wire colors or deterministic net colors. |
| `--show-nets` / `--legend` | off | Add net labels or a circuit legend. |
| `--crop MODE` | `auto` | Crop to circuit content or show the full board with `none`. |
| `--annotations FILE` | none | Overlay offenses from `bklint --format json`. |
| `--state NAME` | open switches | Render a switch state such as `SW1`; net colors and switch markers follow that state. |
| `--layer NAME` | all layers | Render one named layer, including in image and PDF output. |
| `--focus REF` | none | Emphasize one component and its connected wires. |
| `--highlight-net NAME` | none | Emphasize one net and its connected components. |
| `--diff` | off | Compare two circuit files in a standalone HTML viewer. |
| `--backend NAME` | `auto` | Use `rsvg`, `vips`, or `magick` for raster output. |
| `--background COLOR` | white | Set the JPEG background with a CSS name, `#RGB`, or `#RRGGBB`; PNG and SVG reject it. |
| `--quality N` | `90` | JPEG and WebP quality. |
| `--print-template` | off | Export a full-board PDF with physical hole spacing for 100% printing. |
| `--static` | off | Omit SVG layer controls and scripts. |
| `--force` | off | Draw resolved elements even when input has layout errors. |
| `--render-timeout SECONDS` | 60 | Limit external raster conversion time. |

## Raster backends

PNG uses the first available backend: `rsvg-convert`, `ruby-vips`, then
ImageMagick. JPEG and WebP use `ruby-vips` or ImageMagick. PDF uses
`rsvg-convert` and keeps the SVG as vector content. Install `librsvg`
(`brew install librsvg` or `apt install librsvg2-bin`) for PDF output.
`ruby-vips` needs a libvips build with SVG and WebP support for WebP output.

## Input safety

Breadkit DSL files execute Ruby code. Render only files you trust; use JSON IR
for data-only input.

## Development

The specs use examples from a sibling Breadkit checkout:

```sh
git clone https://github.com/breadkit/breadkit.git
git clone https://github.com/breadkit/breadkit-render.git
cd breadkit-render
bundle install
bundle exec rake
```

Bundler uses the sibling Breadkit checkout when it is present. Packaged
installations require Breadkit 0.2.x.

## License

breadkit-render is available under the [MIT License](LICENSE.txt).
