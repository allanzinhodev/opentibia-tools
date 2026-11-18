# Tibia Wall Tiled Mode

Aseprite's built-in **Tiled Mode** repeats the whole canvas, which works for top-down tiles but not for Tibia walls. In Tibia, a sprite bigger than 32x32 grows **up and left** from its anchor tile (the bottom-right 32x32), neighbouring tiles are always **32 px apart**, and the tile to the right or below is drawn **on top**. This extension adds a preview window that repeats your sprite (or only the selected tile) using those rules, so you can see and paint across the seams.

The draw order follows [Remere's Map Editor](https://github.com/hampusborgos/rme) (`source/map_drawer.cpp`).

## Install

1. Download [`tibia-wall-tiled.aseprite-extension`](tibia-wall-tiled.aseprite-extension) and double-click it, or use `Edit > Preferences > Extensions > Add Extension`.
2. Restart Aseprite if it was already open.

Tested with Aseprite 1.3.18.6 (Steam).

## How to use

Open `View > Tibia Wall Tiled Mode...` (you can bind a key in `Edit > Keyboard Shortcuts`).

- **Tile:** with a selection (Marquee, `M`), only the selected area is repeated, anchored at its bottom-right corner. With no selection, the whole sprite is repeated. The preview follows selection, frame and sprite changes on its own.
- **Repetir:** `Grade (X e Y)` (default), `Horizontal (X)` or `Vertical (Y)`.
- **Cópias / Deslocamento:** number of copies per axis (2–9) and the step in pixels (32 by default, whatever the sprite size).
- **Por cima:** `Tibia` (right/bottom copy on top) or `Inversa`.
- **Mostrar:** a 32x32 grid aligned to the anchor, and an outline of the central copy plus its anchor tile.
- **Lápis:** left click paints with the foreground color and right click erases, on any copy, including across seams. Each stroke goes to the active layer and is undone with a single `Ctrl+Z`.
- **Conta-gotas (eyedropper):** `Alt+click`, or click with the Eyedropper tool (`I`) active. Left click sets the foreground color and right click sets the background color. It samples what the preview shows (all visible layers). In indexed sprites it picks the matching palette index.
- **Zoom:** slider or mouse wheel. `Ajustar zoom` fits the preview to the window.

Limitations: the main canvas itself is not changed (the scripting API can't do that), the preview pencil is 1 px and ignores Aseprite's brush settings, and while you paint on the main canvas the preview updates when the stroke ends.

## Files

| File | What it is |
| --- | --- |
| `plugin.lua` | The window, events, pencil and eyedropper. |
| `core.lua` | Pure logic: layout, compositing, click-to-pixel mapping, undoable commit. |
| `package.json` | Extension manifest. |
| `tests/test_core.lua` | 31 checks run in batch mode (layout, overlap order, selection, pick, commit/undo, eyedropper, indexed). |
| `tests/test_load.lua` | Loads `plugin.lua` without a GUI and checks the command is registered. |
| `tests/gui_open.lua` | Creates a sample 64x64 wall and opens the window (needs the extension installed). |

Run the tests from this folder:

```
Aseprite.exe -b --script tests/test_core.lua
Aseprite.exe -b --script tests/test_load.lua
```

Rebuild the package after changing the code (PowerShell, from this folder):

```
Compress-Archive -Force package.json, plugin.lua, core.lua tibia-wall-tiled.zip
Move-Item -Force tibia-wall-tiled.zip tibia-wall-tiled.aseprite-extension
```
