# PlanForge Builder Release Notes

## [0.5.0] - 2026-03-25

### Implementado
- Rodape interno configuravel com geracao automatica ao fechar o comodo.
- Novo comando `Gerar rodape` para regenerar o rodape a partir de uma parede, piso ou rodape de um comodo criado pelo plugin.
- Novas configuracoes persistentes para altura e profundidade do rodape.
- Metadados de comodo gravados nas paredes e no piso para permitir regeneracao posterior.

### Ajustado
- O rodape agora interrompe automaticamente nos trechos com aberturas que descem ate a base, como portas.
- Smoke test ampliado para validar criacao, volume esperado e regeneracao do rodape.
