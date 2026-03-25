# PlanForge Builder Release Notes

## [0.6.0] - 2026-03-25

### Implementado
- Novo backlog vivo em `docs/BACKLOG.md`, para acompanhar o roadmap do plugin e marcar cada entrega concluida.
- Novo editor parametrico no painel para a parede selecionada, com leitura da selecao atual, ajuste de espessura, altura e alinhamento.
- Lista de portas e janelas registradas na parede selecionada, com edicao de largura, altura, posicao e peitoril diretamente no painel.
- Novo servico de regeneracao completa do comodo, recalculando paredes, piso e rodape a partir dos metadados persistidos do ambiente.

### Ajustado
- Reconstrucao de paredes passou a preservar as aberturas parametricas registradas na parede.
- Smoke test ampliado para validar leitura da selecao, edicao parametrica de parede, porta e janela, e regeneracao completa do comodo.
