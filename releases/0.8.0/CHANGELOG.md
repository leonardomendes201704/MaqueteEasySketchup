# Changelog

Todas as versoes publicadas do PlanForge Builder devem ser registradas aqui.

## [0.8.0] - 2026-03-25

### Implementado
- Novo comando `Gerar comodo` no menu, toolbar e painel do plugin.
- Novo fluxo modal para informar largura e profundidade internas do comodo antes do posicionamento.
- Nova ferramenta `RoomTool` com ghost de posicionamento ancorado no canto inferior do comodo.
- Novo servico `RoomBuilder` para criar automaticamente as quatro paredes, o piso e o rodape de um comodo retangular.

### Ajustado
- Smoke test ampliado para validar a selecao da ferramenta de comodo e a geracao automatica de um comodo completo a partir de ancora e dimensoes.

## [0.7.1] - 2026-03-25

### Implementado
- Novo modulo `LayerManager` para criar e manter as tags `Walls`, `Floors` e `Baseboards`.

### Ajustado
- Paredes, pisos e rodapes agora sao organizados automaticamente em tags separadas ao criar ou regenerar o comodo.
- A geometria interna dos grupos continua em `Layer0`, preservando a boa pratica de manter faces e arestas em `Untagged`.
- Smoke test ampliado para validar atribuicao de tags e preservacao dessa organizacao apos regeneracao.

## [0.7.0] - 2026-03-25

### Implementado
- Novo modulo `MaterialManager` para criar e atualizar materiais automaticos por tipo de elemento.
- Novas configuracoes persistentes para ativar ou desativar materiais automaticos e definir nome e cor de parede, piso e rodape.
- Painel HtmlDialog ampliado com controles de material para os principais tipos de geometria do plugin.

### Ajustado
- Paredes, pisos e rodapes agora recebem material automaticamente ao criar ou regenerar o comodo.
- Smoke test ampliado para validar criacao, aplicacao e preservacao dos materiais apos regeneracao.

## [0.6.0] - 2026-03-25

### Implementado
- Novo backlog vivo em `docs/BACKLOG.md`, para acompanhar o roadmap do plugin e marcar cada entrega concluida.
- Novo editor parametrico no painel para a parede selecionada, com leitura da selecao atual, ajuste de espessura, altura e alinhamento.
- Lista de portas e janelas registradas na parede selecionada, com edicao de largura, altura, posicao e peitoril diretamente no painel.
- Novo servico de regeneracao completa do comodo, recalculando paredes, piso e rodape a partir dos metadados persistidos do ambiente.

### Ajustado
- Reconstrucao de paredes passou a preservar as aberturas parametricas registradas na parede.
- Smoke test ampliado para validar leitura da selecao, edicao parametrica de parede, porta e janela, e regeneracao completa do comodo.

## [0.5.1] - 2026-03-25

### Ajustado
- Quando existe piso no comodo, o rodape agora nasce sobre a face superior do piso, em vez de partir do `z=0` da parede.
- A interrupcao do rodape por aberturas que chegam ate a base passou a considerar a nova cota do rodape quando ele esta apoiado sobre o piso.
- Smoke test ampliado para validar explicitamente que a base do rodape coincide com o topo do piso.

## [0.5.0] - 2026-03-25

### Implementado
- Rodape interno configuravel com geracao automatica ao fechar o comodo.
- Novo comando `Gerar rodape` para regenerar o rodape a partir de uma parede, piso ou rodape de um comodo criado pelo plugin.
- Novas configuracoes persistentes para altura e profundidade do rodape.
- Metadados de comodo gravados nas paredes e no piso para permitir regeneracao posterior.

### Ajustado
- O rodape agora interrompe automaticamente nos trechos com aberturas que descem ate a base, como portas.
- Smoke test ampliado para validar criacao, volume esperado e regeneracao do rodape.

## [0.4.0] - 2026-03-25

### Implementado
- Nova ferramenta de corte de janela com comando proprio no menu e na toolbar do plugin.
- Preview ghost da janela com posicionamento livre na altura ao passar o mouse sobre paredes do PlanForge Builder.
- Novas configuracoes persistentes para largura e altura padrao de janela.

### Ajustado
- O topo da janela agora possui snap magnetico na altura das portas quando o cursor passa perto, sem bloquear a movimentacao livre fora da faixa de snap.
- Smoke test ampliado para validar selecao da ferramenta de janela, snap do topo e corte real de volume na parede.

## [0.3.0] - 2026-03-25

### Implementado
- Nova ferramenta de corte de porta com comando proprio no menu e na toolbar do plugin.
- Preview ghost do recorte de porta ao passar o mouse sobre paredes do PlanForge Builder.
- Corte confirmado por clique, removendo volume real da parede em vez de apenas desenhar guia.
- Novas configuracoes persistentes para largura e altura padrao de porta.
- Compatibilidade com paredes antigas por inferencia de metadados da parede a partir da geometria quando necessario.

### Ajustado
- Smoke test ampliado para validar selecao da ferramenta de porta e reducao de volume apos o corte.

## [0.2.2] - 2026-03-25

### Ajustado
- O piso agora usa o contorno interno das paredes com base no alinhamento configurado, evitando invasao sobre a espessura das paredes.
- A extrusao do piso passou a subir a partir da base das paredes, mantendo a base do piso em `z=0`.
- Smoke test ampliado para validar o inset do piso e a nova posicao vertical do volume.

## [0.2.1] - 2026-03-25

### Ajustado
- Juncoes entre paredes sequenciais agora sao reprojetadas com encontro em miter nas esquinas, eliminando folgas visuais e sobreposicoes nas quinas.
- O preview da parede passou a considerar o segmento anterior e o fechamento do comodo para antecipar melhor o encontro de cantos.
- Smoke test ampliado para validar compartilhamento correto dos pontos de junta entre duas paredes consecutivas.

## [0.2.0] - 2026-03-25

### Implementado
- Fluxo de releases versionadas em `releases\<versao>` com scripts para instalar, empacotar e congelar versoes.
- Piso 3D automatico ao fechar um comodo, criado como grupo separado com extrusao para baixo.
- Nova configuracao `Espessura do piso (cm)` com valor padrao de `12 cm`.
- Nova configuracao `Criar piso automatico ao fechar o comodo`.
- Smoke test ampliado para validar selecao da ferramenta e criacao de piso.
- Rollback e rollout por script, permitindo instalar `0.1.0` ou `0.2.0` sob demanda.

### Ajustado
- O smoke test agora restaura as configuracoes do usuario ao final.
- Documentacao atualizada para explicar versionamento e empacotamento por release.

## [0.1.0] - 2026-03-25

### Implementado
- Estrutura inicial completa da extensao SketchUp em Ruby com namespace `LeonardoLabs::PlanForgeBuilder`.
- Ferramenta de desenho de paredes com fluxo em sequencia por cliques.
- Snap horizontal configuravel.
- Espessura de parede configuravel.
- Altura de parede configuravel com criacao 3D por extrusao.
- Alinhamento da parede por centro, face esquerda ou face direita.
- Painel `HtmlDialog` com configuracoes em portugues do Brasil.
- Menu e toolbar dedicados no SketchUp.
- Log de diagnostico e smoke test para validar carregamento da extensao.
