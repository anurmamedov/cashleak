# Brand

## App icon

A takeaway cup with a coin on it. Coffee is the canonical small leak — the
purchase nobody regrets individually and everybody regrets in aggregate — so the
mark is the product's argument rather than a generic finance symbol.

| File | Use |
|---|---|
| `Logo-coral-1024.png` | iOS and Android app icon. White cup on coral. |
| `Logo-light-1024.png` | Favicon, web header, anything on white. Coral cup, inverted coin. |

The iOS asset catalogue holds three variants — light, dark and tinted. iOS 18+
composites the tinted one itself, so that file carries luminance only and no
hue.

## Regenerating

```bash
python3 make_icon.py
```

Draws at 4096 and downsamples to 1024, which is why the edges are clean. Colours
and geometry are constants at the top of the file.

**Don't hand-edit the PNGs.** Change the script and re-run, or the variants
drift apart.

## Colour

Coral `#D85A30` — the same value as the leak accent in the app, so the icon and
the Overview card agree. Dark variant uses `#7A2E14`.

## Rules

- The icon is square with no rounded corners. iOS masks it; baking the radius in
  produces a visible double corner.
- No transparency. App Store icons are rejected for an alpha channel.
- Never place the coral cup on a coral ground, or the white cup on white.
