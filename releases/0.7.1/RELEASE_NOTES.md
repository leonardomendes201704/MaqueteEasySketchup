# PlanForge Builder Release Notes

## [0.7.1] - 2026-03-25

### Implementado
- Novo modulo `LayerManager` para criar e manter as tags `Walls`, `Floors` e `Baseboards`.

### Ajustado
- Paredes, pisos e rodapes agora sao organizados automaticamente em tags separadas ao criar ou regenerar o comodo.
- A geometria interna dos grupos continua em `Layer0`, preservando a boa pratica de manter faces e arestas em `Untagged`.
- Smoke test ampliado para validar atribuicao de tags e preservacao dessa organizacao apos regeneracao.
