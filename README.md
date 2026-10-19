# VKIntoxEffects

The effect shaders VKIntox ships with, in their own repo so they can move and
be contributed to without touching the layer.

| effect | what it does |
| --- | --- |
| [`ExponentialFog.fx`](ExponentialFog.fx) | exponential height fog. linearizes the depth buffer for ReShade's depth input settings so it holds up on Vulkan, anti-aliases silhouettes before the fog is mixed in, and leaves the skybox alone. needs a detected depth buffer |
| [`MSAA.fx`](MSAA.fx) | image-space anti-aliasing in eight passes. each pass measures the luminance spread around a pixel and blends edges along their own direction, so staircases soften while flat areas cost nothing |

Both are compiled by VKIntox's own ReShade FX compiler, not ReShade's Windows
build, and VKIntox's setup puts them in a `VKIntox` folder beside the effect
packages you install.

## writing effects for VKIntox

- effects are compiled by the compiler that lives in
  [VKIntox](https://github.com/VKIntox/VKIntox) under `src/vendor/reshade`;
  that is the dialect to target
- `ReShade.fxh` is provided by the compiler itself; no other include is
  available at runtime, so an effect has to be self-contained
- depth-based effects must honour the `RESHADE_DEPTH_INPUT_*` preprocessor
  defines; [`ExponentialFog.fx`](ExponentialFog.fx) shows the standard handling
- keep texture reads low. every effect runs on the present path, and the
  difference between five reads and a hundred is a frame budget
- the main repo's CI compiles this tree with `vkintox-shader-check`, and this
  repo runs the same check on every push and pull request, so a contribution
  is validated the same way the layer's own effects are

## license

MIT. see [LICENSE](LICENSE).
