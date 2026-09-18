# Exceção "ICMS 12% por exigência do destinatário"

Pedido de 16/09/2026, para a PORTOBELLO (PBG S/A). Mercadoria de manutenção, uso e
consumo ou ativo imobilizado sai a 17% (Lei 10.297/96, art. 19, § 3º), e a emissão para
em "destinação manutenção exige alíquota interna de 17%, e a nota está com 12%". Quando o
cliente contribuinte exige 12% na OC, a nota sai a 12% (RICMS/SC-01, art. 26, III, "n"),
por determinação dele, que responde solidariamente pela diferença (art. 26, § 6º).

## Quando aparece

Na conferência da NF-e da OV (etapa fiscal) e na tela de faturar a OS, só se:

- o destinatário é contribuinte (indIEDest = 1);
- a operação é interna (SC);
- a destinação é manutenção, uso e consumo ou ativo imobilizado.

Para não contribuinte a opção não aparece.

## Ativar

- Número da OC (obrigatório).
- Evidência: texto do e-mail do cliente ou anexo (até 5 MB, guardado no banco).
- O banco grava quem ativou e quando. Reativar ou desativar preserva o histórico.
- A OC vira o pedido de compra da nota quando ele ainda está vazio.
- Ativar ou desativar derruba o snapshot da nota: na OS, clique em **Reconferir**; na OV,
  a emissão refaz a conferência sozinha. Com a NF-e de produção enviada, não muda mais.

## O que muda na nota

- Itens **sem** cBenef SC820006: CST 00, 12%, sem redução, sem cBenef.
- Itens **com** SC820006: seguem a regra própria (CST 20, pRedBC 29,412).
- indFinal = 1, mesmo que o perfil fiscal diga 0.
- IPI não muda. Na manutenção ele continua dentro da base do ICMS: item FAB (CFOP 5101)
  tem vBC = vProd + vIPI. Vale também na revenda de item importado pela própria empresa
  (origem 1, equiparado a industrial, CFOP 5102): NF-e 2/73 de homologação da OV-SEG-00004-026
  (18/09/2026), vBC 4.563,40 + 444,93 = 5.008,33 a 12%. Sem a exceção o mesmo par é bloqueado
  por `conflitoIpiNaBaseComAliquota`; os dois lados estão em `scripts/test-nfe-pipeline.mjs`.
- vTotTrib segue a regra existente (IBPT, só com indFinal = 1).
- Informações complementares, com N = nItem:
  `Itens N: ICMS à alíquota de 12% (RICMS/SC-01, art. 26, III, "n") aplicada por
  determinação do destinatário, conforme OC nº X, utilização informada: manutenção. O
  destinatário responde solidariamente pela diferença de alíquota, nos termos do art. 26,
  § 6º, do RICMS/SC-01.` A frase "Destinação informada pelo destinatário" não se repete:
  o texto da exceção já traz a utilização (revisão da NF-e 2/55).
- A Focus troca "º" por "o" no XML ("OC no", "§ 6o"); o payload enviado leva "º".

## Trava de 17%

- Com a exceção ativa, a trava vira confirmação na hora de emitir.
- Sem a exceção, continua bloqueando.

## Onde está

| Camada | Arquivo |
| --- | --- |
| Regra e texto | `supabase/functions/_shared/fiscal/icms-sc-destinacao.ts` |
| Montador da nota | `supabase/functions/_shared/nfe-payload.ts` |
| Banco | `supabase/migrations/20260916140000_nfe_excecao_icms_12_destinatario.sql` |
| Tela | `components/faturamento/ExcecaoIcms12Destinatario.tsx` |
| Relatório mensal | `/faturamento/nfe/excecoes` (`f.fn_nfe_excecao_aliquota_relatorio`) |
| Testes | `scripts/test-nfe-pipeline.mjs`, `supabase/tests/nfe_excecao_icms_12_destinatario.sql` |

O relatório lista as notas autorizadas no mês com a exceção: nota, destinatário, OC, vBC,
ICMS destacado e diferença para 17%, somando só os itens da exceção. Tem filtro de
ambiente e exporta CSV.

## Produção

A liberação de perfil continua obrigatória. A prontidão de produção deixa de comparar o
indFinal com o perfil quando a nota tem a exceção, e exige indFinal = 1. Como o texto da
nota muda, a solicitação precisa de uma homologação nova com a exceção ativa antes da
produção.
