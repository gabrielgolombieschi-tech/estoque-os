# Conferência fiscal por destino e perfil

## Resultado

A conferência da NF-e da OV passou a ter duas etapas. A primeira confirma se o destino é Santa Catarina ou outra UF e valida essa escolha contra o cadastro fiscal do cliente. A segunda só é aberta depois que o servidor resolve um perfil fiscal válido para cada linha.

Nenhuma NF-e foi emitida nesta entrega e nenhum perfil foi habilitado para produção.

## Fluxo da tela

1. A pessoa abre **Conferir e emitir**.
2. A tela começa sem decisão fiscal implícita e pergunta se a mercadoria vai para SC ou para outra UF.
3. Fora de SC, a UF é obrigatória.
4. A RPC `f.fn_solicitacao_nfe_resolver_perfis` compara a UF escolhida com a UF do destinatário. Divergência ou cadastro ausente bloqueia e oferece o atalho para `/clientes/cadastro-fiscal`.
5. O servidor classifica a busca por empresa, CRT, natureza, âmbito, UF, `indicador_ie`, origem do produto, vigência e faixa de automação.
6. Cada linha recebe seu próprio perfil. Isso permite uma mesma NF-e com produtos de origens diferentes sem aplicar uma tributação única incorreta.
7. Valores vindos do perfil aparecem preenchidos, com cadeado e o código do perfil visível.
8. Presença do comprador, modalidade do frete, frete, seguro e outras despesas continuam sendo confirmados em cada nota.
9. A RPC de gravação resolve tudo novamente e rejeita adulteração de campo bloqueado no navegador.

## Regra territorial usada somente para procurar perfil

Para destinatário interestadual contribuinte:

| Origem/UF | Faixa procurada |
| --- | ---: |
| origem 1, 2 ou 6 | 4% |
| PR, RS, SP, RJ ou MG, demais origens | 12% |
| demais UFs, demais origens | 7% |

A faixa não é gravada como imposto por cálculo da tela. A alíquota, o CFOP e os CSTs só entram quando existe perfil cadastrado para aquela combinação. Destinatário interestadual não contribuinte é bloqueado com a mensagem de que precisa de perfil próprio de DIFAL.

## Dono de cada campo

### Perfil da operação

- CFOP interno ou externo
- CST ICMS ou CSOSN, conforme CRT
- modalidade e alíquota de ICMS
- redução da base
- existência/ausência confirmada de `cBenef`
- CST e alíquotas de PIS/COFINS
- finalidade e consumidor final, quando confirmados no perfil
- IBS/CBS apenas quando o próprio perfil tiver valores confirmados

### Cadastro fiscal do produto (`public.fiscal_itens`)

- origem
- NCM e CEST
- unidade tributável
- CST IPI
- `ipi_codigo_enquadramento_legal` (`cEnq`)
- alíquota de IPI
- número da FCI, quando aplicável

IPI deixou de ser herdado de `f.perfil_operacao`. A tela de itens agora permite cadastrar CST IPI, cEnq e FCI. Na conferência eles aparecem somente para leitura; ausência bloqueia e direciona a correção ao item.

### Confirmado em cada nota

- presença do comprador
- modalidade do frete
- valor do frete
- valor do seguro
- outras despesas

Zero continua válido, mas precisa ser valor explícito. Vazio significa não confirmado.

## IBS/CBS

`cst_ibs_cbs`, `cclass_trib`, `cclass_trib_versao`, alíquota IBS UF, alíquota IBS municipal e alíquota CBS não recebem default. Enquanto o perfil não tiver valores confirmados, ficam editáveis, vazios e obrigatórios. A referência da homologação anterior é mostrada apenas como sugestão visual e não é aplicada.

## Persistência e auditoria

Foram adicionados:

- `f.solicitacao_faturamento.destino_uf_confirmada`, data e usuário da confirmação;
- data e usuário da aplicação de perfil no cabeçalho;
- `f.solicitacao_item.perfil_operacao_id`, data e usuário por linha;
- escopo territorial, `indicador_ie`, modalidade, finalidade, consumidor e IBS/CBS estruturado em `f.perfil_operacao`;
- CST IPI, cEnq e FCI em `public.fiscal_itens`;
- FCI no snapshot da linha da solicitação.

O perfil no cabeçalho só é preenchido quando todas as linhas usam o mesmo perfil. O vínculo por linha é a fonte da auditoria em notas mistas.

## Cenários automatizados

O teste `supabase/tests/faturamento_conferencia_destino_perfil.sql` cobre:

1. interna SC contribuinte com o perfil esperado;
2. interna SC não contribuinte;
3. interestadual contribuinte na faixa de 12%;
4. interestadual contribuinte na faixa de 7%;
5. origem 1 na faixa de 4%;
6. origem 2 na faixa de 4%;
7. origem 6 na faixa de 4%;
8. interestadual não contribuinte bloqueado por DIFAL;
9. UF escolhida divergente do cliente;
10. produto sem origem;
11. combinação sem perfil;
12. nota com origens mistas e perfis por linha;
13. tentativa de alterar ICMS bloqueado pelo perfil;
14. IBS/CBS vazio sem default e emissão bloqueada.
15. chamada direta à RPC com linha sem perfil resolvido bloqueada no servidor.

Também é verificado que destino, perfil por linha e zero explícito ficam gravados com carimbo de auditoria.

## Validações executadas

- `npx supabase db reset --local`
- `supabase/tests/faturamento_conferencia_destino_perfil.sql`
- `supabase/tests/faturamento_nfe_pipeline.sql`
- `npm run test:nfe-pipeline` (22 cenários)
- `npx tsc --noEmit`
- ESLint nos arquivos alterados
- `npm run build`
- smoke HTTP de `/itens` e `/comercial/vendas/1`
- `npx supabase db lint --local --level error` e `--linked`: somente os 10 erros históricos do baseline; nenhum objeto desta entrega foi apontado

## Aplicação remota

- migration `20260903110000_nfe_conferencia_destino_perfil.sql` aplicada em 03/09/2026;
- `db push --linked --dry-run` confirmou o banco remoto atualizado;
- Edge Functions `nfe-emitir` e `nfe-emitir-producao` republicadas, respectivamente nas versões 19 e 6;
- smoke remoto somente leitura confirmou as colunas, as três RPCs e o perfil SEG ajustado;
- nenhum perfil da empresa foi habilitado para produção e nenhuma NF-e foi emitida.
