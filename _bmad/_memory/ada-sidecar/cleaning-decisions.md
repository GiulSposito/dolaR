---
name: ada-cleaning-decisions
description: Decisões de limpeza e wrangling tomadas ao longo do projeto
metadata:
  type: project
---

# Log de Decisões de Limpeza — dolaR

## Status: Fase de coleta ainda não iniciada

As decisões serão registradas aqui à medida que os dados forem inspecionados na Fase 2.

## Template para registros futuros

```
### [DATA] — Decisão sobre {variavel}
- **Problema encontrado:** {descrever}
- **Opções consideradas:** {listar}
- **Decisão tomada:** {descrever}
- **Justificativa:** {explicar}
- **Impacto:** {linhas afetadas, colunas modificadas}
```

## Regras gerais já definidas

1. **Datas:** todos os datasets alinhados ao grid de dias úteis da PTAX.
2. **Missings em séries mensais:** `fill(.direction = "down")` — representa disponibilidade real no mercado.
3. **Fins de semana/feriados:** não interpolados — PTAX não disponível = linha não criada.
4. **Outliers extremos:** não remover automaticamente; documentar e criar flag `is_outlier_{variavel}`.
5. **Leakage temporal:** proibido. Nunca usar dado futuro como feature no dia t.
