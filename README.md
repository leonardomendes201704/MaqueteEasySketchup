# MaqueteEasySketchup

`MaqueteEasySketchup` e o repositorio do plugin **PlanForge Builder**, uma extensao para SketchUp Pro focada em desenho rapido de maquetes arquitetonicas com fluxo simples, visual e produtivo, inspirado em construtores de planta de jogos como The Sims.

## Visao de negocio

### Problema que o projeto resolve

Desenhar uma planta baixa conceitual no SketchUp com as ferramentas nativas costuma ser lento para usuarios leigos ou intermediarios. O plugin reduz esse atrito com um fluxo de poucos cliques para:

- desenhar paredes em sequencia;
- fechar comodos rapidamente;
- gerar piso 3D e rodape automaticamente;
- abrir portas e janelas com preview ghost;
- ajustar medidas sem reconstruir tudo manualmente.

### Publico-alvo

- arquitetos e designers em fase de estudo preliminar;
- profissionais que fazem maquete volumetrica rapida;
- usuarios de SketchUp Pro que precisam de produtividade sem treinar um fluxo tecnico pesado;
- times que querem evoluir a ferramenta internamente com releases controladas.

### Proposta de valor

- menos cliques para levantar uma planta base;
- geometria organizada em grupos;
- configuracao persistente;
- releases congeladas para rollout gradual em producao;
- base tecnica pronta para evolucao parametrica.

## Visao tecnica

### Stack

- SketchUp Ruby API
- Ruby como base principal da extensao
- `UI::HtmlDialog` para o painel de configuracao e edicao parametrica
- PowerShell para instalacao, empacotamento, versionamento e smoke test

### Namespace principal

- `LeonardoLabs::PlanForgeBuilder`

### Modulos e responsabilidades

- `planforge_builder.rb`
  loader principal registrado no SketchUp
- `planforge_builder/main.rb`
  bootstrap, comandos publicos e carga segura dos modulos
- `planforge_builder/settings.rb`
  configuracoes persistentes e sanitizacao de entradas
- `planforge_builder/layer_manager.rb`
  criacao e atribuicao automatica das tags Walls, Floors e Baseboards
- `planforge_builder/material_manager.rb`
  criacao e aplicacao de materiais automaticos por tipo
- `planforge_builder/geometry_builder.rb`
  construcao de paredes, piso, cortes e metadados geometricos
- `planforge_builder/room_builder.rb`
  geracao automatica de comodos retangulares completos a partir de ancora e dimensoes
- `planforge_builder/room_reconciler.rb`
  reconciliacao de paredes compartilhadas entre comodos do plugin
- `planforge_builder/baseboard_builder.rb`
  geracao e regeneracao de rodapes
- `planforge_builder/room_tool.rb`
  ferramenta de posicionamento com ghost para gerar comodo retangular
- `planforge_builder/wall_tool.rb`
  ferramenta de desenho de paredes com preview e fluxo sequencial
- `planforge_builder/door_tool.rb`
  ferramenta de corte de portas com ghost preview
- `planforge_builder/window_tool.rb`
  ferramenta de corte de janelas com snap magnetico opcional
- `planforge_builder/parametric_editor.rb`
  leitura da selecao e aplicacao de edicoes parametricas
- `planforge_builder/room_regenerator.rb`
  regeneracao completa do comodo a partir dos metadados persistidos
- `planforge_builder/ui.rb`
  painel HtmlDialog e callbacks entre UI e Ruby
- `planforge_builder/commands.rb`
  menu e toolbar
- `planforge_builder/smoke_test.rb`
  validacao automatizada de carregamento e fluxo funcional

### Estrategia de dados

- cada parede e criada como `Sketchup::Group`;
- piso, rodape e aberturas sao relacionados por metadados no dicionario `leonardo_labs_planforge_builder`;
- cada comodo recebe um token para permitir regeneracao posterior;
- portas e janelas ficam registradas como aberturas parametricas da parede;
- grupos de parede, piso e rodape sao organizados em tags separadas;
- materiais sao resolvidos por configuracao e aplicados por tipo de entidade.

## Funcionalidades entregues

- desenho de paredes em sequencia por cliques;
- snap horizontal configuravel;
- espessura, altura e alinhamento de parede configuraveis;
- modo ortogonal em 90 graus;
- preview dinamico da parede durante o desenho;
- piso 3D automatico ao fechar o comodo;
- encaixe do piso pelo lado interno das paredes;
- geracao automatica de comodo retangular por largura e profundidade em metros por padrao PT-BR;
- reconciliacao automatica de paredes compartilhadas entre comodos gerados pelo plugin, evitando sobreposicao visual nas unioes;
- corte de portas com preview ghost;
- corte de janelas com preview ghost e snap magnetico do topo na altura das portas;
- rodape interno automatico e regeneravel;
- rodape apoiado sobre o piso quando o comodo possui piso;
- edicao parametrica de paredes, portas e janelas pelo painel;
- regeneracao completa do comodo a partir da selecao;
- organizacao automatica em tags `Walls`, `Floors` e `Baseboards`;
- materiais automaticos por tipo de elemento, com nome e cor configuraveis;
- toolbar e menu dedicados;
- smoke test automatizado no SketchUp Pro 2020.

## Estrutura do repositorio

```text
CHANGELOG.md
docs/
  BACKLOG.md
dist/
  planforge_builder-0.1.0.rbz
  ...
  planforge_builder-0.8.0.rbz
  planforge_builder-0.8.1.rbz
  planforge_builder-0.9.0.rbz
planforge_builder/
  baseboard_builder.rb
  commands.rb
  diagnostics.rb
  door_tool.rb
  geometry_builder.rb
  main.rb
  room_builder.rb
  room_tool.rb
  layer_manager.rb
  material_manager.rb
  parametric_editor.rb
  room_regenerator.rb
  settings.rb
  smoke_test.rb
  ui.rb
  wall_tool.rb
  window_tool.rb
  html/
    panel.css
    panel.html
    panel.js
  icons/
planforge_builder.rb
releases/
  0.1.0/
  ...
  0.8.0/
  0.8.1/
  0.9.0/
scripts/
  capture-release.ps1
  export-release-notes.ps1
  install-version.ps1
  package.ps1
  run-compile-probe.ps1
  run-installed-smoke-test.ps1
  run-startup-probe.ps1
```

## Versionamento e rollout

O projeto foi estruturado para rollout gradual em producao.

- cada release fica congelada em `releases/<versao>`;
- cada release tem `RELEASE_NOTES.md`;
- o changelog consolidado fica em [CHANGELOG.md](CHANGELOG.md);
- o backlog vivo fica em [docs/BACKLOG.md](docs/BACKLOG.md);
- os pacotes `.rbz` ficam em `dist/`;
- apenas uma versao deve estar instalada de cada vez no SketchUp.

### Comandos uteis

Listar releases disponiveis:

```powershell
Set-Location "C:\Leonardo\Labs\Sketchup Plugins"
.\scripts\install-version.ps1 -List
```

Instalar uma release:

```powershell
.\scripts\install-version.ps1 -Version 0.9.0
```

Congelar o estado atual como nova release:

```powershell
.\scripts\capture-release.ps1 -Version 0.9.0
```

Empacotar uma release em `.rbz`:

```powershell
.\scripts\package.ps1 -Version 0.9.0
```

Rodar validacao automatizada da versao instalada:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-installed-smoke-test.ps1
```

## Changelog resumido

### 0.9.0

- reconciliacao automatica de paredes compartilhadas entre comodos do plugin;
- paredes proxy para reaproveitar a parede fisica existente sem duplicacao;
- regeneracao e rodape passam a respeitar paredes compartilhadas.

### 0.8.1

- gerador de comodo com entrada em metros por padrao PT-BR;
- parser proprio para `m`, `cm` e `mm`, tratando valores sem unidade como metros;
- ghost e VCB do gerador exibem dimensoes em metros sem depender da unidade global do SketchUp.

### 0.8.0

- comando de gerar comodo com modal de medidas;
- ghost de posicionamento ancorado no canto inferior do comodo;
- geracao automatica das 4 paredes com piso e rodape.

### 0.7.1

- tags separadas `Walls`, `Floors` e `Baseboards`;
- atribuicao automatica dessas tags na criacao e regeneracao;
- geometria interna mantida em `Layer0`.

### 0.7.0

- materiais automaticos por tipo de elemento;
- nomes e cores configuraveis para parede, piso e rodape;
- aplicacao automatica dos materiais ao criar ou regenerar o comodo.

### 0.6.0

- edicao parametrica de paredes, portas e janelas;
- regeneracao completa do comodo a partir da selecao;
- smoke test ampliado para validar os fluxos parametricos.

### 0.5.1

- rodape passa a nascer sobre o topo do piso quando o comodo possui piso.

### 0.5.0

- rodape interno automatico;
- comando de regeneracao manual de rodape;
- metadados de comodo para reconstrucoes futuras.

### 0.4.0

- ferramenta de janela com preview ghost;
- snap magnetico do topo da janela na altura das portas.

### 0.3.0

- ferramenta de corte de porta com preview ghost e remocao real de volume.

### 0.2.2

- piso encaixado pelo lado interno das paredes;
- base do piso alinhada com a base das paredes.

### 0.2.1

- correcao de encontros de canto em miter entre paredes sequenciais.

### 0.2.0

- estrategia de releases congeladas;
- piso 3D automatico com espessura configuravel.

### 0.1.0

- MVP inicial da extensao com paredes, painel, menu, toolbar e smoke test.

Para o historico completo, consulte [CHANGELOG.md](CHANGELOG.md).

## Validacao atual

Validado localmente em:

- SketchUp Pro 2020 (`20.0.363`)
- Windows

Ultima validacao automatizada conhecida:

- release `0.9.0`
- smoke test com status `ok`
- cobertura de parede, porta, janela, piso, rodape, tags, materiais, edicao parametrica, geracao automatica, reconciliacao entre comodos e regeneracao de comodo

## Manutencao

- configuracoes persistem via `Sketchup.write_default`;
- o log local fica em `%LOCALAPPDATA%\\PlanForgeBuilder\\planforge_builder.log`;
- o gatilho do smoke test e `%TEMP%\\planforge_builder_smoke_test.json`;
- o resultado do smoke test e `%TEMP%\\planforge_builder_smoke_test_result.json`;
- novas features devem atualizar `CHANGELOG.md`, `docs/BACKLOG.md` e, quando aplicavel, `RELEASE_NOTES.md`.

## Proximas evolucoes sugeridas

- presets de ambientes e familias de paredes;
- biblioteca reutilizavel de portas e janelas;
- pavimentos e niveis;
- medidas e area do comodo sempre visiveis;
- handles visuais para editar paredes e aberturas direto no modelo;
- geracao externa ou em ambos os lados para rodape;
- migracao automatica de metadados entre versoes.
