-- Tibia Wall Tiled Mode: preview ao vivo do sprite repetido a cada 32px
-- (convencao do Tibia), com lapis para pintar direto nas emendas.
local core
local S = nil -- estado da janela aberta (so uma por vez)

local MODES = { "Horizontal (X)", "Vertical (Y)", "Grade (X e Y)" }
local MODE_KEY = { ["Horizontal (X)"] = "x", ["Vertical (Y)"] = "y", ["Grade (X e Y)"] = "xy" }
local ORDERS = { "Tibia (direita/baixo por cima)", "Inversa" }

local function opts()
  local d = S.dlg.data
  return MODE_KEY[d.mode] or "x", d.count, math.max(1, math.floor(tonumber(d.step) or 32)), d.order == ORDERS[2]
end

local function setInfo(text)
  if S and S.dlg then S.dlg:modify{ id = "info", text = text } end
end

-- Identifica a selecao atual (para notar quando ela muda).
local function selKey(spr)
  local b = spr and core.selectionBounds(spr)
  return b and string.format("%d,%d,%d,%d", b.x, b.y, b.width, b.height) or ""
end

-- Recalcula composicao + preview a partir do sprite/frame ativos.
local function rebuild(keepFlat)
  if not S then return end
  local spr = S.sprite
  if not spr or not S.frame then
    S.preview = nil
    setInfo("Abra um sprite.")
    S.dlg:repaint()
    return
  end
  if not keepFlat then
    S.flat = core.flatten(spr, S.frame)
    S.src, S.bx, S.by = core.source(S.flat, spr)
    local key = selKey(spr)
    if key ~= S.selKey then S.autoFit = true end -- tile mudou de tamanho: reajusta zoom
    S.selKey = key
  end
  local mode, count, step, rev = opts()
  local w, h = S.src.width, S.src.height
  S.copies, S.tw, S.th, S.nx, S.ny = core.layout(w, h, mode, count, step, rev)
  S.preview = core.render(S.src, S.copies, S.tw, S.th)
  if not S.stroke then
    local what = (S.src == S.flat) and "sprite inteiro" or string.format("selecao em %d,%d", S.bx, S.by)
    setInfo(string.format("Tile %dx%d (%s)  |  passo %dpx  |  fixo no canto inferior direito", w, h, what, step))
  end
  S.dlg:repaint()
end

local function fitZoom(gw, gh)
  if not S.tw then return 1 end
  return math.max(1, math.min(16, math.floor(math.min((gw - 8) / S.tw, (gh - 8) / S.th))))
end

-- Liga a janela ao sprite ativo (ouve alteracoes para atualizar ao vivo).
local function bind()
  local spr = app.sprite
  if S.sprite ~= spr then
    if S.sprite and S.listener then pcall(function() S.sprite.events:off(S.listener) end) end
    S.sprite, S.listener = spr, nil
    if spr then S.listener = spr.events:on("change", function() if S and not S.stroke then rebuild() end end) end
    S.autoFit = true
  end
  S.frame = app.frame
  rebuild()
end

-------------------------------------------------------------------- desenho
local function paint(ev)
  local gc = ev.context
  local gw, gh = gc.width, gc.height
  gc.color = Color{ r = 40, g = 40, b = 40 }
  gc:fillRect(Rectangle(0, 0, gw, gh))
  if not S.preview then return end
  if S.autoFit then S.zoom = fitZoom(gw, gh); S.autoFit = false; S.dlg:modify{ id = "zoom", value = S.zoom } end
  local z, tw, th = S.zoom, S.tw, S.th
  local ox, oy = math.floor((gw - tw * z) / 2), math.floor((gh - th * z) / 2)
  S.ox, S.oy = ox, oy

  -- xadrez (8px do sprite)
  local a, b = Color{ r = 102, g = 102, b = 102 }, Color{ r = 153, g = 153, b = 153 }
  local cs = 8
  for cy = 0, math.ceil(th / cs) - 1 do
    for cx = 0, math.ceil(tw / cs) - 1 do
      gc.color = ((cx + cy) % 2 == 0) and a or b
      local w = math.min(cs, tw - cx * cs) * z
      local h = math.min(cs, th - cy * cs) * z
      gc:fillRect(Rectangle(ox + cx * cs * z, oy + cy * cs * z, w, h))
    end
  end

  gc.antialias = false
  gc:drawImage(S.preview, Rectangle(0, 0, tw, th), Rectangle(ox, oy, tw * z, th * z))

  local d = S.dlg.data
  if d.grid then -- grade 32x32 alinhada pela ancora (canto inferior direito)
    gc.color = Color{ r = 0, g = 200, b = 255, a = 110 }
    local gx = tw
    while gx >= 0 do gc:fillRect(Rectangle(ox + gx * z, oy, 1, th * z)); gx = gx - 32 end
    local gy = th
    while gy >= 0 do gc:fillRect(Rectangle(ox, oy + gy * z, tw * z, 1)); gy = gy - 32 end
  end
  if d.highlight then -- contorno da copia central + seu tile ancora
    local ci, cj = (S.nx - 1) // 2, (S.ny - 1) // 2
    local _, _, step = opts()
    local x0, y0 = ox + ci * step * z, oy + cj * step * z
    local w, h = S.src.width, S.src.height
    gc.color = Color{ r = 255, g = 210, b = 0, a = 200 }
    gc:strokeRect(Rectangle(x0, y0, w * z, h * z))
    gc.color = Color{ r = 255, g = 60, b = 60, a = 200 }
    gc:strokeRect(Rectangle(x0 + (w - math.min(32, w)) * z, y0 + (h - math.min(32, h)) * z,
      math.min(32, w) * z, math.min(32, h) * z))
  end
end

-------------------------------------------------------------------- lapis
local function toPreview(ev)
  local x = (ev.x - S.ox) // S.zoom
  local y = (ev.y - S.oy) // S.zoom
  if x < 0 or y < 0 or x >= S.tw or y >= S.th then return nil end
  return x, y
end

local function plot(px, py)
  local st = S.stroke
  local sx, sy = core.pick(S.src, S.copies, px, py)
  if not sx then return end
  st.work:drawPixel(sx + S.bx, sy + S.by, st.value)
  S.src:drawPixel(sx, sy, st.rgba)
end

local function strokeTo(ev)
  local x, y = toPreview(ev)
  if not x then S.stroke.last = nil; return end
  local last = S.stroke.last
  if last then core.line(last[1], last[2], x, y, plot) else plot(x, y) end
  S.stroke.last = { x, y }
  rebuild(true)
end

-------------------------------------------------------------------- conta-gotas
-- Pega a cor do que aparece no preview (todas as camadas visiveis).
local function eyedrop(ev, button)
  local x, y = toPreview(ev)
  if not x then return end
  local c = core.colorAt(S.sprite, S.preview, x, y)
  local bg = button == MouseButton.RIGHT
  if bg then app.bgColor = c else app.fgColor = c end
  local txt = c.alpha == 0 and "transparente"
    or string.format("#%02X%02X%02X%s", c.red, c.green, c.blue,
      S.sprite.colorMode == ColorMode.INDEXED and (" (idx " .. c.index .. ")") or "")
  setInfo((bg and "Cor de fundo: " or "Cor principal: ") .. txt)
end

local function wantsEyedropper(ev)
  return ev.altKey or (app.tool and app.tool.id == "eyedropper")
end

local function beginStroke(ev)
  if not S.preview then return end
  if wantsEyedropper(ev) then
    S.picking = ev.button
    eyedrop(ev, S.picking)
    return
  end
  if not S.dlg.data.paint then return end
  local spr, layer, frame = app.sprite, app.layer, app.frame
  if spr ~= S.sprite then bind() end
  if not layer or not layer.isImage or layer.isTilemap then setInfo("Selecione uma camada de imagem."); return end
  if not layer.isEditable then setInfo("Camada bloqueada."); return end
  local erase = ev.button == MouseButton.RIGHT
  local color = (not erase) and app.fgColor or nil
  local pc = app.pixelColor
  S.stroke = {
    sprite = spr, layer = layer, frame = frame,
    work = core.workImage(spr, layer:cel(frame)),
    value = core.pixelValue(spr, color),
    rgba = color and pc.rgba(color.red, color.green, color.blue, color.alpha) or 0,
  }
  setInfo(erase and "Apagando..." or "Pintando...")
  strokeTo(ev)
end

local function endStroke()
  if S then S.picking = nil end
  local st = S and S.stroke
  if not st then return end
  S.stroke = nil
  core.commit(st.sprite, st.layer, st.frame, st.work, "Tibia Tiled: pintar")
  app.refresh()
  rebuild()
end

-------------------------------------------------------------------- janela
local function close()
  if not S then return end
  local s = S
  S = nil
  if s.sprite and s.listener then pcall(function() s.sprite.events:off(s.listener) end) end
  if s.siteListener then app.events:off(s.siteListener) end
  if s.timer then s.timer:stop() end
  pcall(function() s.dlg:close() end)
end

local function open()
  if S then close() end
  S = { zoom = 1, autoFit = true }
  local dlg = Dialog{ title = "Tibia Wall Tiled Mode", onclose = function() if S then endStroke(); close() end end }
  S.dlg = dlg
  local function changed() rebuild() end
  local function refit() S.autoFit = true; rebuild() end
  dlg:combobox{ id = "mode", label = "Repetir:", option = MODES[3], options = MODES, onchange = refit }
  dlg:slider{ id = "count", label = "Cópias:", min = 2, max = 9, value = 3, onchange = refit }
  dlg:number{ id = "step", label = "Deslocamento:", text = "32", decimals = 0, onchange = refit }
  dlg:combobox{ id = "order", label = "Por cima:", option = ORDERS[1], options = ORDERS, onchange = changed }
  dlg:slider{ id = "zoom", label = "Zoom:", min = 1, max = 16, value = 1,
    onchange = function() S.zoom = dlg.data.zoom; dlg:repaint() end }
  dlg:check{ id = "grid", label = "Mostrar:", text = "Grade 32x32", selected = true, onchange = changed }
  dlg:check{ id = "highlight", text = "Cópia central", selected = true, onchange = changed }
  dlg:newrow()
  dlg:check{ id = "paint", label = "Lápis:", text = "Pintar no preview (esq. = cor, dir. = apagar)", selected = true }
  dlg:newrow()
  dlg:label{ label = "Conta-gotas:", text = "Alt+clique ou ferramenta Eyedropper (I). Esq. = principal, dir. = fundo" }
  dlg:canvas{
    id = "canvas", width = 560, height = 360,
    onpaint = paint,
    onmousedown = beginStroke,
    onmousemove = function(ev)
      if S.picking then eyedrop(ev, S.picking)
      elseif S.stroke then strokeTo(ev) end
    end,
    onmouseup = endStroke,
    onwheel = function(ev)
      S.zoom = math.max(1, math.min(16, S.zoom - (ev.deltaY > 0 and 1 or -1)))
      dlg:modify{ id = "zoom", value = S.zoom }
      dlg:repaint()
    end,
  }
  dlg:label{ id = "info", text = "" }
  dlg:button{ text = "Ajustar zoom", onclick = refit }
  dlg:button{ text = "Atualizar", onclick = function() bind(); rebuild() end }
  dlg:button{ text = "Fechar", onclick = close }

  S.siteListener = app.events:on("sitechange", function()
    local fn = app.frame and app.frame.frameNumber
    local cur = S and S.frame and S.frame.frameNumber
    if S and not S.stroke and (app.sprite ~= S.sprite or fn ~= cur) then bind() end
  end)
  -- Mudar a selecao nem sempre dispara "change" no sprite: confere 4x por segundo.
  S.timer = Timer{ interval = 0.25, ontick = function()
    local ok, key = pcall(selKey, S and S.sprite)
    if S and S.sprite and ok and not S.stroke and key ~= S.selKey then
      rebuild()
    end
  end }
  dlg:show{ wait = false }
  bind()
  S.timer:start()
end

function init(plugin)
  core = dofile(app.fs.joinPath(plugin.path, "core.lua"))
  plugin:newCommand{
    id = "TibiaWallTiledMode",
    title = "Tibia Wall Tiled Mode...",
    group = "view_canvas_helpers",
    onenabled = function() return app.sprite ~= nil end,
    onclick = open,
  }
end

function exit(plugin)
  close()
end
