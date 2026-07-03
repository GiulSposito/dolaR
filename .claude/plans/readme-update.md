# Plano: Atualizar README.md

## Decisão de abordagem

**NÃO renderizar o Quarto como markdown.** O relatório técnico usa plotly interativo, DT tables e
chunks R dinâmicos — renderizado para `.md` produziria HTML/JS inline que o GitHub não renderiza.

**Abordagem correta:** reescrever o `README.md` como um documento GitHub Flavored Markdown (GFM)
rico, baseado no conteúdo do relatório técnico, com:
- Figuras estáticas `.png` que existem em `outputs/figures/` (versionadas, não no .gitignore)
- Path relativo `outputs/figures/nome.png` — funciona perfeitamente no GitHub
- Link para o relatório técnico HTML (para leitura completa)

---

## Figuras disponíveis e onde usar

| Figura | Uso no README |
|--------|---------------|
| `outputs/figures/eda-01-usd-brl-ptax.png` | Seção "O Problema" — série histórica |
| `outputs/figures/eda-02-retornos-diarios.png` | Seção "O Problema" — retornos |
| `outputs/figures/baseline-comparison-full.png` | Seção "Resultados" — comparação modelos |
| `outputs/figures/eval-strategy-returns.png` | Seção "Resultados" — retorno estratégia |
| `outputs/figures/eval-pred-vs-actual.png` | Seção "Resultados" — previsto vs real |
| `outputs/figures/vip-target_30d.png` | Seção "Feature Importance" |

Não usar todas — focar nas 4-5 mais impactantes para não poluir o README.

---

## Estrutura do novo README.md

### 1. Header (mantém o atual, atualizado)
- Título + badge de status
- Aviso de projeto educacional

### 2. Resultados — PRIMEIRO (new!)
"Executive summary first" — mostrar os resultados logo no topo:
- Tabela de performance: D+5/D+30/D+90 × champion × Test RMSE × Dir% × Strategy return
- 1 figura: `eval-strategy-returns.png`
- Nota sobre os retornos serem teóricos (sem custos de transação)

### 3. O Problema
- Por que prever câmbio é difícil (EMH, Meese-Rogoff)
- Retornos logarítmicos vs preço bruto
- 1 figura: `eda-01-usd-brl-ptax.png`
- Tabela dos 3 horizontes

### 4. Pipeline e Fases (checklist atualizado)
- Todas as fases marcadas como [x] (pipeline completo)
- Scripts reais (01-13) com descrição
- Diagrama ASCII da arquitetura

### 5. Dataset
- 9 fontes, 60 vars brutas + 52 engenheiradas = 111 vars
- Tabela de fontes (simplificada)
- Breve sobre leakage temporal

### 6. Feature Engineering
- 5 grupos (G1-G5) com resumo
- NÃO duplicar o relatório técnico — apenas tabela resumo

### 7. Modelagem e Resultados
- Tabela completa: todos os modelos × horizontes × RMSE (CV + test)
- 1 figura: `baseline-comparison-full.png`
- Champions por horizonte

### 8. Avaliação Final
- 1 figura: `eval-pred-vs-actual.png`
- Tabela de métricas do test set

### 9. Estrutura do projeto (atualizada)
- Árvore de diretórios real (scripts 01-13, não 01-10 como está)

### 10. Setup
- Mantém o atual (clonar, renv, API key FRED)

### 11. Agentes Helix DS
- Mantém a tabela Ada/Grace/Alan/Marie

### 12. Relatório Técnico
- Link para `reports/technical-report.html` (nota: não renderizado no GitHub, baixar para ver)
- Ou mencionar como abrir

---

## Regras para imagens no GitHub

Para que as imagens renderizem no README no GitHub:
- Path relativo: `outputs/figures/nome.png` ✅
- Ou URL absoluta do raw GitHub: `https://raw.githubusercontent.com/GiulSposito/dolaR/main/outputs/figures/nome.png`
- Usar o path relativo (mais simples, funciona após o commit)

Sintaxe markdown: `![Caption](outputs/figures/nome.png)`
Com largura: `<img src="outputs/figures/nome.png" width="800">`

---

## O que NÃO fazer

- Não copiar texto do relatório técnico integralmente — README é um resumo
- Não incluir fórmulas LaTeX complexas (GitHub não renderiza todas)
- Não incluir mais de 5-6 figuras (README ficaria enorme)
- Não duplicar o setup (que já existe e está correto)

---

## Estimativa

1 arquivo README.md com ~200-280 linhas. Reescrita completa preservando o setup e acrescentando
resultados/figuras/pipeline atualizado.
