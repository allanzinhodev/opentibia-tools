-- Unificar Paleta - Aseprite 1.3.18.6+
-- Arquivo independente; copie para a pasta de scripts do Aseprite.
-- Selecione cores da paleta, gere tons intermediarios e padronize a camada.
local Engine = (function()
-- Motor puro Lua: gera tons intermediarios e encontra a cor mais proxima.
-- As cores de entrada e saida usam { r=0..255, g=0..255, b=0..255, index=? }.
-- Nenhuma funcao depende do Aseprite; a interface cuida de alfa e paletas.
local Engine = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local EPSILON = 1e-14
local SEARCH_LIMIT = 100000
local RANKING_BUDGET = 12000000
local SAMPLE_LIMIT = 2048

local function clamp(v, low, high)
  return max(low, min(high, v))
end

local function channel(v)
  assert(type(v) == "number" and v == v and v >= 0 and v <= 255,
         "Canal RGB invalido; use valores de 0 a 255.")
  return floor(v + 0.5)
end

local function rgbKey(r, g, b)
  return r * 65536 + g * 256 + b
end

local function linear(v)
  v = clamp(v / 255, 0, 1)
  if v <= 0.04045 then return v / 12.92 end
  return ((v + 0.055) / 1.055) ^ 2.4
end

local function encoded(v)
  v = clamp(v, 0, 1)
  if v <= 0.0031308 then return v * 12.92 * 255 end
  return (1.055 * v ^ (1 / 2.4) - 0.055) * 255
end

local function toSpace(r, g, b, metric)
  if metric == "rgb" then return { r / 255, g / 255, b / 255 } end
  r, g, b = linear(r), linear(g), linear(b)
  local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
  local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
  local s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
  return {
    0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
  }
end

local function distance(a, b)
  local x, y, z = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return x * x + y * y + z * z
end

local function metricName(options)
  local metric = options.metric or "oklab"
  assert(metric == "rgb" or metric == "oklab", "Metrica desconhecida: " .. tostring(metric))
  return metric
end

local function normalizedColors(colors)
  assert(type(colors) == "table" and #colors > 0, "Selecione ao menos uma cor base.")
  local out, seen = {}, {}
  for _, source in ipairs(colors) do
    local r, g, b = channel(source.r), channel(source.g), channel(source.b)
    local key = rgbKey(r, g, b)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = {
        r = r, g = g, b = b, index = source.index,
        generated = source.generated == true,
      }
    end
  end
  return out, seen
end

-- A distancia e Oklab ao quadrado (padrao), ou RGB normalizado ao quadrado.
-- nearest() aceita canais fracionarios para difusao de erro no adaptador.
function Engine.prepare(colors, options)
  options = options or {}
  local metric = metricName(options)
  local palette = normalizedColors(colors)
  local vectors = {}
  for i, color in ipairs(palette) do
    vectors[i] = toSpace(color.r, color.g, color.b, metric)
  end
  local cache, cacheCount = {}, 0
  local mapper = { colors = palette, metric = metric }

  function mapper:nearest(r, g, b)
    r, g, b = clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255)
    local key
    if r == floor(r) and g == floor(g) and b == floor(b) then
      key = rgbKey(r, g, b)
      local hit = cache[key]
      if hit then return palette[hit[1]], hit[2] end
    end
    local target = toSpace(r, g, b, metric)
    local bestIndex, bestDistance = 1, math.huge
    for i, vector in ipairs(vectors) do
      local value = distance(target, vector)
      if value < bestDistance then bestIndex, bestDistance = i, value end
    end
    if key then
      if cacheCount >= 65536 then cache, cacheCount = {}, 0 end
      cache[key], cacheCount = { bestIndex, bestDistance }, cacheCount + 1
    end
    return palette[bestIndex], bestDistance
  end

  -- A distribuicao espacial (difusao de erro) pertence ao adaptador de pixels.
  function mapper:map(r, g, b)
    return self:nearest(r, g, b)
  end

  return mapper
end

local function integerOption(value, fallback, low, high, name)
  if value == nil then value = fallback end
  assert(type(value) == "number" and value == floor(value)
         and value >= low and value <= high,
         name .. " deve estar entre " .. low .. " e " .. high .. ".")
  return value
end

local function sampleHistogram(samples, limit)
  local byKey, out = {}, {}
  for _, source in ipairs(samples or {}) do
    local r, g, b = channel(source.r), channel(source.g), channel(source.b)
    local count = source.count or 1
    assert(type(count) == "number" and count == count and count > 0 and count < math.huge,
           "Contagem de pixels invalida no histograma.")
    local key = rgbKey(r, g, b)
    if byKey[key] then
      byKey[key].count = byKey[key].count + count
    else
      local sample = { r = r, g = g, b = b, count = count, key = key }
      byKey[key], out[#out + 1] = sample, sample
    end
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
  end)
  local total = #out
  while #out > limit do out[#out] = nil end
  return out, total
end

-- Gera misturas convexas com pesos inteiros / steps. Cada tom usa no maximo
-- maxColors bases DISTINTAS. O limite de busca considera tentativas, mesmo
-- quando o arredondamento acaba produzindo cores repetidas.
--
-- A selecao de novos tons e guiada pela arte: cada cor amostrada vota no
-- candidato que mais reduz seu erro em relacao somente as bases; a frequencia
-- dos pixels pondera esse voto. O desempate usa cobertura e depois RGB.
-- Isso e uma heuristica deterministica, nao uma otimizacao global exaustiva.
function Engine.generate(colors, options)
  options = options or {}
  local metric = metricName(options)
  local bases, seen = normalizedColors(colors)
  for _, color in ipairs(bases) do color.generated = false end
  local maxColors = integerOption(options.maxColors, 2, 1, 3, "Cores por mistura")
  local steps = integerOption(options.steps, 4, 2, 8, "Divisoes da mistura")
  local maxNew = integerOption(options.maxNewColors, 32, 0, 256, "Novas cores")
  local space = options.space or "srgb"
  assert(space == "srgb" or space == "linear", "Espaco de mistura desconhecido.")
  local result = {
    colors = bases, baseCount = #bases, generatedCount = 0, candidateCount = 0,
    searchedCount = 0, sampledColors = 0, sourceSampleColors = 0,
    searchLimit = SEARCH_LIMIT, rankingBudget = RANKING_BUDGET,
  }
  if maxNew == 0 or maxColors == 1 or #bases < 2 then return result end

  local n = #bases
  local attempts = n * (n - 1) / 2 * (steps - 1)
  if maxColors >= 3 and steps >= 3 then
    attempts = attempts + n * (n - 1) * (n - 2) / 6
                         * (steps - 1) * (steps - 2) / 2
  end
  assert(attempts <= SEARCH_LIMIT,
    string.format("Busca muito grande: %.0f misturas (limite %d). Reduza as cores base, as divisoes ou as cores por mistura.",
                  attempts, SEARCH_LIMIT))
  result.searchedCount = attempts

  local components = {}
  for i, base in ipairs(bases) do
    if space == "linear" then
      components[i] = { linear(base.r), linear(base.g), linear(base.b) }
    else
      components[i] = { base.r, base.g, base.b }
    end
  end
  local candidates = {}
  local function add(i, j, k, wi, wj, wk)
    local a, b, c = components[i], components[j], k and components[k]
    local channels = {}
    for channelIndex = 1, 3 do
      local value = (a[channelIndex] * wi + b[channelIndex] * wj
                     + (c and c[channelIndex] * wk or 0)) / steps
      if space == "linear" then value = encoded(value) end
      channels[channelIndex] = floor(clamp(value, 0, 255) + 0.5)
    end
    local r, g, b = channels[1], channels[2], channels[3]
    local key = rgbKey(r, g, b)
    if not seen[key] then
      seen[key] = true
      candidates[#candidates + 1] = {
        r = r, g = g, b = b, generated = true, key = key,
        vector = toSpace(r, g, b, metric), score = 0, coverage = 0,
      }
    end
  end
  for i = 1, n - 1 do
    for j = i + 1, n do
      for wi = 1, steps - 1 do add(i, j, nil, wi, steps - wi, 0) end
      if maxColors >= 3 and steps >= 3 then
        for k = j + 1, n do
          for wi = 1, steps - 2 do
            for wj = 1, steps - wi - 1 do
              add(i, j, k, wi, wj, steps - wi - wj)
            end
          end
        end
      end
    end
  end
  result.candidateCount = #candidates
  if #candidates == 0 then return result end

  local sampleLimit = min(SAMPLE_LIMIT, max(1, floor(RANKING_BUDGET / #candidates)))
  local samples, originalSampleCount = sampleHistogram(options.sampleColors, sampleLimit)
  result.sampledColors, result.sourceSampleColors = #samples, originalSampleCount
  result.sampled = #samples < originalSampleCount
  if #samples > 0 then
    local baseMapper = Engine.prepare(bases, { metric = metric })
    for _, sample in ipairs(samples) do
      local _, baseDistance = baseMapper:nearest(sample.r, sample.g, sample.b)
      local target = toSpace(sample.r, sample.g, sample.b, metric)
      local best, bestDistance = nil, baseDistance
      if baseDistance > EPSILON then
        for _, candidate in ipairs(candidates) do
          local value = distance(target, candidate.vector)
          if value < baseDistance then
            candidate.coverage = candidate.coverage + (baseDistance - value) * sample.count
          end
          if value < bestDistance - EPSILON
             or (best and abs(value - bestDistance) <= EPSILON and candidate.key < best.key) then
            best, bestDistance = candidate, value
          end
        end
        if best then
          best.score = best.score + (baseDistance - bestDistance) * sample.count
        end
      end
    end
    table.sort(candidates, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      if a.coverage ~= b.coverage then return a.coverage > b.coverage end
      return a.key < b.key
    end)
    for _, candidate in ipairs(candidates) do
      if result.generatedCount >= maxNew or candidate.score <= EPSILON then break end
      result.colors[#result.colors + 1] = {
        r = candidate.r, g = candidate.g, b = candidate.b, generated = true,
      }
      result.generatedCount = result.generatedCount + 1
    end
  else
    -- Sem arte para orientar: espalha a escolha pela lista RGB ordenada.
    table.sort(candidates, function(a, b) return a.key < b.key end)
    local count = min(maxNew, #candidates)
    for i = 1, count do
      local at = floor((i - 0.5) * #candidates / count) + 1
      local candidate = candidates[at]
      result.colors[#result.colors + 1] = {
        r = candidate.r, g = candidate.g, b = candidate.b, generated = true,
      }
    end
    result.generatedCount = count
  end
  return result
end

Engine.toSpace = toSpace
Engine.distance = distance
Engine.srgbToLinear = linear
Engine.linearToSrgb = encoded
Engine.limits = { search = SEARCH_LIMIT, ranking = RANKING_BUDGET, samples = SAMPLE_LIMIT }

return Engine

end)()

local Reference = (function()
-- Paleta dos pixels visiveis de uma imagem externa. Indexed usa documento
-- temporario para resolver sua propria paleta; o documento e fechado sem salvar.
local Reference = {}
local pc = app.pixelColor
local MAX_COLORS = 8192

local function fail(message) error(message, 0) end
local function key(r,g,b) return r*65536 + g*256 + b end

local function siteSnapshot()
  local range = app.range
  local layers,frames,colors = {},{},{}
  for i=1,#range.layers do layers[i] = range.layers[i] end
  for i=1,#range.frames do frames[i] = range.frames[i].frameNumber end
  for i,color in ipairs(range.colors) do colors[i] = color end
  return {sprite=app.sprite,layer=app.layer,frame=app.frame and app.frame.frameNumber,
    layers=layers,frames=frames,colors=colors,empty=range.isEmpty,type=range.type}
end

local function restoreSite(site)
  if not site.sprite then return end
  app.sprite = site.sprite
  if site.layer then app.layer = site.layer end
  if site.frame then app.frame = site.frame end
  app.range:clear()
  if not site.empty then
    if site.type == RangeType.LAYERS then
      if #site.frames > 0 then app.range.frames=site.frames end
      if #site.layers > 0 then app.range.layers=site.layers end
    else
      if #site.layers > 0 then app.range.layers=site.layers end
      if #site.frames > 0 then app.range.frames=site.frames end
    end
  end
  app.range.colors=site.colors
end

local function indexedAsRgb(filename)
  -- Image{fromFile} preserva indices e nao expoe sua paleta. Um documento
  -- temporario permite renderizar com a paleta do proprio arquivo, sem salvar.
  local site,temporary = siteSnapshot(),nil
  local ok,result = pcall(function()
    temporary=Sprite{fromFile=filename,oneFrame=true}
    if not temporary then fail("Falha ao abrir referencia indexada.") end
    local rgb=Image(temporary.width,temporary.height,ColorMode.RGB)
    rgb:drawSprite(temporary,1)
    return rgb
  end)
  if temporary then temporary:close() end
  restoreSite(site)
  if not ok then fail("Nao foi possivel renderizar a referencia indexada: " .. tostring(result)) end
  return result
end

function Reference.load(filename)
  if type(filename) ~= "string" or filename == "" then
    fail("Escolha um arquivo de imagem como referencia.")
  end
  local ok,image = pcall(function() return Image{fromFile=filename} end)
  if not ok or not image then fail("Nao foi possivel ler a imagem de referencia: " .. filename) end
  if image.colorMode == ColorMode.INDEXED then image=indexedAsRgb(filename) end
  local colors, histogram, pixelCount = {}, {}, 0
  for it in image:pixels() do
    local pixel = it()
    local r,g,b,a
    if image.colorMode == ColorMode.GRAY then
      r,a = pc.grayaV(pixel),pc.grayaA(pixel)
      g,b = r,r
    else
      r,g,b,a = pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel),pc.rgbaA(pixel)
    end
    if a > 0 then
      pixelCount = pixelCount+1
      local rgb = key(r,g,b)
      if histogram[rgb] then histogram[rgb].count = histogram[rgb].count+1
      else
        local entry = {r=r,g=g,b=b,count=1,key=rgb}
        histogram[rgb],colors[#colors+1] = entry,entry
        if #colors > MAX_COLORS then
          fail("A referencia tem mais de " .. MAX_COLORS .. " cores RGB. Use uma spritesheet de pixel art ou reduza as cores do arquivo.")
        end
      end
    end
  end
  if #colors == 0 then fail("A imagem de referencia contem apenas pixels transparentes.") end
  table.sort(colors,function(a,b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
  end)
  return {colors=colors,filename=filename,uniqueCount=#colors,pixelCount=pixelCount,
    width=image.width,height=image.height,firstFrameOnly=true}
end

function Reference.savePalette(colors,filename)
  if type(colors) ~= "table" or #colors == 0 then fail("Nao ha cores para salvar na paleta.") end
  if type(filename) ~= "string" or filename == "" then fail("Escolha onde salvar a paleta.") end
  local palette = Palette(#colors)
  for i,color in ipairs(colors) do
    palette:setColor(i-1,Color{r=color.r,g=color.g,b=color.b,a=255})
  end
  local ok,result = pcall(function() return palette:saveAs(filename) end)
  if not ok or result == false then fail("Nao foi possivel salvar a paleta: " .. filename) end
  return true
end

Reference.maxColors = MAX_COLORS
return Reference

end)()

-- Adaptador Aseprite. Engine e incorporado pelo build; nenhuma dependencia externa.
local Tool = {}
local pc = app.pixelColor
local TITLE = "Unificar paleta"

local function fail(message) error(message, 0) end
local function rgbKey(r, g, b) return r * 65536 + g * 256 + b end
local function integer(value, default, lo, hi, name)
  value = value == nil and default or tonumber(value)
  if not value or value ~= math.floor(value) or value < lo or value > hi then
    fail(name .. ": use um inteiro de " .. lo .. " a " .. hi .. ".")
  end
  return value
end

function Tool.paletteAt(sprite, frameNumber)
  local result, best = sprite.palettes[1], -1
  for i=1,#sprite.palettes do
    local palette = sprite.palettes[i]
    local number = palette.frameNumber
    if number <= frameNumber and number > best then
      result, best = palette, number
    end
  end
  return result
end

local function validate(options)
  local sprite = options.sprite or app.sprite
  if not sprite then fail("Abra um sprite antes de executar o script.") end
  if sprite.colorMode ~= ColorMode.RGB then
    fail("Use Sprite > Color Mode > RGB antes de executar. Este script gera tons RGB.")
  end
  local layer = options.layer or app.layer
  if not layer or layer.sprite ~= sprite or not layer.isImage or layer.isTilemap or layer.isReference then
    fail("Selecione uma camada de pixels comum (grupos, tilemaps e referencias nao sao aceitos).")
  end
  local ancestor = layer
  while ancestor and ancestor ~= sprite do
    if not ancestor.isEditable then fail("A camada ou um grupo superior esta bloqueado.") end
    ancestor = ancestor.parent
  end
  local o = {}
  for k, v in pairs(options) do o[k] = v end
  o.sprite, o.layer = sprite, layer
  o.frameNumber = integer(o.frameNumber or (app.frame and app.frame.frameNumber), 1, 1, #sprite.frames, "Frame")
  o.frames = o.frames or "current"
  if o.frames ~= "current" and o.frames ~= "all" then fail("Escopo de frames invalido.") end
  o.reference = o.referenceFile ~= nil or o.referenceColors ~= nil
  o.mode = o.reference and "nearest" or (o.mode or "mix")
  if o.reference then o.protectOutline = false end
  if o.mode ~= "mix" and o.mode ~= "nearest" then fail("Modo invalido.") end
  o.maxColors = integer(o.maxColors, 2, 1, 3, "Cores base por mistura")
  o.steps = integer(o.steps, 4, 2, 8, "Partes da mistura")
  o.maxNewColors = integer(o.maxNewColors, 8, 0, 256, "Limite de cores novas")
  o.outlineThreshold = integer(o.outlineThreshold, 48, 0, 255, "Limite da borda escura")
  o.metric, o.space = o.metric or "oklab", o.space or "srgb"
  if o.metric ~= "oklab" and o.metric ~= "rgb" then fail("Metrica invalida.") end
  if o.space ~= "srgb" and o.space ~= "linear" then fail("Espaco de mistura invalido.") end
  if o.respectSelection == nil then o.respectSelection = true end
  if o.addToPalette == nil then o.addToPalette = true end
  o.palette = Tool.paletteAt(sprite, o.frameNumber)
  local referenceColors = o.referenceColors
  if not referenceColors and o.referenceFile then referenceColors = Reference.load(o.referenceFile).colors end
  if o.indices == nil then
    o.indices = {}
    if o.reference then
      for i=1,#referenceColors do o.indices[i] = i-1 end
    else
      for i,index in ipairs(app.range.colors) do o.indices[i] = index end
    end
  end
  local bases, seen = {}, {}
  for _, index in ipairs(o.indices) do
    integer(index, nil, 0, (o.reference and #referenceColors or #o.palette) - 1, "Indice da paleta")
    local color
    if o.reference then
      local source = referenceColors[index+1]
      if type(source) ~= "table" then fail("Cor ausente ou invalida na referencia.") end
      color = Color{
        r=integer(source.r,nil,0,255,"Vermelho da referencia"),
        g=integer(source.g,nil,0,255,"Verde da referencia"),
        b=integer(source.b,nil,0,255,"Azul da referencia"),a=255}
    else
      color = o.palette:getColor(index)
    end
    if color.alpha ~= 255 then fail("Escolha apenas cores opacas como base (alpha 255).") end
    local key = rgbKey(color.red, color.green, color.blue)
    if not seen[key] then
      seen[key] = true
      bases[#bases + 1] = {r=color.red, g=color.green, b=color.blue, index=index}
    end
  end
  if #bases == 0 then fail("Selecione pelo menos uma cor opaca da paleta.") end
  return o, bases
end

local function eligible(o, cel, image, x, y, pixel)
  if pc.rgbaA(pixel) == 0 then return false end
  local gx, gy = x + cel.position.x, y + cel.position.y
  if gx < 0 or gy < 0 or gx >= o.sprite.width or gy >= o.sprite.height then return false end
  if o.respectSelection and not o.sprite.selection.isEmpty and not o.sprite.selection:contains(gx, gy) then
    return false
  end
  if o.protectOutline then
    local brightness = 0.2126 * pc.rgbaR(pixel) + 0.7152 * pc.rgbaG(pixel) + 0.0722 * pc.rgbaB(pixel)
    if brightness <= o.outlineThreshold then
      if x == 0 or y == 0 or x == image.width - 1 or y == image.height - 1 then return false end
      if pc.rgbaA(image:getPixel(x-1,y)) == 0 or pc.rgbaA(image:getPixel(x+1,y)) == 0
        or pc.rgbaA(image:getPixel(x,y-1)) == 0 or pc.rgbaA(image:getPixel(x,y+1)) == 0 then return false end
    end
  end
  return true
end

-- Calcula todas as imagens em memoria. Previa nao escreve no documento.
function Tool.plan(options)
  local o, bases = validate(options)
  local cels = {}
  if o.frames == "all" then
    for _, cel in ipairs(o.layer.cels) do cels[#cels + 1] = cel end
    table.sort(cels, function(a,b) return a.frameNumber < b.frameNumber end)
  else
    local cel = o.layer:cel(o.frameNumber)
    if cel then cels[1] = cel end
  end
  if #cels == 0 then fail("Nao ha pixels no frame/escopo escolhido desta camada.") end
  local histogram = {}
  local eligiblePixels = 0
  for _, cel in ipairs(cels) do
    local image = cel.image
    for it in image:pixels() do
      local pixel = it()
      if eligible(o, cel, image, it.x, it.y, pixel) then
        if o.mode == "mix" then
          local r,g,b = pc.rgbaR(pixel),pc.rgbaG(pixel),pc.rgbaB(pixel)
          local key = rgbKey(r,g,b)
          local sample = histogram[key]
          if sample then sample.count = sample.count + 1
          else histogram[key] = {r=r,g=g,b=b,count=1} end
        end
        eligiblePixels = eligiblePixels + 1
      end
    end
  end
  local samples = {}
  for _, sample in pairs(histogram) do samples[#samples + 1] = sample end
  local result
  if o.mode == "mix" and eligiblePixels > 0 then
    result = Engine.generate(bases, {
      maxColors=o.maxColors, steps=o.steps, maxNewColors=o.maxNewColors,
      space=o.space, metric=o.metric, sampleColors=samples,
    })
  else
    result = {colors=bases,baseCount=#bases,generatedCount=0,candidateCount=0}
  end
  local mapper = Engine.prepare(result.colors, {metric=o.metric,mode="nearest"})
  local changes, changedPixels = {}, 0
  local firstBefore, firstAfter, firstPosition, firstFrame
  for _, cel in ipairs(cels) do
    local original, output = cel.image, Image(cel.image)
    local changed = 0
    for it in output:pixels() do
      local pixel = it()
      if eligible(o, cel, original, it.x, it.y, pixel) then
        local color = mapper:nearest(pc.rgbaR(pixel), pc.rgbaG(pixel), pc.rgbaB(pixel))
        local replacement = pc.rgba(color.r, color.g, color.b, pc.rgbaA(pixel))
        if replacement ~= pixel then it(replacement); changed = changed + 1 end
      end
    end
    if not firstBefore or cel.frameNumber == o.frameNumber then
      firstBefore, firstAfter, firstPosition, firstFrame = original, output, cel.position, cel.frameNumber
    end
    if changed > 0 then
      changes[#changes + 1] = {cel=cel, image=output, frameNumber=cel.frameNumber}
      changedPixels = changedPixels + changed
    end
  end
  -- Acrescenta apenas entradas ausentes; nunca substitui cores anteriores da paleta.
  local palette, paletteAdded = nil, 0
  if o.addToPalette and (result.generatedCount > 0 or o.reference) then
    local copy, existing = Palette(o.sprite.palettes[1]), {}
    for i=0,#copy-1 do
      local color = copy:getColor(i)
      if color.alpha == 255 then existing[rgbKey(color.red,color.green,color.blue)] = true end
    end
    local append = {}
    for _, color in ipairs(result.colors) do
      local key = rgbKey(color.r,color.g,color.b)
      if not existing[key] then
        append[#append + 1] = color
        existing[key] = true
      end
    end
    if #append > 0 then
      local oldSize = #copy
      if oldSize + #append > 65536 then fail("A paleta excederia 65536 entradas. Desative adicionar a paleta.") end
      copy:resize(oldSize + #append)
      for i,color in ipairs(append) do copy:setColor(oldSize+i-1, Color{r=color.r,g=color.g,b=color.b,a=255}) end
      palette, paletteAdded = copy, #append
    end
  end
  return {
    options=o, changes=changes, palette=palette, colors=result.colors,
    before=firstBefore, after=firstAfter, position=firstPosition, previewFrame=firstFrame,
    stats={changedPixels=changedPixels, generatedCount=result.generatedCount,
      baseCount=result.baseCount, processedCels=#cels, addedToPalette=paletteAdded,
      candidateCount=result.candidateCount, eligiblePixels=eligiblePixels},
  }
end

local function snapshotSite()
  local range = app.range
  local layers, frames, colors = {}, {}, {}
  -- Layers/Frames retornados pela API sao userdata, mas os setters exigem
  -- tabelas Lua. Copia os elementos antes de limpar o range do editor.
  for i=1,#range.layers do layers[i] = range.layers[i] end
  for i=1,#range.frames do frames[i] = range.frames[i].frameNumber end
  for i,color in ipairs(range.colors) do colors[i] = color end
  return {sprite=app.sprite,layer=app.layer,frame=app.frame and app.frame.frameNumber,
    layers=layers,frames=frames,colors=colors,empty=range.isEmpty,type=range.type}
end

local function restoreSite(site)
  if site.sprite then
    app.sprite = site.sprite
    if site.layer then app.layer = site.layer end
    if site.frame then app.frame = site.frame end
    app.range:clear()
    if not site.empty then
      if site.type == RangeType.LAYERS then
        if #site.frames > 0 then app.range.frames = site.frames end
        if #site.layers > 0 then app.range.layers = site.layers end
      else
        if #site.layers > 0 then app.range.layers = site.layers end
        if #site.frames > 0 then app.range.frames = site.frames end
      end
    end
    if #site.colors > 0 then app.range.colors = site.colors end
  end
end

function Tool.commit(plan)
  if #plan.changes == 0 and not plan.palette then return plan.stats end
  local o, saved = plan.options, snapshotSite()
  local ok, message = pcall(function()
    app.sprite = o.sprite
    app.transaction(TITLE, function()
      -- UnlinkCel atua no range inteiro, portanto limpa antes de cada cel.
      -- Assim outros frames/camadas vinculados ficam intactos e metadados sao mantidos.
      for _, change in ipairs(plan.changes) do
        app.range:clear()
        app.layer, app.frame = o.layer, change.frameNumber
        app.command.UnlinkCel()
        o.layer:cel(change.frameNumber).image = change.image
      end
      if plan.palette then o.sprite:setPalette(plan.palette) end
    end)
  end)
  restoreSite(saved)
  if not ok then error(message, 0) end
  app.refresh()
  return plan.stats
end

function Tool.run(options) return Tool.commit(Tool.plan(options)) end

local function alert(message) app.alert{title=TITLE,text=tostring(message)} end

local function showPreview(plan, parent)
  local o = plan.options
  local before, after = Image(o.sprite.width,o.sprite.height), Image(o.sprite.width,o.sprite.height)
  before:drawImage(plan.before, plan.position)
  after:drawImage(plan.after, plan.position)
  local scale = math.min(4, 180 / before.width, 160 / before.height)
  local w,h = math.max(1,math.floor(before.width*scale)),math.max(1,math.floor(before.height*scale))
  local dlg = Dialog{title="Previa — " .. o.layer.name,parent=parent}
  dlg:label{text="Antes / depois (frame " .. plan.previewFrame .. ")"}
  dlg:canvas{width=w*2+12,height=h, onpaint=function(ev)
    local gc = ev.context
    for y=0,h-1,8 do for x=0,w*2+11,8 do
      gc.color = ((x//8+y//8)%2 == 0) and Color{r=160,g=160,b=160} or Color{r=110,g=110,b=110}
      gc:fillRect(Rectangle(x,y,8,8))
    end end
    gc:drawImage(before,Rectangle(0,0,before.width,before.height),Rectangle(0,0,w,h))
    gc:drawImage(after,Rectangle(0,0,after.width,after.height),Rectangle(w+12,0,w,h))
  end}
  dlg:label{text=plan.stats.changedPixels .. " pixels a alterar; " .. plan.stats.generatedCount .. " cores novas."}
  dlg:label{text="A previa nao altera o sprite. Feche e use Aplicar."}
  dlg:button{text="Fechar"}
  dlg:show{wait=true,autoscrollbars=true}
end

function Tool.show()
  local sprite, layer, frame = app.sprite, app.layer, app.frame
  local ok, message = pcall(function()
    validate{sprite=sprite,layer=layer,indices={}}
  end)
  -- A escolha vazia sera preenchida na janela; outros problemas bloqueiam cedo.
  if not ok and not tostring(message):find("pelo menos uma cor",1,true) then alert(message); return end
  local spritePalette = Tool.paletteAt(sprite, frame.frameNumber)
  local palette, referenceData = spritePalette, nil
  local selected, page = {}, 0
  for _, index in ipairs(app.range.colors) do
    if index < #palette and palette:getColor(index).alpha == 255 then selected[index] = true end
  end
  local dlg = Dialog(TITLE)
  local pageSize, columns, cell = 128, 16, 14
  local reloadSource
  local function selectionIndices()
    local indices = {}
    for index=0,#palette-1 do if selected[index] then indices[#indices+1] = index end end
    return indices
  end
  local function update()
    dlg:modify{id="chosen",text=#selectionIndices() .. " cores selecionadas; borda branca = escolhida"}
    dlg:modify{id="page",text="Paleta: pagina " .. page+1 .. "/" .. math.ceil(#palette/pageSize)}
    dlg:repaint()
  end
  local function refreshMode()
    local reference = dlg.data.source == "Arquivo de referencia"
    local mix = not reference and dlg.data.mode == "Criar tons intermediarios"
    dlg:modify{id="mode",enabled=not reference}
    for _,id in ipairs{"maxColors","steps","maxNewColors","space"} do dlg:modify{id=id,enabled=mix} end
    dlg:modify{id="addToPalette",enabled=mix or reference}
    dlg:modify{id="protectOutline",enabled=not reference}
    dlg:modify{id="outlineThreshold",enabled=not reference}
  end
  reloadSource = function()
    local data = dlg.data
    if data.source == "Arquivo de referencia" then
      if not data.referenceFile or data.referenceFile == "" then
        referenceData, selected, page = nil, {}, 0
        palette = Palette(1); palette:setColor(0,Color{r=0,g=0,b=0,a=0})
        dlg:modify{id="sourceStatus",text="Escolha o arquivo de referencia abaixo."}
      else
        local success, loaded = pcall(Reference.load, data.referenceFile)
        if not success then
          referenceData, selected, page = nil, {}, 0
          palette = Palette(1); palette:setColor(0,Color{r=0,g=0,b=0,a=0})
          dlg:modify{id="sourceStatus",text="Falha ao ler a referencia."}
          alert(loaded)
        else
          referenceData, selected, page = loaded, {}, 0
          palette = Palette(#loaded.colors)
          for i,color in ipairs(loaded.colors) do
            palette:setColor(i-1, Color{r=color.r,g=color.g,b=color.b,a=255})
            selected[i-1] = true
          end
          dlg:modify{id="sourceStatus",text=#loaded.colors .. " cores do arquivo; nenhuma mistura sera criada."}
        end
      end
      dlg:modify{id="mode",option="Somente cores escolhidas"}
    else
      palette, selected, page = spritePalette, {}, 0
      for _,index in ipairs(app.range.colors) do
        if index < #palette and palette:getColor(index).alpha == 255 then selected[index] = true end
      end
      dlg:modify{id="sourceStatus",text="Selecione as cores base para padronizar a camada."}
    end
    update()
    refreshMode()
  end
  local function options()
    local data = dlg.data
    local reference = data.source == "Arquivo de referencia"
    if reference and not referenceData then fail("Escolha um arquivo de referencia valido.") end
    return {sprite=sprite,layer=layer,frameNumber=frame.frameNumber,
      referenceColors=reference and referenceData.colors or nil,
      frames=data.frames == "Todos da camada" and "all" or "current",
      indices=selectionIndices(),mode=data.mode == "Criar tons intermediarios" and "mix" or "nearest",
      maxColors=data.maxColors,steps=data.steps,maxNewColors=data.maxNewColors,
      metric=data.metric == "Oklab (perceptual)" and "oklab" or "rgb",
      space=data.space == "sRGB (artistica)" and "srgb" or "linear",
      respectSelection=data.respectSelection,protectOutline=data.protectOutline,
      outlineThreshold=data.outlineThreshold,addToPalette=data.addToPalette}
  end
  dlg:label{text="Camada: " .. layer.name}
  dlg:combobox{id="source",label="Origem das cores",option="Paleta atual",
    options={"Paleta atual","Arquivo de referencia"},onchange=function() reloadSource() end}
  dlg:file{id="referenceFile",label="Spritesheet fonte",title="Escolher spritesheet de referencia",
    open=true,filetypes={"png","aseprite","ase","bmp","gif"},filename="",
    onchange=function()
      dlg:modify{id="source",option="Arquivo de referencia"}
      reloadSource()
    end}
  dlg:label{id="sourceStatus",text="Selecione as cores base para padronizar a camada."}
  dlg:label{id="page",text="Paleta: pagina 1/" .. math.ceil(#palette/pageSize)}
  dlg:canvas{id="palette",width=columns*cell,height=8*cell,hexpand=false,
    onpaint=function(ev)
      local gc = ev.context
      gc.color=Color{r=48,g=48,b=48}; gc:fillRect(Rectangle(0,0,gc.width,gc.height))
      for slot=0,pageSize-1 do
        local index = page*pageSize + slot
        if index < #palette then
          local x,y = (slot%columns)*cell,(slot//columns)*cell
          local color = palette:getColor(index)
          gc.color = color.alpha == 255 and color or Color{r=75,g=75,b=75}
          gc:fillRect(Rectangle(x+2,y+2,cell-4,cell-4))
          if selected[index] then
            gc.color=Color{r=255,g=255,b=255}; gc.strokeWidth=1
            gc:strokeRect(Rectangle(x,y,cell-1,cell-1))
          elseif color.alpha ~= 255 then
            gc.color=Color{r=220,g=80,b=80}; gc:fillRect(Rectangle(x+5,y+5,4,4))
          end
        end
      end
    end,
    onmousedown=function(ev)
      if ev.button ~= MouseButton.LEFT then return end
      if ev.x < 0 or ev.y < 0 or ev.x >= columns*cell or ev.y >= 8*cell then return end
      local index = page*pageSize + (ev.y//cell)*columns + (ev.x//cell)
      if index < #palette and palette:getColor(index).alpha == 255 then selected[index]=not selected[index]; update() end
    end}
  dlg:button{text="<",onclick=function() page=math.max(0,page-1);update() end}
  dlg:button{text=">",onclick=function() page=math.min(math.ceil(#palette/pageSize)-1,page+1);update() end}
  dlg:button{text="Limpar",onclick=function() selected={};update() end}
  dlg:label{id="chosen",text="Clique nas cores para selecionar/remover."}
  dlg:separator{text="Padronizacao"}
  dlg:combobox{id="mode",label="Modo",option="Criar tons intermediarios",
    options={"Criar tons intermediarios","Somente cores escolhidas"},onchange=refreshMode}
  dlg:slider{id="maxColors",label="Bases por mistura",min=1,max=3,value=2}
  dlg:slider{id="steps",label="Partes da mistura",min=2,max=8,value=4}
  dlg:slider{id="maxNewColors",label="Max. cores novas",min=0,max=256,value=8}
  dlg:combobox{id="space",label="Mistura",option="sRGB (artistica)",options={"sRGB (artistica)","RGB linear (luz)"}}
  dlg:combobox{id="metric",label="Cor mais proxima",option="Oklab (perceptual)",options={"Oklab (perceptual)","RGB"}}
  dlg:combobox{id="frames",label="Frames",option="Atual",options={"Atual","Todos da camada"}}
  dlg:check{id="respectSelection",text="Respeitar selecao de pixels (se houver)",selected=true}
  dlg:check{id="protectOutline",text="Proteger borda escura junto a transparencia",selected=false}
  dlg:slider{id="outlineThreshold",label="Escuridao da borda",min=0,max=255,value=48}
  dlg:check{id="addToPalette",text="Acrescentar cores permitidas na paleta",selected=true}
  dlg:separator{}
  dlg:button{text="Salvar paleta...",onclick=function()
    local colors = {}
    for _,index in ipairs(selectionIndices()) do
      local color = palette:getColor(index)
      colors[#colors+1] = {r=color.red,g=color.green,b=color.blue}
    end
    if #colors == 0 then alert("Selecione cores antes de salvar a paleta."); return end
    local export = Dialog{title="Salvar paleta GPL",parent=dlg}
    export:file{id="filename",label="Arquivo",title="Salvar paleta GPL",save=true,filetypes={"gpl"},filename="paleta_referencia.gpl"}
    export:button{text="Salvar",onclick=function()
      local success,result = pcall(Reference.savePalette,colors,export.data.filename)
      if success then export:close(); alert("Paleta salva: " .. export.data.filename) else alert(result) end
    end}
    export:button{text="Cancelar"}
    export:show{wait=true}
  end}
  dlg:newrow()
  dlg:button{text="Previa",onclick=function()
    local success,result = pcall(function() return Tool.plan(options()) end)
    if success then showPreview(result,dlg) else alert(result) end
  end}
  dlg:button{text="Aplicar",onclick=function()
    local success,result = pcall(function() return Tool.run(options()) end)
    if success then
      dlg:close()
      alert(result.changedPixels .. " pixels alterados em " .. result.processedCels .. " cel(s).\n"
        .. result.generatedCount .. " tons novos; " .. result.addedToPalette .. " entradas acrescentadas a paleta.\n"
        .. "Ctrl+Z desfaz toda a operacao.")
    else alert(result) end
  end}
  dlg:button{text="Cancelar"}
  update()
  refreshMode()
  dlg:show{wait=true,autoscrollbars=true}
end

if app.isUIAvailable and not (app.params and app.params.unificar_test == "1") then Tool.show() end
return {Engine=Engine,Tool=Tool,Reference=Reference}
