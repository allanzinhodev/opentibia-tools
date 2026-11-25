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

### 🧱 Tibia Wall Tiled Mode

A Tiled Mode preview for Tibia walls. Aseprite's own Tiled Mode repeats the whole canvas. This extension repeats the sprite, or only the selected tile, every 32 px in X and Y, anchored at the bottom-right with the right/bottom copy on top, like the Tibia client. You can paint across the seams and pick colors with the eyedropper (`Alt+click`) right in the preview.

**Install:** double-click [`tibia-wall-tiled/tibia-wall-tiled.aseprite-extension`](tibia-wall-tiled/tibia-wall-tiled.aseprite-extension), then open `View > Tibia Wall Tiled Mode...`. Details in [`tibia-wall-tiled/README.md`](tibia-wall-tiled/README.md).

---

### Montar Outfit

Turns a Tibia outfit sprite sheet (1024x3072) into an editable file and back. The sheet holds 16 frames x 6 categories (Personagem, Addon 1, Addon 2, and the three mounted versions). Each category/frame is a 512x64 strip with North, East, South and West, each sprite followed by its mask, and two strips per row.

**Install:** Copy [`Montar Outfit.lua`](Montar%20Outfit.lua) into the folder opened by `File > Scripts > Open Scripts Folder`, then select `File > Scripts > Rescan Scripts Folder`. Tested with Aseprite 1.3.18.6.

**How to use:**

1. Open the 1024x3072 sheet and run `File > Scripts > Montar Outfit`.
2. Pick **Montar arquivo de edição** and the sheet order (**6 categorias por frame** or **16 frames por categoria**). A new 256x64 file opens with 16 frames (tags `Idle` 1-8 and `walk` 9-16), 6 layers (sprite and mask for each part, masks shown in Multiply at 90%) and 4 columns: Norte, Sul, Norte Montado, Sul Montado.
3. Edit it, then run the script again with **Montar Spritesheet** to rebuild the 1024x3072 sheet. East and West are generated from South and North (vertical flip + 90° clockwise rotation of each 64x64 cell).

---

### Gerar Mascara

Builds an outfit mask from palette colors. Pixels of the chosen colors on the active layer lose their saturation and get 10% lighter, and a copy of them is painted 64 px to the right in the mask color: yellow `#FFFF00`, green `#00FF00`, red `#FF0000` or blue `#0000FF`.

**Install:** Copy [`Gerar Mascara.lua`](Gerar%20Mascara.lua) into the folder opened by `File > Scripts > Open Scripts Folder`, then select `File > Scripts > Rescan Scripts Folder`. Works in RGB and Indexed modes. Tested with Aseprite 1.3.18.6.

**How to use:**

1. Run `File > Scripts > Gerar Mascara`. The window stays open.
2. Select colors in the palette (`Ctrl`/`Shift`+click) and click **Usar seleção da paleta**. Click a color in the window to remove it.
3. Pick the mask color and click **Aplicar**. Run it again for each part with a different mask color. **Ctrl+Z** undoes each run.

Options: lightening amount, X offset (64 by default), current frame or all frames, and mask on the same layer or on a separate layer (created if missing). Mask pixels that would fall outside the canvas are skipped and counted. In Indexed mode, missing colors are added to the palette.

---

## Requirements

- [Aseprite](https://www.aseprite.org/) (with scripting enabled)

---

## Contributing

More scripts are on the way! Feel free to open issues or submit pull requests if you have ideas or improvements.

---

## License

MIT
