local sprite = app.activeSprite
if not sprite then
    app.alert("Nenhum sprite ativo.")
    return
end

-- Configurações iniciais
local CELL_S = 64
local stripW = 512
local stripH = 576

-- Cria imagem que representará o spritesheet na vertical (512x576)
local stripImg = Image(stripW, stripH, sprite.colorMode)

if sprite.colorMode == ColorMode.RGB or sprite.colorMode == ColorMode.GRAY then
    stripImg:clear()
else
    stripImg:clear(sprite.transparentColor)
end

-- Se o sprite atual já é o vertical strip (512x576)
if sprite.width == stripW and sprite.height == stripH then
    local flat = Image(sprite.spec)
    flat:drawSprite(sprite, 1)
    stripImg:drawImage(flat, 0, 0)
else
    -- Se for o sprite animado com múltiplos frames (ex: 512x192, 3 frames)
    for i, frame in ipairs(sprite.frames) do
        local flat = Image(sprite.spec)
        flat:drawSprite(sprite, frame.frameNumber)
        local destY = (i - 1) * sprite.height
        stripImg:drawImage(flat, 0, destY)
    end
end

-- Nova imagem de saída (1024x576)
local outW = 1024
local outH = 576
local outImg = Image(outW, outH, sprite.colorMode)

if sprite.colorMode == ColorMode.RGB or sprite.colorMode == ColorMode.GRAY then
    outImg:clear()
else
    outImg:clear(sprite.transparentColor)
end

-- Função de flip solicitada:
-- "flip vertical e rotaciona -90 graus com ancora no centro"
local function get_flipped_coords(x, y)
    -- 1. Flip vertical (inverte o eixo Y)
    local y_flip = (CELL_S - 1) - y
    local x_flip = x
    
    -- 2. Rotaciona 90 graus (horário) com âncora no centro (31.5, 31.5)
    -- Transformação resultante equivalente a x' = y, y' = x
    local x_new = y
    local y_new = x
    
    return x_new, y_new
end

-- Função que processa um "Lote" de 4 colunas e o converte para o lote de 8 colunas impresso à direita
local function process_batch(srcX, srcY, destX, destY)
    local IN_SOUTH = 0
    local IN_MASK_S = 1
    local IN_WEST = 2
    local IN_MASK_W = 3
    
    -- Mapeamento das 8 colunas de saída baseadas no pedido:
    -- {Índice da coluna original, aplicar função flip}
    local outMap = {
        {IN_WEST, true},    -- 1 Coluna: oeste com flip
        {IN_MASK_W, true},  -- 2 Coluna: mascara oeste com flip
        {IN_SOUTH, true},   -- 3 Coluna: sul com flip
        {IN_MASK_S, true},  -- 4 Coluna: mascara sul com flip
        {IN_SOUTH, false},  -- 5 Coluna: sul
        {IN_MASK_S, false}, -- 6 Coluna: mascara sul
        {IN_WEST, false},   -- 7 Coluna: oeste
        {IN_MASK_W, false}  -- 8 Coluna: mascara oeste
    }
    
    for outCol = 0, 7 do
        local inCol = outMap[outCol + 1][1]
        local doFlip = outMap[outCol + 1][2]
        
        local sx_base = srcX + inCol * CELL_S
        local dx_base = destX + outCol * CELL_S
        
        for y = 0, CELL_S - 1 do
            for x = 0, CELL_S - 1 do
                local sx, sy = x, y
                
                if doFlip then
                    -- Como a função matemática é o seu próprio inverso,
                    -- podemos usá-la para encontrar o pixel de origem.
                    sx, sy = get_flipped_coords(x, y)
                end
                
                local px = stripImg:getPixel(sx_base + sx, srcY + sy)
                outImg:drawPixel(dx_base + x, destY + y, px)
            end
        end
    end
end

-- O loop principal percorre os 3 frames verticais
for f = 0, 2 do
    local srcBlockY = f * 3 * CELL_S
    local destBlockY = f * 3 * CELL_S
    
    -- Linha 1 de saída: Personagem e Addon 1
    -- Lote 1: só o personagem (Linha original 0, colunas 0 a 3)
    process_batch(0, srcBlockY + 0*CELL_S, 0, destBlockY + 0*CELL_S)
    -- Lote 2: Addon 1 (Linha original 1, colunas 0 a 3)
    process_batch(0, srcBlockY + 1*CELL_S, 8*CELL_S, destBlockY + 0*CELL_S)
    
    -- Linha 2 de saída: Addon 2 e Montaria (Personagem na montaria)
    -- Lote 1: Addon 2 (Linha original 2, colunas 0 a 3)
    process_batch(0, srcBlockY + 2*CELL_S, 0, destBlockY + 1*CELL_S)
    -- Lote 2: Montaria (Linha original 0, colunas 4 a 7)
    process_batch(4*CELL_S, srcBlockY + 0*CELL_S, 8*CELL_S, destBlockY + 1*CELL_S)
    
    -- Linha 3 de saída: Addon 1 na montaria e Addon 2 na montaria
    -- Lote 1: Addon 1 da montaria (Linha original 1, colunas 4 a 7)
    process_batch(4*CELL_S, srcBlockY + 1*CELL_S, 0, destBlockY + 2*CELL_S)
    -- Lote 2: Addon 2 da montaria (Linha original 2, colunas 4 a 7)
    process_batch(4*CELL_S, srcBlockY + 2*CELL_S, 8*CELL_S, destBlockY + 2*CELL_S)
end

-- Gera o sprite final e abre em nova aba
local newSprite = Sprite(outW, outH, sprite.colorMode)
if sprite.colorMode == ColorMode.INDEXED then
    newSprite:setPalette(sprite.palettes[1])
end

newSprite.cels[1].image = outImg
newSprite.cels[1].position = Point(0, 0)
app.activeSprite = newSprite

-- Tenta ajustar o zoom, opcional
if app.command.FitToScreen then
    app.command.FitToScreen()
end

app.alert("Conversão concluída com sucesso! Spritesheet gerado: 1024x576.")
