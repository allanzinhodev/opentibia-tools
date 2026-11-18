-- Rodar: Aseprite.exe -b [--script-param out=<pasta p/ PNGs>] --script tests/test_core.lua
local here = app.fs.filePath(debug.getinfo(1, "S").source:sub(2))
local core = dofile(app.fs.joinPath(here, "..", "core.lua"))
local out = app.params.out or app.fs.tempPath
local pc = app.pixelColor
local fails = 0
local function check(name, got, want)
  if got == want then print("ok   " .. name)
  else fails = fails + 1; print("FAIL " .. name .. ": got " .. tostring(got) .. " want " .. tostring(want)) end
end

local RED, BLUE, GREEN = pc.rgba(255,0,0), pc.rgba(0,0,255), pc.rgba(0,255,0)

-- 1) Ordem de sobreposicao e posicoes (sprite 64x64, passo 32)
local spr = Sprite(64, 64, ColorMode.RGB)
local img = Image(64, 64, ColorMode.RGB)
img:drawPixel(40, 10, RED); img:drawPixel(5, 10, BLUE)
img:drawPixel(40, 20, RED); img:drawPixel(8, 20, GREEN)
spr.cels[1].image = img

local flat = core.flatten(spr, 1)
local copies, tw, th = core.layout(64, 64, "x", 3, 32, false)
check("X: largura total", tw, 128); check("X: altura total", th, 64)
local prev = core.render(flat, copies, tw, th)
check("copia 1 deslocada 32px", prev:getPixel(72, 10), RED)
check("copia 1 mostra pixel da esquerda", prev:getPixel(37, 10), BLUE)
check("copia da direita por cima (Tibia)", prev:getPixel(72, 20), GREEN)
local rc = core.layout(64, 64, "x", 3, 32, true)
check("ordem inversa", core.render(flat, rc, tw, th):getPixel(72, 20), RED)

local _, tw2, th2 = core.layout(64, 64, "y", 4, 32, false)
check("Y: tamanho", tw2 .. "x" .. th2, "64x160")
local _, tw3, th3, nx, ny = core.layout(64, 64, "xy", 3, 32, false)
check("XY: tamanho", tw3 .. "x" .. th3 .. " " .. nx * ny, "128x128 9")
local _, tw4 = core.layout(32, 32, "x", 3, 32, false)
check("32x32 lado a lado", tw4, 96)

-- 2) Clique -> pixel do sprite
local x, y = core.pick(flat, copies, 72, 20)
check("pick pixel visivel do topo", x .. "," .. y, "8,20")
x, y = core.pick(flat, copies, 72, 10)
check("pick pula copia transparente", x .. "," .. y, "40,10")
x, y = core.pick(flat, copies, 72, 30)
check("pick transparente -> copia do topo", x .. "," .. y, "8,30")

-- 3) Gravar traco e desfazer
local layer, cel = spr.layers[1], spr.cels[1]
local work = core.workImage(spr, cel)
work:drawPixel(1, 1, GREEN)
core.commit(spr, layer, 1, work)
local c = layer:cel(1)
check("commit grava pixel", c.image:getPixel(1 - c.position.x, 1 - c.position.y), GREEN)
check("commit preserva pixel antigo", c.image:getPixel(40 - c.position.x, 10 - c.position.y), RED)
check("cel recortada", c.bounds.x .. "," .. c.bounds.y, "1,1")
app.undo()
c = layer:cel(1)
check("undo remove traco", c.image:getPixel(1 - c.position.x, 1 - c.position.y) == GREEN and
  c.bounds:contains(Rectangle(1, 1, 1, 1)), false)

-- cel inexistente: nova camada
local l2 = spr:newLayer()
local w2 = core.workImage(spr, l2:cel(1))
w2:drawPixel(10, 50, BLUE)
core.commit(spr, l2, 1, w2)
check("cria cel nova", l2:cel(1) ~= nil and l2:cel(1).image:getPixel(0, 0), BLUE)

-- selecao como tile de origem
local sp3 = Sprite(64, 64, ColorMode.RGB)
local i3 = Image(64, 64, ColorMode.RGB)
i3:drawPixel(40, 50, RED)
sp3.cels[1].image = i3
local f3 = core.flatten(sp3, 1)
local s0, bx0, by0 = core.source(f3, sp3)
check("sem selecao usa sprite inteiro", s0.width .. "x" .. s0.height .. "@" .. bx0 .. "," .. by0, "64x64@0,0")
sp3.selection = Selection(Rectangle(32, 32, 32, 32))
local s1, bx1, by1 = core.source(f3, sp3)
check("selecao recorta o tile", s1.width .. "x" .. s1.height .. "@" .. bx1 .. "," .. by1, "32x32@32,32")
check("pixel do tile selecionado", s1:getPixel(8, 18), RED)
local cp3, tw3b, th3b = core.layout(32, 32, "xy", 3, 32, false)
check("grade 3x3 do tile 32", tw3b .. "x" .. th3b, "96x96")
local p3 = core.render(s1, cp3, tw3b, th3b)
check("repete em X e Y", p3:getPixel(8 + 64, 18 + 32), RED)
local lx3, ly3 = core.pick(s1, cp3, 8 + 64, 18 + 32)
check("pick volta p/ canvas", (lx3 + bx1) .. "," .. (ly3 + by1), "40,50")
sp3.selection = Selection(Rectangle(60, 60, 20, 20))
local s2 = core.source(f3, sp3)
check("selecao cortada pela borda", s2.width .. "x" .. s2.height, "4x4")

-- conta-gotas
local ce = core.colorAt(sp3, p3, 8 + 64, 18 + 32)
check("conta-gotas RGB", ce.red .. "," .. ce.green .. "," .. ce.blue .. "," .. ce.alpha, "255,0,0,255")
check("conta-gotas transparente", core.colorAt(sp3, p3, 0, 0).alpha, 0)
app.fgColor = ce
check("vira cor principal", app.fgColor.red .. "," .. app.fgColor.green, "255,0")
local spx = Sprite(32, 32, ColorMode.INDEXED)
local palx = spx.palettes[1]
palx:resize(8)
palx:setColor(5, Color{ r = 10, g = 20, b = 30 })
local rgbx = Image(4, 4, ColorMode.RGB)
rgbx:drawPixel(1, 1, pc.rgba(10, 20, 30))
check("conta-gotas indexed -> indice", core.colorAt(spx, rgbx, 1, 1).index, 5)
check("conta-gotas indexed transparente", core.colorAt(spx, rgbx, 0, 0).index, spx.transparentColor)

-- indexed
local spi = Sprite(64, 64, ColorMode.INDEXED)
check("cor indexed", core.pixelValue(spi, Color{ index = 3 }), 3)
check("transparente indexed", core.pixelValue(spi, nil), spi.transparentColor)

-- 4) Imagem visual: parede horizontal do Tibia (64x64, face inclinada 45 graus)
local wall = Sprite(64, 64, ColorMode.RGB)
local wi = Image(64, 64, ColorMode.RGB)
for py = 31, 63 do
  local z = 63 - py
  for px = 32 - z, 63 - z do
    if px >= 0 then
      local lx = px + z - 32 -- coordenada ao longo da parede (0..31)
      local mortar = (py % 8 == 7) or ((lx + ((py // 8) % 2) * 8) % 16 == 15)
      wi:drawPixel(px, py, mortar and pc.rgba(90, 80, 70) or pc.rgba(160, 110, 80))
    end
  end
end
wi:drawPixel(63, 63, pc.rgba(255, 255, 0)) -- ancora (canto inferior direito)
wall.cels[1].image = wi
local function save(name, mode, n)
  local f = core.flatten(wall, 1)
  local cp, w, h = core.layout(64, 64, mode, n, 32, false)
  local p = core.render(f, cp, w, h)
  local s, z = Image(w * 4, h * 4, ColorMode.RGB), 4
  for yy = 0, h - 1 do for xx = 0, w - 1 do
    local v = p:getPixel(xx, yy)
    if pc.rgbaA(v) == 0 then v = (((xx // 8) + (yy // 8)) % 2 == 0) and pc.rgba(60, 60, 60) or pc.rgba(80, 80, 80) end
    for a = 0, z - 1 do for b = 0, z - 1 do s:drawPixel(xx * z + a, yy * z + b, v) end end
  end end
  s:saveAs(app.fs.joinPath(out, name))
end
save("wall_x.png", "x", 4)
save("wall_xy.png", "xy", 3)

print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
