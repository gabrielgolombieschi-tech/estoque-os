# Ajuste de meio centavo (por item da nota)

Pedido do Gabriel em 18/09/2026, a partir da OV-SEG-00004-026: a OC 1309011 da Portobello é
valor fechado, R$ 4.563,40 **já com o IPI**. Mercadoria 4.158,00 × 9,75% = **405,405**. A regra
geral do montador arredonda meio para cima (405,41) e a nota fecharia em 4.563,41, um centavo
acima da OC, que o cliente recusa.

## O que é

- A regra geral de arredondamento **não muda** (`round()` em `nfe-payload.ts`: meio para cima,
  duas casas).
- Cada linha da solicitação ganha uma marca **"arredondar empate para baixo"**, com tributo,
  motivo obrigatório, quem confirmou e quando (`f.solicitacao_item.arredondar_empate_*`,
  migration `20260918270000`).
- A marca **só liga quando o valor exato do tributo cai em empate de meio centavo**: terceira
  casa 5 e nada depois (405,405; 0,005), com tolerância de ponto flutuante na terceira casa.
  Fora disso o banco recusa (`f.fn_nfe_empate_meio_centavo`).
- Efeito: aquele tributo, naquele item, arredonda para baixo. Diferença máxima R$ 0,01 por
  linha. Vale para o **IPI**; a coluna aceita ICMS, mas a RPC e o montador recusam ICMS por
  enquanto.
- Se a linha mudar depois da confirmação e sair do empate, o montador para a emissão com a
  mensagem "o ajuste de meio centavo está marcado mas o IPI não cai em empate" e a tela mostra
  o bloco vermelho com **Desfazer o ajuste**.

## Onde aparece

Conferência da OV (painel de rascunhos) e Faturar OS (prévia, depois de conferir). Só quando há
empate na linha, ou quando o ajuste já está ligado. Texto:

> O IPI deu exatamente meio centavo (405,405). Padrão: 405,41, total 4.563,41. Arredondar para
> baixo (405,40, total 4.563,40) para fechar com o pedido do cliente?

Campo **Motivo do ajuste** (10 a 300 caracteres) e botão **Arredondar para baixo**. Ligado, o
bloco vira verde com o valor, o total, o motivo e a data, e o botão **Desfazer o ajuste**.

Na OV o rascunho ainda não tem CST/alíquota de IPI gravados na linha (a conferência só grava ao
emitir), então a tela manda os dois junto com a confirmação e a RPC os grava na linha
(`20260919020000`). Na OS a linha já vem conferida.

## RPC

`f.fn_solicitacao_item_arredondar_empate(p_solicitacao_item_id, p_tributo, p_ativar, p_motivo,
p_cst_ipi, p_aliquota_ipi)` — `authenticated` com acesso financeiro à empresa; solicitação em
RASCUNHO/PREVIA/APROVADA; homologação autorizada não trava (obriga a homologar de novo);
produção enviada trava. Desativar limpa tudo. Retorna valor exato, padrão e para baixo.

## Testes

- `scripts/test-nfe-pipeline.mjs`: 4.158,00 × 9,75% sem a marca → 405,41 / 4.563,41; com a marca
  → 405,40 / 4.563,40 (PIS 60,37, COFINS 278,09); marca fora do empate → erro; ICMS → erro;
  marca desligada → payload idêntico ao de sempre.
- `supabase/tests/nfe_arredondar_empate.sql`: função de empate; recusas (sem motivo, motivo
  curto, ICMS, item sem IPI); ativação em empate com quem/quando; reativar e desativar; valores
  da conferência ainda não gravados; fora do empate recusado; linhas existentes seguem false e a
  check constraint recusa marca sem motivo.

## Caso OV-SEG-00004-026

Rascunho com 1 UN × 4.158,00 (motivo da diferença para o orçado: "Orçado inclui IPI"), destino
SC, destinação INSUMO (Utilização "Aquisição de Mercadoria Insumos" na OC), sem exceção de 12%,
ajuste do meio centavo com o motivo "fechar com OC 1309011, total 4.563,40". Esperado na NF-e:
vProd 4.158,00, IPI 50 9,75% **405,40**, vBC ICMS 4.158,00 (IPI fora da base), ICMS 12% 498,96,
PIS 60,37, COFINS 278,09 (base 3.659,04), base IBS/CBS 3.320,58, indFinal 0, **vNF 4.563,40**.
