# Nano Banana Tibia Spritesheet Skill

## Descrição
Skill para usar o Nano Banana na criação/edição de spritesheets de montarias do jogo Tibia.

## Base de Parâmetros
Existem 3 spritesheets de montarias do jogo Tibia. A estrutura padrão de cada spritesheet é a seguinte:

### Colunas (Direção)
- **1ª Coluna:** Posição Norte
- **2ª Coluna:** Posição Leste
- **3ª Coluna:** Posição Sul
- **4ª Coluna:** Posição Oeste

### Linhas (Ação)
- **1ª Linha:** Personagem Parado (Idle)
- **2ª Linha:** Movimento/Walk (Frame 1)
- **3ª Linha:** Movimento/Walk (Frame 2)

## Regras Obrigatórias
Sempre que for criar ou manipular estas spritesheets, aplique rigorosamente as seguintes regras:
1. **Preservar proporção:** Manter a escala correta dos sprites.
2. **Preservar densidade de pixels:** Não alterar a resolução nativa dos pixels.
3. **Preservar aspecto pixelado:** Não usar anti-aliasing; manter as bordas duras características de pixel art.
4. **Fundo transparente:** Utilizar rosa absoluto (Hex: `#FF00FF` / RGB: `255, 0, 255`) para gerar a transparência de fundo.
