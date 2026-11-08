# opencode-theme

The `herder` theme for opencode v2, so opencode in Herder's agent panel looks
like the rest of the window. `herder.json` is the theme: opencode names a theme
after its file, and the opencode preset in `apps/herder` asks for `herder` by
setting `OPENCODE_CLI_CONFIG_CONTENT` for its sessions alone.

`just install` links it into `~/.config/opencode/themes/`, where opencode looks
for themes. A link, so an edit here reaches the next opencode started. Without
it opencode falls back to a theme of its own, and nothing breaks.

## What it follows

The colours come from `apps/herder/HerderKit/Sources/DesignSystem/Theme.swift`,
and change with it:

- `background.base` is `transparent`, so the pane's glass shows through, as it
  does behind Herder's own terminals. Do not give it a colour: that is the
  solid box this theme exists to remove.
- Text is `Palette.text`, `secondaryText` and `tertiaryText`. The accent is
  `Palette.violet`; links and fields are `Palette.accent`.
- Raised surfaces, borders and the gray scale are `Palette.modal`,
  `fieldGroup`, `field` and `hairline`, flattened onto the window colour.
- `syntax` is `Palette.Syntax`, colour for colour.
- Each hue's `200` step is a Herder colour; the other steps are mixed from it
  toward white (`100`) and toward the window, `#1c1c1f` (`300` to `900`).

Dark only: Herder has no light appearance.

The format is opencode v2's (`base` plus `dark`, with nine-step hues). See
<https://opencode.ai/v2/docs/cli/theme>. `just test` checks the file is
complete enough for opencode to load.
