---
name: ada-data-quality-log
description: Log de problemas de qualidade de dados encontrados e resolvidos
metadata:
  type: project
---

# Log de Qualidade de Dados — dolaR

## Status: Aguardando coleta de dados (Fase 2)

Este log será preenchido após `scripts/02-collect-market.R` e subsequentes.

## Métricas a registrar por fonte

| Fonte | Período | N linhas | % missing | Gaps | Outliers | Status |
|-------|---------|----------|-----------|------|----------|--------|
| BCB PTAX | — | — | — | — | — | pendente |
| Yahoo Finance | — | — | — | — | — | pendente |
| BCB SGS | — | — | — | — | — | pendente |
| BCB Focus | — | — | — | — | — | pendente |
| FRED | — | — | — | — | — | pendente |

## Métricas atualizadas pós-coleta (2026-07-02)

| Fonte | Período | N linhas | Obs | Status |
|-------|---------|----------|-----|--------|
| BCB PTAX | 2010–2026-07-01 | 4.142 | bid + ask | ✅ |
| Yahoo Finance | 2010–2026 | 46.779 | 11 tickers | ✅ |
| BCB SGS diário | 2010–2026 | ~4.000/série | selic, cdi | ✅ |
| BCB SGS mensal | 2010–2026 | ~192/série | ipca, fluxo | ✅ |
| BCB Focus | 2010–2026 | 118.177 | 4 indicadores | ✅ (não integrado ao dataset até correção Bug 1) |
| FRED diário | 2010–2026 | ~4.303/série | treasury, vix, dxy | ✅ |
| FRED mensal | 2010–2026 | ~197/série | cpi, pce, unrate | ✅ |
| IBGE SIDRA | 1979–2026-05 | 2.790 | 5 variantes IPCA | ✅ (não integrado até correção Bug 1) |

## Gaps documentados — esperados e aceitos para MVP

### SOFR — NA antes de 2018-04-03
- **Motivo:** a série SOFR só existe a partir de abril de 2018.
- **Decisão:** manter NA para 2010–2018. Não aplicar forward-fill retroativo.
- **Impacto:** feature `sofr` tem ~8 anos de NA no início do dataset.

### Minério de ferro — ausente
- **Motivo:** sem fonte gratuita com série diária confiável para MVP.
- **Proxy adotado:** `cobre` (ticker HG=F, já coletado via Yahoo) — correlacionado com ciclo global de commodities e demanda chinesa.
- **Ação futura:** World Bank Pink Sheet (mensal) pós-MVP.

### CDS Brasil / EMBI+ — ausente
- **Motivo:** fontes pagas (JP Morgan, Bloomberg, Refinitiv).
- **Proxy adotado:** `ewz` (ETF Brasil em dólar, já coletado via Yahoo) — captura risco-país em frequência diária.
- **Ação futura:** verificar séries proxy no FRED ou Ipeadata.

### B3 dólar futuro e DI futuro — ausentes no MVP
- **Motivo:** `DOL=F` não tem dados no Yahoo Finance; acesso à B3 requer cadastro em B3 for Developers.
- **Script 05-collect-b3.R:** placeholder documentado. `^BVSP` já coletado em 02a.
- **Ação futura:** B3 for Developers ou cotahist para dados históricos.

### reservas_intl — corrigido
- **Problema encontrado:** série BCB SGS 3545 retornou apenas 16 obs anuais (2010–2025).
- **Correção:** trocado para série 13621 (Reservas internacionais — liquidez).
- **Resultado:** 3.519 obs **diárias** (2010-01-04 a 2025-12-31). ✅

### saldo_cambial — periodicidade suspeita
- **Série BCB SGS 23636:** apenas 16 obs anuais coletadas. Série pode ter periodicidade irregular.
- **Ação:** verificar após recoleta com janelas menores; se persistir, remover do dataset.

## Checklist de qualidade (a executar na Fase 2 — EDA)

- [ ] Verificar gaps temporais (dias úteis sem cotação PTAX)
- [ ] Verificar missings nas séries Yahoo Finance (fins de semana e feriados EUA vs BR)
- [ ] Verificar consistência entre PTAX e Yahoo `USDBRL=X`
- [ ] Verificar alinhamento de fusos horários (BCB = Brasília, Yahoo = mercado NY)
- [ ] Verificar resultado da recoleta de `reservas_intl` (série 13621)
- [ ] Verificar forward-fill de Focus no dataset (colunas `focus_*`)
- [ ] Verificar forward-fill de IBGE no dataset (colunas `ipca_*`)
- [ ] Confirmar que `sofr` tem NA apenas antes de 2018 (não há falha de coleta)
