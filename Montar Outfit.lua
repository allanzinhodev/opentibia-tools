-- Montar Outfit: spritesheet 1024x3072 <-> documento editavel.
-- Aseprite 1.3.18+. Execute em File > Scripts > Montar Outfit.
-- Cada faixa 512x64: Norte, Leste, Sul, Oeste; desenho e mascara por direcao.
-- As faixas sao empacotadas da esquerda para a direita, duas por linha.
-- Categorias: Personagem, Addon 1, Addon 2, Personagem Montado,
-- Addon 1 Montado, Addon 2 Montado. Edicao: 256x64, 16 frames.
local M = {}
local CELL, FRAMES, CATEGORIES = 64, 16, 6
local ID = "montar_outfit_v1"
local NAMES = {
  "Personagem", "Personagem - Máscara",
  "Addon 1", "Addon 1 - Mascara",
  "Addon 2", "Addon 2 - Mascara"
}
local DIRECTIONS = { "Norte", "Sul", "Norte Montado", "Sul Montado" }

local function requireValue(condition, message)
  if not condition then error(message, 0) end
end

function M.metadata(sprite)
  if not sprite then return {} end
  local ok, value = pcall(json.decode, sprite.data)
  if ok and (type(value) == "table" or type(value) == "userdata") and value.tool == ID then
    return value
  end
  return {}
end

local function checkOrder(order)
  requireValue(order == "frame" or order == "category", "Ordem da spritesheet inválida.")
end

function M.sheetCell(frame, category, direction, mask, order)
  local strip
  if order == "category" then strip = category * FRAMES + frame
  else strip = frame * CATEGORIES + category end
  return (strip % 2) * 512 + direction * 128 + mask * CELL,
         math.floor(strip / 2) * CELL
end

local function blankImage(sprite, width, height)
  local spec = sprite.spec
  spec.width, spec.height = width, height
  local image = Image(spec)
  image:clear()
  return image
end

-- Copia valores brutos, inclusive alpha e indices da paleta. Nunca aplica
-- Multiply/opacidade aos pixels das mascaras. Recorta cels fora do canvas.
local function copyRect(destination, source, sx, sy, dx, dy, width, height, transpose)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local sourceX, sourceY = sx + x, sy + y
      local targetX, targetY = dx + x, dy + y
      if transpose then targetX, targetY = dx + y, dy + x end
      if sourceX >= 0 and sourceY >= 0 and sourceX < source.width and sourceY < source.height
         and targetX >= 0 and targetY >= 0
         and targetX < destination.width and targetY < destination.height then
        destination:drawPixel(targetX, targetY, source:getPixel(sourceX, sourceY))
      end
    end
  end
end

local function flattened(sprite)
  local image = blankImage(sprite, sprite.width, sprite.height)
  local layer = sprite.layers[1]
  local cel = layer and layer:cel(1)
  if #sprite.layers == 1 and not layer.isGroup and layer.isVisible
     and layer.opacity == 255 and layer.blendMode == BlendMode.NORMAL
     and cel and cel.opacity == 255 then
    if cel.position.x == 0 and cel.position.y == 0
       and cel.image.width == sprite.width and cel.image.height == sprite.height then
      return Image(cel.image)
    end
    copyRect(image, cel.image, 0, 0, cel.position.x, cel.position.y,
             cel.image.width, cel.image.height)
  else
    image:drawSprite(sprite, 1, Point(0, 0))
  end
  return image
end

local function newSprite(source, width, height)
  local spec = source.spec
  spec.width, spec.height = width, height
  local sprite = Sprite(spec)
  sprite.transparentColor = source.transparentColor
  if source.palettes[1] then sprite:setPalette(source.palettes[1]) end
  sprite.gridBounds = Rectangle(0, 0, CELL, CELL)
  return sprite
end

local function outputName(source, suffix)
  local metadata = M.metadata(source)
  local filename = metadata.source or source.filename
  if not filename or filename == "" then return "outfit" .. suffix .. ".aseprite" end
  return app.fs.joinPath(app.fs.filePath(filename), app.fs.fileTitle(filename) .. suffix .. ".aseprite")
end

local function addTag(sprite, name, first, last, color)
  local tag = sprite:newTag(first, last)
  tag.name, tag.color = name, color
  return tag
end

function M.importSheet(source, order)
  requireValue(source ~= nil, "Abra a spritesheet 1024 × 3072 antes de executar.")
  requireValue(source.width == 1024 and source.height == 3072,
               "A spritesheet deve medir exatamente 1024 × 3072 pixels.")
  requireValue(#source.frames == 1, "A spritesheet de origem deve ter um único frame.")
  order = order or "frame"
  checkOrder(order)
  local image = flattened(source)
  local destination = newSprite(source, CELL * 4, CELL)
  local ok, message = pcall(function()
    app.transaction("Montar arquivo de edição", function()
      for f = 2, FRAMES do destination:newEmptyFrame(f) end
      for _, frame in ipairs(destination.frames) do frame.duration = 0.1 end
      local layers = {}
      for i, name in ipairs(NAMES) do
        local layer = i == 1 and destination.layers[1] or destination:newLayer()
        layer.name, layer.data = name, ID .. ":layer:" .. i
        if i % 2 == 0 then
          layer.blendMode, layer.opacity = BlendMode.MULTIPLY, 230
        else
          layer.blendMode, layer.opacity = BlendMode.NORMAL, 255
        end
        layers[i] = layer
      end
      if layers[1]:cel(1) then destination:deleteCel(layers[1]:cel(1)) end
      for f = 0, FRAMES - 1 do
        for part = 0, 2 do
          for mask = 0, 1 do
            local layer = layers[part * 2 + mask + 1]
            local canvas = blankImage(destination, CELL * 4, CELL)
            for column = 0, 3 do
              local category = part + math.floor(column / 2) * 3
              local direction = column % 2 == 0 and 0 or 2
              local x, y = M.sheetCell(f, category, direction, mask, order)
              copyRect(canvas, image, x, y, column * CELL, 0, CELL, CELL)
            end
            destination:newCel(layer, f + 1, canvas, Point(0, 0))
          end
        end
      end
      local idleColor, walkColor = Color{r=98,g=170,b=231}, Color{r=101,g=195,b=123}
      addTag(destination, "Idle", 1, 8, idleColor)
      addTag(destination, "walk", 9, 16, walkColor)
      for column, name in ipairs(DIRECTIONS) do
        local slice = destination:newSlice(Rectangle((column - 1) * CELL, 0, CELL, CELL))
        slice.name = name
      end
      destination.data = json.encode{tool=ID, version=1, order=order, layout="columns", source=source.filename}
      destination.filename = outputName(source, "_edicao")
    end)
  end)
  if not ok then destination:close(); error(message, 0) end
  return destination
end

local function findLayers(sprite)
  local result = {}
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup then
      local role = tonumber(layer.data:match("^" .. ID .. ":layer:(%d+)$"))
      if not role then
        for index, name in ipairs(NAMES) do if layer.name == name then role = index; break end end
      end
      if role and role >= 1 and role <= #NAMES then
        requireValue(not result[role], "Há duas layers correspondentes a " .. NAMES[role] .. ".")
        result[role] = layer
      end
    end
  end
  for index, name in ipairs(NAMES) do
    requireValue(result[index] ~= nil, "Layer obrigatória ausente: " .. name)
  end
  return result
end

function M.exportSheet(source, order)
  requireValue(source ~= nil, "Abra o arquivo de edição antes de montar a spritesheet.")
  requireValue(source.width == CELL * 4 and source.height == CELL and #source.frames == FRAMES,
    "Use o arquivo de edição: 256 × 64 pixels com 16 frames.")
  order = order or M.metadata(source).order or "frame"
  checkOrder(order)
  local layers = findLayers(source)
  local image = blankImage(source, 1024, 3072)
  for f = 0, FRAMES - 1 do
    for category = 0, CATEGORIES - 1 do
      local mounted, part = math.floor(category / 3), category % 3
      for mask = 0, 1 do
        local layer = layers[part * 2 + mask + 1]
        for direction = 0, 3 do
          -- N e O usam Norte; L e S usam Sul. FlipV + giro horario = (x,y)->(y,x).
          local column = mounted * 2 + ((direction == 1 or direction == 2) and 1 or 0)
          local cel = layer:cel(f + 1)
          if cel then
            local x, y = M.sheetCell(f, category, direction, mask, order)
            copyRect(image, cel.image, column * CELL - cel.position.x, -cel.position.y,
                     x, y, CELL, CELL, direction == 1 or direction == 3)
          end
        end
      end
    end
  end
  local destination = newSprite(source, 1024, 3072)
  local ok, message = pcall(function()
    app.transaction("Montar Spritesheet", function()
      destination.layers[1].name = "Spritesheet"
      local cel = destination.layers[1]:cel(1)
      if cel then cel.image, cel.position = image, Point(0, 0)
      else destination:newCel(destination.layers[1], 1, image, Point(0, 0)) end
      destination.filename = outputName(source, "_spritesheet")
    end)
  end)
  if not ok then destination:close(); error(message, 0) end
  return destination
end

local function main()
  local params = app.params or {}
  if params.mode == "library" then return M end
  if not app.isUIAvailable then
    local sprite = app.activeSprite
    if params.input then sprite = app.open(params.input) end
    local destination
    if params.mode == "import" then
      destination = M.importSheet(sprite, params.order)
    elseif params.mode == "export" then
      destination = M.exportSheet(sprite, params.order)
    else error("Use --script-param mode=import ou mode=export.", 0) end
    if params.output then destination:saveAs(params.output) end
    return destination
  end
  local source = app.activeSprite
  requireValue(source ~= nil, "Abra a spritesheet ou o arquivo de edição antes de executar.")
  local metadata = M.metadata(source)
  local importText, exportText = "Montar arquivo de edição", "Montar Spritesheet"
  local frameOrder, categoryOrder = "6 categorias por frame", "16 frames por categoria"
  local isSheet = source.width == 1024 and source.height == 3072
  local dialog = Dialog{title="Montar Outfit"}
  dialog:combobox{id="action", label="Operação:", options={importText, exportText},
    option=isSheet and importText or exportText}
  dialog:combobox{id="order", label="Ordem da sheet:", options={frameOrder, categoryOrder},
    option=metadata.order == "category" and categoryOrder or frameOrder}
  dialog:label{text="Canvas: 256 × 64 | quatro posições lado a lado"}
  dialog:label{text="Idle: 8 frames | walk: 8 frames | 100 ms"}
  dialog:label{text="Norte, Sul, Norte Montado, Sul Montado"}
  dialog:button{id="run", text="Executar", focus=true}
  dialog:button{text="Cancelar"}
  dialog:show()
  local data = dialog.data
  if not data.run then return end
  local order = data.order == categoryOrder and "category" or "frame"
  local destination
  if data.action == importText then
    destination = M.importSheet(source, order)
  else destination = M.exportSheet(source, order) end
  app.activeSprite = destination
  app.activeLayer = destination.layers[1]
  app.activeFrame = destination.frames[1]
  app.refresh()
  app.alert{title="Montar Outfit", text={
    "Arquivo criado em uma nova aba: " .. destination.width .. " × " .. destination.height .. ".",
    data.action == importText and "6 layers; máscaras em Multiply a 90%." or "Leste e Oeste reconstruídos com o flip de 64 × 64.",
    data.action == importText and "Salve como .aseprite para continuar editando." or "Salve como PNG para exportar a spritesheet."
  }}
  return destination
end

if (app.params or {}).mode == "library" then return M end
if app.isUIAvailable then
  local ok, message = pcall(main)
  if not ok then app.alert{title="Montar Outfit", text=tostring(message)} end
else return main() end
