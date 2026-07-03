# Ada — Avaliação dos Scripts de Importação (SP)

## Contexto

Checkpoints confirmados: 01-setup ✅, 02a-market ✅, 02b-macro-br ✅, 02c-macro-us ✅, 03-build-dataset ✅  
Checkpoint ausente: 02d-b3 ❌ (script 05 não foi executado)

---

## O que está funcionando bem

| Script | Dados | Obs | Período | Status |
|--------|-------|-----|---------|--------|
| 02a — PTAX | `usd_brl_ptax` (bid/ask) | 4.142 | 2010–2026-07-01 | ✅ perfeito |
| 02a — Yahoo | 11 tickers (DXY, VIX, S&P, Nasdaq, IBOV, EWZ, WTI, Brent, ouro, cobre, USDBRL=X) | 46.779 | 2010–2026 | ✅ |
| 02b — BCB SGS diários | selic_meta, selic_diaria, cdi_diario | 5.844 / 4.019 / 4.019 | 2010–2026 | ✅ |
| 02b — BCB SGS mensais | ipca_mensal, ipca_acum12m, fluxo_cambial | ~192 cada | 2010–2026 | ✅ |
| 02b — BCB Focus | Câmbio, Selic, IPCA, PIB | 118.177 | 2010–2026 | ✅ coletado |
| 02b — IBGE SIDRA | 5 variantes do IPCA | 2.790 | 1979–2026-05 | ✅ coletado |
| 02c — FRED diários | treasury_2y, treasury_10y, vix_fred, dxy_fred | ~4.303 cada | 2010–2026 | ✅ |
| 02c — FRED mensais | fed_funds, desemprego_us, pce_us, cpi_us, core_cpi_us | ~197 cada | 2010–2026 | ✅ |
| 06 — Targets | `target_5d`, `target_30d`, `target_90d` via `log(lead/ptax)` | — | — | ✅ correto |

---

## Bugs críticos a corrigir

### Bug 1 — `06-build-dataset.R`: Focus e IBGE coletados mas NÃO integrados ao dataset

**Problema:** `load_raw_data()` carrega `raw$focus`, mas `build_daily_dataset()` não o usa. IBGE nem é carregado (`raw$ibge` não existe). Os dois datasets estão em disco mas não entram no modelo.

**Impacto:** features importantíssimas faltando — expectativas Focus de câmbio/Selic/IPCA são citadas no briefing como "Essencial" para 30d e 90d.

**Correção em `06-build-dataset.R`:**

a) Em `load_raw_data()` — adicionar carregamento IBGE:
```r
ibge_path <- here("data", "raw", "ibge", "ipca_sidra.csv")
if (file.exists(ibge_path)) {
  raw$ibge <- read_csv(ibge_path, show_col_types = FALSE) |>
    filter(date >= as.Date("2010-01-01")) |>
    pivot_wider(names_from = variavel, values_from = valor) |>
    janitor::clean_names()
}
```

b) Em `build_daily_dataset()` — adicionar joins de Focus e IBGE com forward-fill:
```r
# Focus (semanal → forward-fill até próxima divulgação)
if (!is.null(raw$focus)) {
  focus_wide <- raw$focus |>
    select(date, indicador, Mediana) |>
    pivot_wider(names_from = indicador, values_from = Mediana,
                names_prefix = "focus_") |>
    janitor::clean_names() |>
    arrange(date)
  ds <- ds |>
    left_join(focus_wide, by = "date") |>
    arrange(date) |>
    fill(starts_with("focus_"), .direction = "down")
}

# IBGE (mensal → forward-fill)
if (!is.null(raw$ibge)) {
  ds <- ds |>
    left_join(raw$ibge, by = "date") |>
    arrange(date) |>
    fill(starts_with("ipca_"), .direction = "down")
}
```

---

### Bug 2 — `03-collect-macro-br.R`: `reservas_intl` e `saldo_cambial` com apenas 16 obs (anuais)

**Problema:** `reservas_intl` (série 3545) e `saldo_cambial` (série 23636) retornaram apenas 16 observações — uma por ano (2010-01-01 a 2025-01-01). Estas séries deveriam ser mensais.

**Causa provável:** O `rbcb::get_series()` com janelas de 2 anos pode estar retornando apenas a última observação de cada janela para essas séries específicas, ou a série 3545 no SGS tem periodicidade anual. Série correta para reservas mensais no BCB é a **série 13621** (Reservas internacionais — conceito liquidez, em US$ bilhões), que é mensal.

**Correção em `03-collect-macro-br.R`:**
```r
BCB_SERIES <- tribble(
  ~codigo, ~nome,
  # ...
  13621,   "reservas_intl",    # Reservas internacionais conceito liquidez (mensal) ← trocar 3545
  23636,   "saldo_cambial",    # Manter — investigar se o problema é da janela
)
```
Após reexecução, verificar se `reservas_intl` passa a ter ~192 obs mensais. Se `saldo_cambial` persistir com poucas obs, pode ser que a série tenha periodicidade maior — documentar e remover do dataset se não for útil.

---

## Lacunas conhecidas vs. datasources.md (não são bugs, são gaps de escopo)

| Variável | Prioridade no doc | Status | Ação MVP |
|----------|------------------|--------|----------|
| Minério de ferro | Alta | ❌ sem fonte gratuita diária | usar cobre (HG=F, já coletado) como proxy |
| ANBIMA curva de juros | Alta | ❌ não coletado | **pendente pós-MVP** — requer token ANBIMA |
| CDS Brasil / EMBI+ | Alta | ❌ não coletado | EWZ (já coletado) como proxy para MVP |
| B3 dólar/DI futuro | Alta | ❌ `05-collect-b3.R` não rodou | ver abaixo |
| Comex Stat / fiscal | Alta para 90d | ❌ não coletado | pendente pós-MVP |

**Sobre `05-collect-b3.R`:** O script tenta `DOL=F` (dólar futuro B3) e `^BVSP`. O Ibovespa (`^BVSP`) **já está coletado** no Yahoo (02a). O `DOL=F` provavelmente não retorna dados no Yahoo. **Recomendação:** não executar o script 05 no MVP — adicionar nota no script indicando que BVSP é redundante e que DOL=F requer B3 for Developers.

---

## Outras observações (sem bloqueio)

1. **SOFR começa em 2018-04-03** — gap 2010–2018 é esperado (a série só existe a partir daí). O forward-fill não deve ser aplicado retroativamente — deixar como NA e documentar no data quality log.

2. **Dois índices de dólar:** `dxy` (Yahoo, DX-Y.NYB) e `dxy_fred` (FRED, DTWEXBGS) são índices diferentes (DXY vs. broad dollar index). Ambos são válidos e complementares. Manter os dois com nomes distintos — já estão assim.

3. **IBGE vai de 1979** — o filtro `filter(date >= "2010-01-01")` proposto na correção do Bug 1 resolve isso.

4. **Focus tem colunas ricas:** `Media`, `Mediana`, `DesvioPadrao`, `Minimo`, `Maximo`, `numeroRespondentes`. Para feature engineering futura, considerar dispersão e revisão semanal além da mediana.

---

## Plano de ação

### Fase imediata (corrigir antes de avançar para EDA)

**Tarefa 1 — Corrigir `06-build-dataset.R`**
- Adicionar `raw$ibge` em `load_raw_data()`
- Adicionar join Focus (forward-fill, wide por indicador) em `build_daily_dataset()`
- Adicionar join IBGE (forward-fill) em `build_daily_dataset()`
- Re-executar script no RStudio → novo `daily_dataset.rds` e `model_dataset.rds`

**Tarefa 2 — Corrigir `03-collect-macro-br.R`**
- Trocar código 3545 por 13621 para `reservas_intl`
- Re-executar `collect_bcb_sgs()` e verificar se retorna ~192 obs mensais
- Atualizar checkpoint `02b-macro-br.complete`
- Depois re-executar Tarefa 1

**Tarefa 3 — Documentar gaps no data quality log**
- SOFR: NA antes de 2018 é esperado
- Minério de ferro: ausente, cobre como proxy
- CDS/EMBI: ausente, EWZ como proxy
- B3 futuros: ausente no MVP
- reservas/saldo_cambial: verificar resultado pós-correção

### Fase posterior (pós-MVP / feature engineering)
- ANBIMA curva de juros (requer token)
- Comex Stat (balança comercial para horizonte 90d)
- Tesouro Nacional (resultado fiscal para horizonte 90d)
