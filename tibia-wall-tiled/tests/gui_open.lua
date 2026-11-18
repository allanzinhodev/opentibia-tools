-- Teste manual: cria uma parede 64x64 de exemplo e abre o Tibia Wall Tiled Mode.
-- Rodar: Aseprite.exe --script tests/gui_open.lua
local pc = app.pixelColor
local spr = Sprite(64, 64, ColorMode.RGB)
local wi = Image(64, 64, ColorMode.RGB)
for py = 31, 63 do
  local z = 63 - py
  for px = math.max(0, 32 - z), 63 - z do
    local lx = px + z - 32
    local mortar = (py % 8 == 7) or ((lx + ((py // 8) % 2) * 8) % 16 == 15)
    wi:drawPixel(px, py, mortar and pc.rgba(90, 80, 70) or pc.rgba(160, 110, 80))
  end
end
spr.cels[1].image = wi
app.command.TibiaWallTiledMode()
if app.params.select == "1" then
  spr.selection = Selection(Rectangle(32, 32, 32, 32)) -- o timer da janela deve notar
end
