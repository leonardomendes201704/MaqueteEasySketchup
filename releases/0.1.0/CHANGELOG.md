# Changelog

Todas as versoes publicadas do PlanForge Builder devem ser registradas aqui.

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
