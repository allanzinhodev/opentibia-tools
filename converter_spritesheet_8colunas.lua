-- Script Aseprite: Converte spritesheet de 4 colunas para 8 colunas com flip
-- 4 colunas originais: 
--   0: Sul, 1: Mascara Sul, 2: Oeste, 3: Mascara Oeste
-- 8 colunas finais: 
--   0: Oeste Flip, 1: Mascara Oeste Flip, 2: Sul Flip, 3: Mascara Sul Flip
--   4: Sul, 5: Mascara Sul, 6: Oeste, 7: Mascara Oeste

-- Função para rotacionar 90 graus no sentido horário e aplicar flip vertical
local function flipCell(sourceImage, srcX, srcY, destImage, destX, destY)
    for y = 0, 63 do
        for x = 0, 63 do
            local pixel = sourceImage:getPixel(srcX + x, srcY + y)
            
            -- Rotação 90 graus sentido horário (âncora no centro 31.5, 31.5):
            local rotX = 63 - y
            local rotY = x
            
            -- Flip Horizontal (inverte o X):
            local flipX = 63 - rotX
            local flipY = rotY
            
            destImage:putPixel(destX + flipX, destY + flipY, pixel)
        end
    end
end

local function copyCell(sourceImage, srcX, srcY, destImage, destX, destY)
    for y = 0, 63 do
        for x = 0, 63 do
            local pixel = sourceImage:getPixel(srcX + x, srcY + y)
            destImage:putPixel(destX + x, destY + y, pixel)
        end
    end
end

-- Verifica se há um sprite ativo
local sprite = app.activeSprite
if not sprite then
    app.alert("Nenhum sprite ativo!")
    return
end

-- Verifica se as dimensões são múltiplas de 64
if sprite.width % 64 ~= 0 or sprite.height % 64 ~= 0 then
    app.alert("A largura ou altura do sprite não é múltipla de 64! (Tamanho atual: " .. sprite.width .. "x" .. sprite.height .. ")")
    return
end

-- Verifica se tem as 4 colunas originais (256 de largura)
local cols = sprite.width / 64
if cols ~= 4 then
    app.alert("O sprite atual não tem 4 colunas! (Largura esperada: 256, atual: " .. sprite.width .. ")")
    return
end

-- Cria o novo sprite com o dobro da largura (8 colunas)
local rows = math.floor(sprite.height / 64)
local newWidth = 8 * 64
local newHeight = sprite.height

local newSprite = Sprite(newWidth, newHeight, sprite.colorMode)
if sprite.colorMode == ColorMode.INDEXED then
    newSprite:setPalette(sprite.palettes[1])
end

-- Pega uma imagem achatada do sprite original (frame atual)
local sourceImage = Image(sprite.spec)
sourceImage:drawSprite(sprite, app.activeFrame)

-- Cria a imagem de destino
local destImage = Image(newSprite.spec)
destImage:clear()

-- Processa as células linha por linha
for r = 0, rows - 1 do
    local srcY = r * 64
    local destY = r * 64
    
    -- Coluna 0: Posição Oeste Flip (da col 2 original)
    flipCell(sourceImage, 2 * 64, srcY, destImage, 0 * 64, destY)
    
    -- Coluna 1: Mascara Oeste Flip (da col 3 original)
    flipCell(sourceImage, 3 * 64, srcY, destImage, 1 * 64, destY)
    
    -- Coluna 2: Posição Sul Flip (da col 0 original)
    flipCell(sourceImage, 0 * 64, srcY, destImage, 2 * 64, destY)
    
    -- Coluna 3: Mascara Sul Flip (da col 1 original)
    flipCell(sourceImage, 1 * 64, srcY, destImage, 3 * 64, destY)
    
    -- Coluna 4: Posição Sul (da col 0 original)
    copyCell(sourceImage, 0 * 64, srcY, destImage, 4 * 64, destY)
    
    -- Coluna 5: Mascara Sul (da col 1 original)
    copyCell(sourceImage, 1 * 64, srcY, destImage, 5 * 64, destY)
    
    -- Coluna 6: Posição Oeste (da col 2 original)
    copyCell(sourceImage, 2 * 64, srcY, destImage, 6 * 64, destY)
    
    -- Coluna 7: Mascara Oeste (da col 3 original)
    copyCell(sourceImage, 3 * 64, srcY, destImage, 7 * 64, destY)
end

-- Aplica a nova imagem ao sprite
app.transaction(function()
    -- Garante que existe pelo menos uma camada
    local layer = newSprite.layers[1]
    if not layer then
        layer = newSprite:newLayer()
    end
    layer.name = "Spritesheet Convertida"
    
    -- Cria um novo cel com a imagem montada
    newSprite:newCel(layer, 1, destImage, Point(0, 0))
end)

app.alert("Spritesheet de 8 colunas gerada com sucesso!")
