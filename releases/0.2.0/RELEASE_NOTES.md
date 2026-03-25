# PlanForge Builder Release Notes

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
