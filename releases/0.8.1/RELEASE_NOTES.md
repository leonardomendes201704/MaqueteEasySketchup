# PlanForge Builder Release Notes

## [0.8.1] - 2026-03-25

### Ajustado
- O modal `Gerar comodo` agora solicita largura e profundidade em metros por padrao, com rotulos explicitos em PT-BR.
- O parser do gerador de comodo passou a aceitar entradas como `4`, `4,5`, `4,50 m`, `450 cm` e `4500 mm`, sempre tratando valores sem unidade como metros.
- O ghost e o VCB do `RoomTool` agora exibem as dimensoes em metros no formato PT-BR, sem depender da unidade configurada no SketchUp.
- Smoke test ampliado para validar parsing e formatacao metrica do gerador de comodo.
