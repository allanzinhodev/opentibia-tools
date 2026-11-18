-- Carrega plugin.lua sem GUI e confere que o comando e registrado.
local here = app.fs.filePath(debug.getinfo(1, "S").source:sub(2))
local dir = app.fs.joinPath(here, "..")
dofile(app.fs.joinPath(dir, "plugin.lua"))
local got
init({ path = dir, newCommand = function(_, t) got = t end })
print(got and got.id == "TibiaWallTiledMode" and got.group == "view_canvas_helpers"
  and "LOAD OK: " .. got.title or "LOAD FAIL")
