-- Logica pura (sem UI) do Tibia Wall Tiled Mode.
--
-- Convencao do Tibia (conferida no RME, source/map_drawer.cpp):
--  * Um sprite maior que 32x32 cresce para CIMA e para a ESQUERDA a partir
--    do tile ancora (o canto inferior direito do sprite).
--  * Tiles sao desenhados em x/y crescente; quem esta a direita/abaixo e
--    desenhado depois e fica POR CIMA. Dentro de um bloco o RME percorre
--    x por fora e y por dentro.
-- Por isso cada copia anda exatamente `step` px (32) independente do tamanho
-- do canvas, e copias com x/y maior sao desenhadas por ultimo.

local M = {}

-- Posicoes (canto superior esquerdo) de cada copia em ordem de desenho,
-- mais o tamanho total da area de preview.
-- mode: "x" (parede horizontal), "y" (parede vertical) ou "xy" (grade).
function M.layout(w, h, mode, count, step, reverse)
  local nx = (mode == "y") and 1 or count
  local ny = (mode == "x") and 1 or count
  local copies = {}
  for i = 0, nx - 1 do
    for j = 0, ny - 1 do
      copies[#copies + 1] = { x = i * step, y = j * step, i = i, j = j }
    end
  end
  if reverse then
    local r = {}
    for k = #copies, 1, -1 do r[#r + 1] = copies[k] end
    copies = r
  end
  return copies, w + (nx - 1) * step, h + (ny - 1) * step, nx, ny
end

-- Composicao RGB de todas as camadas visiveis do frame.
function M.flatten(sprite, frame)
  local img = Image(sprite.width, sprite.height, ColorMode.RGB)
  img:drawSprite(sprite, frame, Point(0, 0))
  return img
end

-- Retangulo da selecao (dentro do canvas) ou nil se nao houver selecao.
function M.selectionBounds(sprite)
  local sel = sprite.selection
  if not sel or sel.isEmpty then return nil end
  local b = sel.bounds:intersect(Rectangle(0, 0, sprite.width, sprite.height))
  if b.isEmpty then return nil end
  return b
end

-- Tile que sera repetido: a area selecionada ou o sprite inteiro.
-- Retorna a imagem e a posicao dela no canvas (para converter de volta).
function M.source(flat, sprite)
  local b = M.selectionBounds(sprite)
  if not b then return flat, 0, 0 end
  return Image(flat, b), b.x, b.y
end

function M.render(src, copies, tw, th)
  local out = Image(tw, th, ColorMode.RGB)
  for _, c in ipairs(copies) do
    out:drawImage(src, Point(c.x, c.y), 255, BlendMode.NORMAL)
  end
  return out
end

-- Converte um ponto do preview para um pixel do sprite.
-- Prefere a copia mais de cima que tem pixel visivel ali (e o que o usuario
-- esta vendo); se nenhuma tiver, usa a copia mais de cima que cobre o ponto.
function M.pick(src, copies, px, py)
  local w, h = src.width, src.height
  local fallback
  for k = #copies, 1, -1 do
    local c = copies[k]
    local lx, ly = px - c.x, py - c.y
    if lx >= 0 and ly >= 0 and lx < w and ly < h then
      if app.pixelColor.rgbaA(src:getPixel(lx, ly)) > 0 then
        return lx, ly
      end
      if not fallback then fallback = { lx, ly } end
    end
  end
  if fallback then return fallback[1], fallback[2] end
  return nil
end

-- Valor de pixel para a cor no modo de cor do sprite (nil = transparente).
function M.pixelValue(sprite, color)
  local pc = app.pixelColor
  local mode = sprite.colorMode
  if color == nil then
    if mode == ColorMode.INDEXED then return sprite.transparentColor end
    return 0
  end
  if mode == ColorMode.INDEXED then return color.index end
  if mode == ColorMode.GRAY then return pc.graya(color.gray, color.alpha) end
  return pc.rgba(color.red, color.green, color.blue, color.alpha)
end

-- Conta-gotas: cor do pixel (x, y) de uma imagem RGB, como Color do sprite.
-- Em sprites indexed devolve o indice da paleta com a mesma cor (se houver).
function M.colorAt(sprite, rgbImage, x, y)
  local pc = app.pixelColor
  local v = rgbImage:getPixel(x, y)
  local r, g, b, a = pc.rgbaR(v), pc.rgbaG(v), pc.rgbaB(v), pc.rgbaA(v)
  if sprite.colorMode == ColorMode.INDEXED then
    if a == 0 then return Color{ index = sprite.transparentColor } end
    local pal = sprite.palettes[1]
    for i = 0, #pal - 1 do
      local c = pal:getColor(i)
      if c.red == r and c.green == g and c.blue == b and i ~= sprite.transparentColor then
        return Color{ index = i }
      end
    end
  end
  return Color{ r = r, g = g, b = b, a = a }
end

-- Linha de Bresenham chamando fn(x, y) em cada ponto.
function M.line(x0, y0, x1, y1, fn)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    fn(x0, y0)
    if x0 == x1 and y0 == y1 then return end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

-- Imagem do tamanho do canvas com o conteudo atual da cel (para pintar).
function M.workImage(sprite, cel)
  local work = Image(sprite.spec)
  work:clear()
  if cel then work:drawImage(cel.image, cel.position, 255, BlendMode.NORMAL) end
  return work
end

-- Grava a imagem de trabalho na cel em UMA transacao (um Ctrl+Z desfaz o traco).
-- Recorta a area vazia, como o Aseprite faz com as cels normais.
function M.commit(sprite, layer, frame, work, label)
  app.transaction(label or "Tibia Tiled: pintar", function()
    local cel = layer:cel(frame)
    local bounds = work:shrinkBounds()
    if bounds.isEmpty then
      if cel then sprite:deleteCel(cel) end
      return
    end
    local img = Image(work, bounds)
    if cel then
      cel.image = img
      cel.position = Point(bounds.x, bounds.y)
    else
      sprite:newCel(layer, frame, img, Point(bounds.x, bounds.y))
    end
  end)
end

return M
