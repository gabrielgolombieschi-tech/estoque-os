# Backlog — expedição, volumes e DANFE próprio

## Expedição e transporte real

Quando `modFrete` for diferente de `9`, incluir uma etapa de expedição antes da emissão:

- preencher e validar os campos já existentes `public.itens.peso_liquido` e `public.itens.peso_bruto`;
- permitir que a expedição confirme quantidade, espécie, marca, numeração, peso líquido e peso bruto da embalagem efetivamente despachada;
- registrar transportadora, modalidade do frete e placa quando aplicáveis;
- somente então congelar e enviar o grupo `vol`;
- integrar a definição do bloco Fatura/Duplicata à condição de pagamento da venda.

Até essa etapa existir, o cenário sem transporte usa `modFrete=9` e omite `vol`.

## DANFE próprio

**Marco: 01/10/2026.**

Gerar um DANFE próprio a partir do XML autorizado armazenado no bucket privado `nfe-documentos`, preservando o XML como fonte da verdade. O objetivo é controlar a apresentação quando for necessário:

- exibir IBS/CBS e `cClassTrib`;
- formatar o número com nove dígitos no corpo e no canhoto;
- ajustar a tarja de homologação sem encobrir valores;
- estender a moldura da grade de produtos;
- imprimir volumes e Fatura/Duplicata somente quando presentes no XML;
- validar visualmente o PDF contra o leiaute vigente antes da disponibilização ao cliente.

Não implementar antes do marco sem nova priorização.
