--------------------------------------------------------------------------------
-- outfit_sul_oeste.lua
--
-- Reduz uma spritesheet de outfit 1024x1728 para 512x576, mantendo apenas as
-- direcoes SUL e OESTE e apenas os frames escolhidos.
--
-- ORIGEM (1024x1728 = 16 colunas x 27 linhas de 64x64 = 432 sprites)
--   ordem linear, da esquerda para a direita, quebrando linha ao encher:
--     para cada frame (9):
--       para cada camada (6): personagem, addon1, addon2,
--                             montado, montado addon1, montado addon2
--         para cada direcao (4): norte, leste, sul, oeste
--           sprite, mascara
--   -> 6 * 4 * 2 = 48 celulas por frame = exatamente 3 linhas por frame.
--
-- DESTINO (512x576 = 8 colunas x 9 linhas de 64x64 = 72 sprites)
--     para cada frame de OUT_FRAMES (3):
--       para cada camada de OUT_LAYERS (6), na ordem
--         personagem, montado, addon1, montado addon1, addon2, montado addon2:
--           sul, mascara sul, oeste, mascara oeste
--   -> cada par (a pe + montado) ocupa exatamente 1 linha de 8 celulas:
--        linha 1: personagem sul, mascara, personagem oeste, mascara,
--                 montado sul, mascara, montado oeste, mascara
--        linha 2: o mesmo para o addon1
--        linha 3: o mesmo para o addon2
--   -> 6 * 2 * 2 = 24 celulas por frame = exatamente 3 linhas por frame.
--
-- USO: abra a spritesheet no Aseprite e rode File > Scripts > outfit_sul_oeste
--------------------------------------------------------------------------------

--============================ CONFIGURACAO ====================================

-- Frames que serao exportados (1-based). Padrao pedido: 1, 2 e 6.
local OUT_FRAMES = { 1, 2, 6 }

-- Direcoes exportadas, na ordem de saida (1=norte, 2=leste, 3=sul, 4=oeste).
local OUT_DIRS = { 3, 4 }

-- Camadas exportadas, na ordem de saida (1-based, conforme a origem):
--   1 = personagem      2 = addon1            3 = addon2
--   4 = montado         5 = montado addon1    6 = montado addon2
-- Padrao pedido: cada camada a pe seguida da sua versao montada.
local OUT_LAYERS = { 1, 4, 2, 5, 3, 6 }

local CELL = 64 -- tamanho do sprite

local SRC_FRAMES  = 9  -- frames na spritesheet de origem
local SRC_LAYERS  = 6  -- personagem, addon1, addon2, montado, mont.addon1, mont.addon2
local SRC_DIRS    = 4  -- norte, leste, sul, oeste
local SRC_VARIANT = 2  -- sprite + mascara

local SRC_COLS = 16 -- 1024 / 64
local DST_COLS = 8  -- 512  / 64

--==============================================================================

local src = app.activeSprite
if not src then
  app.alert("Abra a spritesheet de origem antes de rodar o script.")
  return
end

local expectedW = SRC_COLS * CELL
local expectedH = (SRC_FRAMES * SRC_LAYERS * SRC_DIRS * SRC_VARIANT / SRC_COLS) * CELL

if src.width ~= expectedW or src.height ~= expectedH then
  local ok = app.alert{
    title = "Tamanho inesperado",
    text = {
      "A spritesheet aberta tem " .. src.width .. "x" .. src.height .. ".",
      "O script espera " .. expectedW .. "x" .. expectedH .. ".",
      "Continuar mesmo assim?"
    },
    buttons = { "Continuar", "Cancelar" }
  }
  if ok ~= 1 then return end
end

--------------------------------------------------------------------------------
-- Achata o frame ativo da origem em uma unica imagem para poder recortar.
--------------------------------------------------------------------------------
local srcFrame = app.activeFrame or src.frames[1]
local srcImg = Image(src.width, src.height, src.colorMode)
srcImg:clear()
srcImg:drawSprite(src, srcFrame, Point(0, 0))

--------------------------------------------------------------------------------
-- Copia uma celula 64x64 de srcImg para dstImg, pixel a pixel (copia exata,
-- sem blend: mascaras e transparencia sao preservadas como estao).
--------------------------------------------------------------------------------
local function blitCell(dstImg, srcIndex, dstIndex)
  local sx = (srcIndex % SRC_COLS) * CELL
  local sy = math.floor(srcIndex / SRC_COLS) * CELL
  local dx = (dstIndex % DST_COLS) * CELL
  local dy = math.floor(dstIndex / DST_COLS) * CELL

  if sx + CELL > srcImg.width or sy + CELL > srcImg.height then
    return -- fora da origem: deixa vazio
  end

  for y = 0, CELL - 1 do
    for x = 0, CELL - 1 do
      dstImg:drawPixel(dx + x, dy + y, srcImg:getPixel(sx + x, sy + y))
    end
  end
end

--------------------------------------------------------------------------------
-- Indice linear na origem.
--   frame  : 0-based
--   layer  : 0-based (0..5)
--   dir    : 0-based (0=norte, 1=leste, 2=sul, 3=oeste)
--   variant: 0 = sprite, 1 = mascara
--------------------------------------------------------------------------------
local function srcIndexOf(frame, layer, dir, variant)
  return frame   * (SRC_LAYERS * SRC_DIRS * SRC_VARIANT)
       + layer   * (SRC_DIRS * SRC_VARIANT)
       + dir     * SRC_VARIANT
       + variant
end

--------------------------------------------------------------------------------
-- Monta a spritesheet de destino.
--------------------------------------------------------------------------------
local outDirCount = #OUT_DIRS
local cellsPerFrame = #OUT_LAYERS * outDirCount * SRC_VARIANT
local totalCells = #OUT_FRAMES * cellsPerFrame
local dstW = DST_COLS * CELL
local dstH = math.ceil(totalCells / DST_COLS) * CELL

local dst = Sprite(dstW, dstH, src.colorMode)
dst.filename = "outfit_sul_oeste_" .. dstW .. "x" .. dstH

if src.colorMode == ColorMode.INDEXED and src.palettes[1] then
  dst:setPalette(src.palettes[1])
end

local dstImg = Image(dstW, dstH, src.colorMode)
dstImg:clear()

local dstIndex = 0
for _, frameNo in ipairs(OUT_FRAMES) do
  local f = frameNo - 1
  for _, layerNo in ipairs(OUT_LAYERS) do
    local layer = layerNo - 1
    for _, dirNo in ipairs(OUT_DIRS) do
      local d = dirNo - 1
      for variant = 0, SRC_VARIANT - 1 do -- 0 = sprite, 1 = mascara
        blitCell(dstImg, srcIndexOf(f, layer, d, variant), dstIndex)
        dstIndex = dstIndex + 1
      end
    end
  end
end

dst.cels[1].image = dstImg
dst.layers[1].name = "sheet"

app.refresh()

app.alert{
  title = "Concluido",
  text = {
    "Spritesheet gerada: " .. dstW .. "x" .. dstH,
    "Frames: " .. table.concat(OUT_FRAMES, ", "),
    "Celulas escritas: " .. dstIndex .. " de " .. totalCells
  }
}
