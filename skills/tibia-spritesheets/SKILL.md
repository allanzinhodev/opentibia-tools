---
name: tibia-spritesheets
description: Layout das spritesheets do Tibia (outfits, addons, montarias, máscaras, paredes) e convenções dos scripts Aseprite do usuário. Use ao ler, converter, recortar ou gerar spritesheets/sprites do Tibia ou OpenTibia, ao mexer em máscaras de outfit (amarelo/vermelho/verde/azul), ou ao escrever/alterar scripts Aseprite para essas sheets.
---

# Spritesheets do Tibia

Referência para as sheets com que o usuário trabalha. As coordenadas são em pixels, com origem no topo-esquerdo e células indexadas a partir de 0. Antes de alterar um layout, confira o script correspondente em `%APPDATA%\Aseprite\scripts` (ver **Ferramentas**): é ele que define o layout.

## Célula, direção e máscara

- **Célula**: outfits e montarias usam 64×64. O mapa (tiles, paredes) usa uma grade de 32×32.
- **Direções**, sempre nesta ordem: Norte, Leste, Sul, Oeste (índices 0–3).
- **Par sprite + máscara**: cada direção ocupa duas células vizinhas, com o desenho em `x` e a máscara em `x + 64`.
- **Leste e Oeste são derivados**: Leste = transposta de Sul e Oeste = transposta de Norte. A transposição vale dentro da célula de 64×64, `(x, y) → (y, x)`, o mesmo que flip vertical seguido de rotação de 90° no sentido horário. Ela se desfaz sozinha. Por isso os arquivos de edição só guardam Norte e Sul.

## Máscara de cor (colorização do outfit)

O cliente pinta o outfit pela máscara. Cada cor pura marca uma parte:

| Cor da máscara | Parte do outfit |
| --- | --- |
| `#FFFF00` amarelo | cabeça |
| `#FF0000` vermelho | corpo |
| `#00FF00` verde | pernas |
| `#0000FF` azul | pés |

Na máscara só entram essas cores puras e o transparente, sem anti-aliasing nem cores intermediárias. No desenho, os pixels de uma área colorizável ficam em tons de cinza, porque o cliente multiplica esses tons pela cor escolhida. O script `Gerar Mascara.lua` faz as duas coisas: deixa os pixels escolhidos cinza e 10% mais claros e pinta a máscara com +64 px em X.

## Sheet de outfit (ordem linear)

A largura é 1024 px, ou seja 16 células por linha, lidas da esquerda para a direita e quebrando a linha ao encher:

```
para cada frame:
  para cada categoria (6): Personagem, Addon 1, Addon 2,
                           Montado, Montado Addon 1, Montado Addon 2
    para cada direção (4): Norte, Leste, Sul, Oeste
      sprite, máscara
```

São 6 × 4 × 2 = 48 células por frame, exatamente 3 linhas. Cada par categoria/frame forma uma **faixa** de 512×64 (8 células), e cabem 2 faixas por linha. A altura indica quantos frames a sheet tem:

| Tamanho | Frames | Observação |
| --- | --- | --- |
| 1024×576 | 3 | |
| 1024×1728 | 9 | |
| 1024×3072 | 16 | Idle = frames 1–8, walk = frames 9–16 |

Com a ordem padrão por frame (`faixa = frame*6 + categoria`), a célula da direção `d`, com `m` = 0 para o desenho e 1 para a máscara, fica em:

```
x = (faixa % 2) * 512 + d * 128 + m * 64
y = floor(faixa / 2) * 64
```

O `Montar Outfit.lua` também aceita a ordem por categoria (`faixa = categoria*16 + frame`). Quando a ordem de uma sheet nova não estiver clara, pergunte ao usuário qual é.

## Layouts derivados

- **Arquivo de edição** (`Montar Outfit.lua`): 256×64 com 16 frames. As colunas são Norte, Sul, Norte Montado e Sul Montado. Há 6 layers, desenho e máscara para Personagem, Addon 1 e Addon 2. As layers de máscara ficam em Multiply a 90% (230), mas isso é só para visualizar: os pixels são copiados crus. Para voltar à sheet de 1024×3072, o script reconstrói Leste e Oeste pela transposição.
- **Sul/Oeste reduzida** (`outfit_sul_oeste*.lua`): 512×576, 8 colunas por 9 linhas, 3 frames. Cada linha tem Sul, máscara Sul, Oeste e máscara Oeste a pé, seguidos dos mesmos quatro montado. As linhas seguem a ordem Personagem, Addon 1, Addon 2.
- **4 → 8 colunas** (`converter_spritesheet_8colunas.lua`): a entrada tem Sul, máscara S, Oeste e máscara O. A saída começa com as versões transpostas de Oeste e Sul (com as máscaras) e depois traz as originais.

## Montarias

Cada sheet tem 4 colunas e 3 linhas. As colunas são as direções Norte, Leste, Sul e Oeste. As linhas são Idle, Walk 1 e Walk 2. A escala, a densidade de pixel e as bordas duras têm de ser preservadas. Nas imagens geradas por IA, o fundo transparente é rosa absoluto `#FF00FF`.

## Paredes e objetos maiores que um tile

A grade é de 32 px. Um sprite maior que 32×32 cresce para cima e para a esquerda a partir do tile âncora, que é o 32×32 do canto inferior direito. Tiles vizinhos ficam sempre a 32 px um do outro, e o tile à direita ou abaixo é desenhado por cima. A extensão `tibia-wall-tiled` faz um preview com essas regras.

## Ferramentas

- **Scripts instalados**: `%APPDATA%\Aseprite\scripts` (Aseprite 1.3.18.6, versão da Steam). Esta é a pasta que **File > Scripts > Open Scripts Folder** abre.
- **Repositório**: https://github.com/allanzinhodev/opentibia-tools. O README tem uma seção por script, em inglês.
- **Estilo dos scripts**: Lua para Aseprite 1.3+, com textos da interface em português. Eles copiam valores crus de pixel, preservando os índices da paleta. Funcionam em RGB e Indexado e agrupam tudo em `app.transaction` para que um Ctrl+Z desfaça a operação inteira. Um script que vira biblioteca expõe `M` quando roda com `app.params.mode == "library"`.
- **Teste sem interface**:

  ```
  "C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe" -b --script-param mode=library --script teste.lua
  ```

  No `teste.lua`, carregue o módulo com `dofile`. Monte sprites pequenos, chame as funções e imprima `ok`/`FAIL`.
