# Operações fiscais que não nascem do botão Faturar

## Situação

O ERP possui um caminho separado em `/faturamento/operacoes` para preparar e controlar, exclusivamente em **homologação**, quatro famílias de operação: devolução de compra, venda à ordem, remessa/retorno e estorno. As regras ficam no banco, sob escopo obrigatório de `tenant_id` e `empresa_id`; a tela não consegue contornar os bloqueios chamando a API diretamente.

Nenhum perfil de operação foi habilitado para produção e nenhuma alíquota, benefício fiscal ou regra específica para o NCM `85444900` foi semeada.

## Caminho de cada operação

### Devolução de compra (emitida pelo ERP desde 17/09/2026)

Aba DEVOLUCAO de `/faturamento/operacoes`. Como a remessa para conserto e o retorno de terceiros,
**emite** a NF-e pelo pipeline fiscal (homologação → liberação do perfil → produção). Passo a
passo, tributação, a nota de referência de homologação e o estoque em
[devolucao-compra.md](devolucao-compra.md).

Resumo: busca a nota de entrada importada com XML, `f.fn_devolucao_compra_preparar` lê o XML,
a tela recebe a quantidade a devolver por item (a soma das devoluções de cada linha nunca passa
do XML), CFOP 5201/6201 (5553/6556), frete e volumes; `f.fn_devolucao_compra_nfe_criar` monta a
operação `DEVOLUCAO_COMPRA` e a solicitação (finNFe 4, espelho proporcional com os impostos do
XML, IPI fora da base do ICMS, tPag 90, `DFeReferenciado` por item). A nota real dá baixa no
estoque; sem saldo, fica a pendência na operação.

### Venda à ordem

1. Informar a OV e o local de entrega alternativo, incluindo documento, nome, endereço, número, bairro, município, UF, CEP e código IBGE.
2. Uma única operação é criada com duas etapas: venda em `6119` e remessa por conta e ordem em `6923`.
3. A etapa 2 permanece bloqueada até a etapa 1 receber uma chave autorizada de 44 dígitos.
4. Ao registrar a primeira chave, o ERP a leva para `nfe_referenciada` e para as informações complementares da segunda etapa.

O endereço alternativo é snapshot da operação; ele não altera o cadastro principal do cliente.

### Remessa para conserto (emitida pelo ERP desde 16/09/2026)

É a aba padrão de `/faturamento/operacoes`. Ao contrário das demais, ela **emite** a NF-e pelo
pipeline fiscal (homologação → liberação do perfil → produção); nada de chave digitada.
Passo a passo, tributação e primeira nota real (NF-e 2/19, cortinas SICK em garantia) em
[remessa-conserto.md](remessa-conserto.md).

Resumo: destinatário do cadastro de clientes, itens do catálogo com o valor de compra,
transporte, `f.fn_remessa_nfe_criar` monta a solicitação com a tributação do perfil
`SEG-REMESSA-CONSERTO-6915-O2-CST50` (ou `-5915-` dentro de SC): ICMS 50 + cBenef SC840007,
IPI 55 cEnq 108, PIS/COFINS 08, IBS/CBS 410/410999 sem grupo de valores, tPag 90. A
autorização em produção abre `f.remessa_controle` sozinha (prazo CONSERTO = 180 dias).

### Outras remessas e retorno (chave digitada)

As finalidades são distintas e aceitam somente estes CFOPs:

| Finalidade | Remessa | Retorno |
| --- | ---: | ---: |
| Industrialização por encomenda | 5901 | 5902 |
| Conserto dentro do estado | 5915 | 5916 |
| Conserto fora do estado | 6915 | 6916 |
| Remessa simples | 5949 / 6949 | sem retorno configurado |
| Por conta e ordem | 6923 | controlada no fluxo de venda à ordem |

Ao registrar a chave da remessa, o ERP abre `f.remessa_controle` por chave, destinatário e data. A listagem mostra dias decorridos e permite criar o retorno correspondente. Registrar a chave do retorno encerra o controle.

O prazo é configurável por empresa e finalidade em `f.remessa_prazo_config`. Ele nasce **vazio**; sem prazo configurado não há alerta nem vencimento presumido.

### Estorno

1. Selecionar um `documento_fiscal` autorizado e informar a justificativa ao fisco.
2. O ERP exige chave original, copia os itens e valores do documento e propõe o CFOP inverso conforme a operação original.
3. O usuário confirma um dos CFOPs observados (`1102`, `1201`, `1202`, `1915`, `2202`). Não existe CFOP fixo.
4. A operação é preparada com finalidade `3`, natureza `999 - ESTORNO DE NF-E NAO CANCELADA NO PRAZO LEGAL`, chave original referenciada e valores idênticos.

O RICMS/SC limita o cancelamento normal a 24 horas e prevê NF-e de estorno quando a operação não ocorreu e o cancelamento não foi transmitido no prazo. A orientação de SC exige finalidade 3, natureza específica, chave referenciada, valores equivalentes, CFOP inverso e justificativa. Fontes: [RICMS/SC, Anexo 11, art. 13](https://legislacao.sef.sc.gov.br/html/regulamentos/icms/ricms_01_11.htm) e [Consulta COPAT 058/22](https://legislacao.sef.sc.gov.br/consulta/views/Publico/DocumentoLegalViewer.ashx?id=63B499B2-93C6-463C-A20F-5A766A2FE80C).

## Estrutura criada

- `f.operacao_fiscal`: cabeçalho, origem, ambiente, estado, confirmações, referências, entrega alternativa e justificativa.
- `f.operacao_fiscal_item`: snapshot dos itens e tributos da fonte.
- `f.remessa_controle`: remessas abertas e seus retornos.
- `f.remessa_prazo_config`: prazo opcional por finalidade.
- `f.v_remessas_abertas`: dias decorridos e alerta condicionado à configuração.
- RPCs `fn_devolucao_compra_*`, `fn_venda_ordem_criar`, `fn_remessa_criar`, `fn_retorno_criar`, `fn_estorno_criar`, `fn_operacao_validar_homologacao` e `fn_operacao_registrar_chave`.
- `fn_operacao_vincular_documento`: ponte idempotente usada pelo emissor para ligar cada etapa ao documento materializado e copiar a referência para `f.documento_fiscal.nfe_referenciada`.

Não foi necessário alterar a OV ou o cliente para guardar o endereço alternativo: a operação mantém seu próprio snapshot em `entrega_json`. A referência à NF-e de origem fica em `f.operacao_fiscal.nfe_referenciada`; ao materializar a emissão, `fn_operacao_vincular_documento` a copia para `f.documento_fiscal.nfe_referenciada`, campo já existente. Na segunda etapa da venda à ordem, a função recusa o vínculo enquanto a primeira chave não existir.

## Portões mantidos

- `ambiente` possui `check` que aceita somente `HOMOLOGACAO` nesta estrutura.
- A devolução não passa sem chave e validação de todos os itens contra o XML.
- A segunda NF-e da venda à ordem não passa sem a chave da primeira.
- O retorno não passa sem a remessa aberta e referenciada.
- O estorno não passa sem documento original, chave, finalidade 3 e justificativa.
- As políticas RLS e as funções validam simultaneamente tenant e empresa.

Registrar uma chave na tela representa o retorno de uma autorização em homologação. A transmissão ao gateway deve chamar primeiro `fn_operacao_validar_homologacao` e, no callback autorizado, `fn_operacao_registrar_chave`; produção permanece bloqueada pelos perfis vigentes.

## Pendente do contador

- Prazo legal por finalidade de remessa. O cadastro permanece nulo até resposta formal.
- Confirmação final das propostas de CFOP para cada documento real, especialmente quando o CFOP de entrada não estiver no mapa observado.
- Textos fiscais definitivos de industrialização, conserto e venda à ordem; os fluxos foram mantidos separados e não receberam texto tributário presumido.
- CST/CSOSN, IPI, PIS, COFINS e benefícios continuam sob os portões fiscais existentes.

## Cenários de homologação executados

- Leitura de XML de entrada e devolução parcial de 1 unidade.
- Rejeição de CST divergente do XML.
- Bloqueio da segunda nota `6923` sem a chave da `6119` e liberação após a chave.
- Abertura de remessa de conserto `5915`, criação do retorno `5916` e encerramento do controle após a chave do retorno.
- Estorno derivado de documento original com CFOP `1202`, finalidade 3 e chave referenciada.
- Vínculo idempotente entre operação e documento, com cópia comprovada para `documento_fiscal.nfe_referenciada`.
- RLS autenticada, reset local completo e rollback dos dados de teste.
