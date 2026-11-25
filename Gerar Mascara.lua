-- Gerar Mascara: escolha cores na paleta; os pixels dessas cores na layer ativa
-- ficam sem saturacao e mais claros, e uma copia deles e pintada com a cor de
-- mascara (amarelo/verde/vermelho/azul) deslocada N pixels para a direita.
-- Aseprite 1.3+, RGB ou Indexado. Execute em File > Scripts > Gerar Mascara.
-- A janela fica aberta: selecione cores na paleta (Ctrl/Shift+clique),
-- clique em "Usar seleção da paleta" e depois em "Aplicar". Ctrl+Z desfaz.
local M = {}
local pc = app.pixelColor

M.MASK_COLORS = {
  { name = "Amarelo #FFFF00", color = Color{ r = 255, g = 255, b = 0,   a = 255 } },
  { name = "Verde #00FF00",   color = Color{ r = 0,   g = 255, b = 0,   a = 255 } },
  { name = "Vermelho #FF0000", color = Color{ r = 255, g = 0,  b = 0,   a = 255 } },
  { name = "Azul #0000FF",    color = Color{ r = 0,   g = 0,   b = 255, a = 255 } },
}

local function requireValue(condition, message)
  if not condition then error(message, 0) end
end

local function sameColor(a, b)
  return a.red == b.red and a.green == b.green and a.blue == b.blue and a.alpha == b.alpha
end

local function hex(c)
  return string.format("#%02X%02X%02X", c.red, c.green, c.blue)
end

-- Saturacao 0 e luminosidade HSL + amount (0..1), limitada a branco.
function M.grayLighter(color, amount)
  local mx = math.max(color.red, color.green, color.blue)
  local mn = math.min(color.red, color.green, color.blue)
  local lightness = math.min(1, (mx + mn) / 510 + amount)
  local v = math.floor(lightness * 255 + 0.5)
  return Color{ r = v, g = v, b = v, a = color.alpha }
end

local function paletteIndex(sprite, color)
  local palette = sprite.palettes[1]
  for i = 0, #palette - 1 do
    if i ~= sprite.transparentColor and sameColor(palette:getColor(i), color) then return i end
  end
  requireValue(#palette < 256, "Paleta cheia (256 cores): não há espaço para " .. hex(color) .. ".")
  palette:resize(#palette + 1)
  palette:setColor(#palette - 1, color)
  return #palette - 1
end

local function pixelValue(sprite, color)
  if sprite.colorMode == ColorMode.INDEXED then return paletteIndex(sprite, color) end
  return pc.rgba(color.red, color.green, color.blue, color.alpha)
end

local function findLayer(layers, name)
  for _, layer in ipairs(layers) do
    if layer.name == name and layer.isImage then return layer end
    if layer.isGroup then
      local found = findLayer(layer.layers, name)
      if found then return found end
    end
  end
end

-- Copia o cel (se houver) para uma imagem que cobre tambem `rect`.
local function expandedImage(sprite, cel, rect)
  local bounds = cel and rect:union(cel.bounds) or rect
  local spec = sprite.spec
  spec.width, spec.height = bounds.width, bounds.height
  local image = Image(spec)
  image:clear(sprite.colorMode == ColorMode.INDEXED and sprite.transparentColor or 0)
  if cel then
    image:drawImage(cel.image, Point(cel.position.x - bounds.x, cel.position.y - bounds.y),
                    255, BlendMode.SRC)
  end
  return image, Point(bounds.x, bounds.y)
end

-- opts: layer, frames (numeros), picks ({index, color}), amount (0..1),
--       maskColor (Color), dx, targetName (nil = mesma layer)
function M.apply(sprite, opts)
  requireValue(sprite ~= nil, "Abra um sprite antes de aplicar.")
  requireValue(sprite.colorMode ~= ColorMode.GRAY, "Modo Grayscale não suportado: use RGB ou Indexado.")
  local layer = opts.layer
  requireValue(layer and layer.isImage and not layer.isTilemap, "Selecione uma layer de imagem.")
  requireValue(layer.isEditable, "A layer ativa está travada.")
  requireValue(#opts.picks > 0, "Nenhuma cor escolhida.")
  local indexed = sprite.colorMode == ColorMode.INDEXED
  local stats = { recolored = 0, masked = 0, outside = 0 }

  app.transaction("Gerar máscara", function()
    local map = {}
    for _, pick in ipairs(opts.picks) do
      if not (indexed and pick.index == sprite.transparentColor) then
        local key = indexed and pick.index or pixelValue(sprite, pick.color)
        map[key] = pixelValue(sprite, M.grayLighter(pick.color, opts.amount))
      end
    end
    local maskValue = pixelValue(sprite, opts.maskColor)

    local target = layer
    if opts.targetName and opts.targetName ~= "" then
      target = findLayer(sprite.layers, opts.targetName)
      if not target then
        target = sprite:newLayer()
        target.name = opts.targetName
      end
      requireValue(target.isEditable and not target.isTilemap,
                   "A layer \"" .. opts.targetName .. "\" não pode ser editada.")
    end

    for _, frameNumber in ipairs(opts.frames) do
      local cel = layer:cel(frameNumber)
      if cel then
        local source, pos = cel.image, cel.position
        local hits = {}
        for it in source:pixels() do
          local value = map[it()]
          if value then hits[#hits + 1] = { it.x, it.y, value } end
        end

        if #hits > 0 then
          local recolored = Image(source)
          for _, h in ipairs(hits) do recolored:drawPixel(h[1], h[2], h[3]) end
          cel.image = recolored
          stats.recolored = stats.recolored + #hits

          local points, x0, y0, x1, y1 = {}, math.huge, math.huge, -math.huge, -math.huge
          for _, h in ipairs(hits) do
            local x, y = pos.x + h[1] + opts.dx, pos.y + h[2]
            if x >= 0 and y >= 0 and x < sprite.width and y < sprite.height then
              points[#points + 1] = { x, y }
              x0, y0 = math.min(x0, x), math.min(y0, y)
              x1, y1 = math.max(x1, x), math.max(y1, y)
            else
              stats.outside = stats.outside + 1
            end
          end

          if #points > 0 then
            local targetCel = target:cel(frameNumber)
            local image, origin = expandedImage(sprite, targetCel,
                                                Rectangle(x0, y0, x1 - x0 + 1, y1 - y0 + 1))
            for _, p in ipairs(points) do
              image:drawPixel(p[1] - origin.x, p[2] - origin.y, maskValue)
            end
            if targetCel then
              targetCel.image, targetCel.position = image, origin
            else
              sprite:newCel(target, frameNumber, image, origin)
            end
            stats.masked = stats.masked + #points
          end
        end
      end
    end
  end)
  return stats
end

-- Cores selecionadas na paleta; sem selecao, usa a cor de frente.
local function readPalettePicks(sprite)
  local palette = sprite.palettes[1]
  local picks = {}
  for _, i in ipairs(app.range.colors or {}) do
    if i >= 0 and i < #palette then picks[#picks + 1] = { index = i, color = palette:getColor(i) } end
  end
  if #picks == 0 then
    local fg = app.fgColor
    for i = 0, #palette - 1 do
      if sameColor(palette:getColor(i), fg) then
        picks[1] = { index = i, color = palette:getColor(i) }
        break
      end
    end
  end
  return picks
end

local function showDialog()
  local picks = {}
  local dialog = Dialog{ title = "Gerar Máscara" }
  local maskNames = {}
  for i, m in ipairs(M.MASK_COLORS) do maskNames[i] = m.name end

  local function refresh(status)
    local colors = {}
    for i, pick in ipairs(picks) do colors[i] = pick.color end
    dialog:modify{ id = "cores", colors = colors }
    dialog:modify{ id = "status", text = status or (#picks .. " cor(es) escolhida(s)") }
  end

  local function usePalette()
    local sprite = app.activeSprite
    if not sprite then return refresh("Abra um sprite primeiro.") end
    picks = readPalettePicks(sprite)
    refresh(#picks == 0 and "Selecione cores na paleta." or nil)
  end

  dialog:shades{ id = "cores", label = "Cores:", mode = "pick", colors = {},
    onclick = function(ev)
      for i, pick in ipairs(picks) do
        if sameColor(pick.color, ev.color) then table.remove(picks, i); break end
      end
      refresh()
    end }
  dialog:label{ text = "Clique numa cor acima para removê-la." }
  dialog:button{ text = "Usar seleção da paleta", onclick = usePalette }
  dialog:separator()
  dialog:combobox{ id = "mask", label = "Cor da máscara:", options = maskNames, option = maskNames[1] }
  dialog:slider{ id = "light", label = "Clarear (%):", min = 0, max = 50, value = 10 }
  dialog:number{ id = "dx", label = "Deslocamento X:", text = "64", decimals = 0 }
  dialog:combobox{ id = "frames", label = "Frames:", options = { "Frame atual", "Todos os frames" } }
  dialog:combobox{ id = "dest", label = "Máscara em:", options = { "Mesma layer", "Layer separada" } }
  dialog:entry{ id = "layerName", label = "Nome da layer:", text = "Máscara" }
  dialog:separator()
  dialog:label{ id = "status", text = "" }
  dialog:button{ text = "Aplicar", focus = true, onclick = function()
    local data, sprite = dialog.data, app.activeSprite
    local maskColor
    for _, m in ipairs(M.MASK_COLORS) do if m.name == data.mask then maskColor = m.color end end
    local frames = {}
    if sprite then
      if data.frames == "Todos os frames" then
        for _, f in ipairs(sprite.frames) do frames[#frames + 1] = f.frameNumber end
      else
        frames[1] = app.activeFrame.frameNumber
      end
    end
    local layer = app.activeLayer
    local ok, result = pcall(M.apply, sprite, {
      layer = layer, frames = frames, picks = picks, amount = data.light / 100,
      maskColor = maskColor, dx = math.floor(data.dx),
      targetName = data.dest == "Layer separada" and data.layerName or nil,
    })
    if not ok then return app.alert{ title = "Gerar Máscara", text = tostring(result) } end
    app.activeLayer = layer
    app.refresh()
    local text = result.recolored .. " px recoloridos, " .. result.masked .. " px de máscara"
    if result.outside > 0 then text = text .. ", " .. result.outside .. " fora do canvas" end
    refresh(text)
  end }
  dialog:button{ text = "Fechar", onclick = function() dialog:close() end }
  dialog:show{ wait = false }
  usePalette()
end

if (app.params or {}).mode == "library" then return M end
if app.isUIAvailable then showDialog() end
return M
