# PlanForge Builder Release Notes

## [0.9.0] - 2026-03-25

### Implementado
- Novo modulo `RoomReconciler` para reconciliar paredes compartilhadas entre comodos do plugin.
- Introducao de paredes proxy compartilhadas para reaproveitar a parede fisica existente sem duplicar a geometria.

### Ajustado
- Geracao e regeneracao de comodos agora recalculam paredes compartilhadas antes da criacao do rodape.
- Quando um comodo novo encosta com uma parede inteira em um comodo existente, o plugin reaproveita essa parede e corta automaticamente os encontros perpendiculares para evitar sobreposicao.
- Rodapes de paredes proxy passam a consultar as aberturas da parede fisica compartilhada.
