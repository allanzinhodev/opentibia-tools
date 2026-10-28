# Aseprite Automations for 45° Perspective Pixel Art

Automation scripts for pixel artists working with 45° perspective sprites in Aseprite — especially useful for Tibia-style game development.

---

## Scripts

### 🔄 Flip Position

In Tibia, only 2 directions are needed to cover all 4 cardinal positions — a front-facing and a back-facing sprite. The remaining two are just mirrored versions.

This script takes a file with those 2 base positions and automatically flips them, generating all 4 directions for you — saving time and keeping consistency across your sprite sheet.

**How to use:**
1. Open your sprite file in Aseprite with the 2 base positions
2. Run the script via `File > Scripts > Flip Position`
3. The flipped frames will be generated automatically

---

### Unificar Paleta

Recolor a sprite sheet using only the colors found in a reference image, or choose colors from the current palette and generate a limited number of intermediate shades.

**Install:** Copy [`unificar_paleta.lua`](unificar_paleta.lua) into the folder opened by `File > Scripts > Open Scripts Folder`, then select `File > Scripts > Rescan Scripts Folder`. This single Lua file is all you need. Tested with Aseprite 1.3.18.6.

**How to use:**

1. Open the destination sprite in **RGB** mode, select its pixel layer, and run `File > Scripts > unificar_paleta`.
2. Select the reference image in **Spritesheet fonte**. All colors used by its visible pixels are selected automatically; animated references use the first frame.
3. Click **Previa**, then **Aplicar**. The processed pixels use only the selected reference colors, preserving their original transparency. **Ctrl+Z** undoes the operation.

**Salvar paleta...** exports the selected colors as a `.gpl` palette. Choose **Paleta atual** to use the current palette instead, with controls for mixing up to three base colors, mixture proportions, and the maximum number of new shades. Both modes can process the current frame or all frames of the selected layer and respect a pixel selection.

---

## Requirements

- [Aseprite](https://www.aseprite.org/) (with scripting enabled)

---

## Contributing

More scripts are on the way! Feel free to open issues or submit pull requests if you have ideas or improvements.

---

## License

MIT
