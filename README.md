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

`bkrender` turns [Breadkit](https://github.com/breadkit/breadkit) circuits into
breadboard, schematic, and netlist views. Export SVG, HTML, images, PDF, or
animated assembly steps.

<p align="center">
  <img src="docs/images/sensor-demo.png" width="800" alt="RP2040 sensor circuit on a full-size breadboard with OLED, two SHT31 modules, switches, and IR modules">
</p>

<p align="center">
  <a href="https://breadkit.github.io/breadkit-render/images/sensor-demo.svg">Open the interactive sensor demo</a>
</p>

## Quick start

Install with Ruby 3.3 or newer:

```sh
gem install breadkit-render
bkrender circuit.bk.rb --theme dark -o circuit.svg
```

This README follows main (0.2.0), which requires Breadkit core 0.2.x. If the
published gems are older, use sibling source checkouts:

```sh
git clone https://github.com/breadkit/breadkit.git
git clone https://github.com/breadkit/breadkit-render.git
cd breadkit-render
bundle install
bundle exec ruby exe/bkrender ../breadkit/examples/01_led_button.bk.rb -o circuit.svg
```

SVG works without a conversion backend. PNG, JPEG, WebP, PDF, and APNG need a
supported backend; see the [format and backend reference](docs/REFERENCE.md#raster-backends).

## Choose a view

```sh
bkrender circuit.bk.rb --view schematic -o schematic.svg
bkrender circuit.bk.rb --view netlist -o netlist.svg
bkrender circuit.bk.rb -o circuit.html
```

The default breadboard view shows physical placement. The schematic groups
pins by electrical connection; the netlist lists resolved nets. HTML adds
interactive inspection. See the [full command reference](docs/REFERENCE.md)
for layers, rail patterns, themes, annotations, assembly guides, animations,
and output options.

The [sensor demo source](https://github.com/breadkit/breadkit/blob/main/examples/05_sensor_demo.bk.rb)
uses an RP2040, OLED, two SHT31 modules, switches, and IR modules. Its 5 V
emitter layer is an alternative: disconnect the emitter's 3.3 V wire before
using it. Keep the receiver at 3.3 V.

Ruby DSL files execute code; render only files you trust. JSON IR is data-only.

## Development

From the sibling checkout above, run `bundle exec rake` for the local checks.

## License

[MIT](LICENSE.txt).
