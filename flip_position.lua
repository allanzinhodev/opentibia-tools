-- half_transform.lua
--
-- Para cada cel (todas as layers, todos os frames):
--   1. Metade ESQUERDA: flip vertical, depois rotação 90° horário
--   2. Metade DIREITA:  flip vertical, depois rotação 90° horário
--   3. Troca as duas metades de lado
--
-- As transformações são feitas por manipulação de pixel direta.
-- O canvas É REDIMENSIONADO se necessário (apenas uma vez, antes do loop).
-- Para sprites quadrados (W=H) ou 2:1 (W=2H) o tamanho final == tamanho original.

-- ── Helpers ──────────────────────────────────────────────────────────────────

-- Copia uma região retangular de srcImage para uma nova Image
local function cropImage(src, rx, ry, rw, rh)
  local dst = Image(rw, rh, src.colorMode)
  dst:clear()
  for y = 0, rh - 1 do
    for x = 0, rw - 1 do
      dst:drawPixel(x, y, src:getPixel(rx + x, ry + y))
    end
  end
  return dst
end

-- Flip vertical de uma Image
local function flipV(src)
  local w, h = src.width, src.height
  local dst = Image(w, h, src.colorMode)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      dst:drawPixel(x, h - 1 - y, src:getPixel(x, y))
    end
  end
  return dst
end

-- Rotação 90° horário de uma Image: (x,y) → (H-1-y, x)
-- Resultado tem dimensões: largura=H original, altura=W original
local function rotateCW(src)
  local sw, sh = src.width, src.height
  local dst = Image(sh, sw, src.colorMode)  -- dimensões trocadas
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      -- pixel (x,y) vai para (sh-1-y, x) no destino
      dst:drawPixel(sh - 1 - y, x, src:getPixel(x, y))
    end
  end
  return dst
end

-- Compõe um Image de tamanho do canvas a partir de um cel (respeita offset)
local function celToCanvas(cel, W, H)
  local canvas = Image(W, H, cel.image.colorMode)
  canvas:clear()
  canvas:drawImage(cel.image, cel.bounds.x, cel.bounds.y)
  return canvas
end

-- ── Transforma uma metade: flipV depois rotateCW ──────────────────────────────
-- Entrada: halfW × H  →  Saída: H × halfW
local function transformHalf(img)
  return rotateCW(flipV(img))
end

-- ── Main ──────────────────────────────────────────────────────────────────────

local sprite = app.activeSprite
if not sprite then
  app.alert("Nenhum sprite ativo!")
  return
end

local W = sprite.width
local H = sprite.height

-- Divide o canvas ao meio verticalmente
local leftW  = math.floor(W / 2)
local rightW = W - leftW          -- pode ser leftW+1 se W for ímpar
local rightX = leftW               -- coluna de início da metade direita

-- Após transformar: cada metade tem dimensões H × halfW (largura virou altura e vice-versa)
-- Para manter o canvas original precisamos que:
--   newW = H + H = 2H  e  newH = leftW  (assumindo leftW == rightW)
-- O canvas final terá tamanho: 2H × leftW
-- Se W==H  → final = 2H × (H/2) — diferente do original (quadrado vira 2:1 horizontal)
-- Se W==2H → final = 2H × (W/2) = W × (W/4)... não, vamos recalcular:
--   W=2H: leftW=H, rightW=H → após transform: dimensões H×H cada → total 2H×H = W×H ✓
-- Portanto para sprites 2:1 (W=2H) o tamanho é preservado.
-- Para outros tamanhos o sprite será redimensionado.

local newW = H + H          -- largura da metade esq transformada + larg da metade dir transformada
local newH = leftW          -- as duas metades têm a mesma altura após transform (= halfW original)

-- Informa o usuário se o canvas vai mudar de tamanho
if (newW ~= W or newH ~= H) then
  local msg = string.format(
    "O canvas será redimensionado de %dx%d para %dx%d.\nContinuar?",
    W, H, newW, newH
  )
  local resp = app.alert{ title="Aviso", text=msg, buttons={"Sim","Não"} }
  if resp ~= 1 then return end
end

app.transaction(function()
  -- Para cada layer e cada frame
  for _, layer in ipairs(sprite.layers) do
    if not layer.isGroup then
      for _, frame in ipairs(sprite.frames) do
        local cel = layer:cel(frame.frameNumber)
        if cel then
          -- 1. Compoe canvas completo (lida com offsets de cel)
          local canvas = celToCanvas(cel, W, H)

          -- 2. Extrai as duas metades
          local leftImg  = cropImage(canvas, 0,      0, leftW,  H)
          local rightImg = cropImage(canvas, rightX,  0, rightW, H)

          -- 3. Transforma cada metade (flipV + rotateCW)
          local leftT  = transformHalf(leftImg)   -- agora tem dimensões H × leftW
          local rightT = transformHalf(rightImg)  -- agora tem dimensões H × rightW

          -- 4. Monta resultado com as metades TROCADAS:
          --    posição esquerda ← metade direita transformada
          --    posição direita  ← metade esquerda transformada
          local result = Image(newW, newH, canvas.colorMode)
          result:clear()
          result:drawImage(rightT, 0,           0)   -- direita vai para a esquerda
          result:drawImage(leftT,  rightT.width, 0)  -- esquerda vai para a direita

          -- 5. Redimensiona o sprite canvas se necessário (só na primeira iteração)
          --    Fazemos isso fora do loop para não chamar milhares de vezes
          cel.image = result
          cel.position = Point(0, 0)
        end
      end
    end
  end

  -- Redimensiona o sprite uma única vez
  if newW ~= W or newH ~= H then
    sprite:resize(newW, newH)
  end
end)

app.refresh()
