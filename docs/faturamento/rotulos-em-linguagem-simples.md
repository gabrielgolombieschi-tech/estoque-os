# Códigos fiscais em linguagem simples (padrão do ERP desde 18/09/2026)

Decisão do Gabriel: **código fiscal nunca aparece sozinho**. Toda opção mostra um texto simples, um
exemplo curto e o código pequeno ao lado; onde dá, a pessoa escolhe a situação e o sistema deriva o
código. Só tela: nada disso muda regra fiscal, cálculo, payload ou perfis.

## Onde os textos vivem

- `lib/fiscal/rotulos.ts` — único lugar dos rótulos, exemplos e códigos: CFOPs das remessas por
  finalidade e do estorno, destinação do cliente (com o efeito 12%/17% e IPI na base, copiado da regra
  de `fiscal/icms-sc-destinacao.ts` do montador), origem da mercadoria, modalidade do frete, formas de
  pagamento da NF-e/NFS-e (tPag) e do contas a pagar. `textoOpcao()` monta "Texto simples (código)"
  para `<option>`, onde não dá para estilizar o código.
- `f.perfil_operacao.rotulo_usuario` / `legenda_usuario` — quando existe perfil para a opção, o texto
  dele prevalece (`rotuloDoPerfil()`); hoje preenchidos nos perfis 5902 e 5903 do retorno de terceiros.

## Telas

| Tela | Antes | Agora |
| --- | --- | --- |
| Operações fiscais › Remessa com controle de retorno | finalidade em código (INDUSTRIALIZACAO…) e CFOP digitado livre | finalidade em texto ("Conserto ou reparo"…) e select do CFOP que o banco aceita para ela (`f.fn_remessa_criar`: 5901; 5915/6915; 5949/6949; 6923), com exemplo e código entre parênteses |
| Operações fiscais › Estorno | CFOP digitado livre ("1102, 1201, 1202, 1915 ou 2202") | select "O que está sendo estornado?" com os cinco CFOPs que `f.fn_estorno_criar` aceita, exemplo da nota original |
| Operações fiscais › Venda à ordem | só o título "6119 seguida de 6923" | frase explicando as duas notas; não há CFOP a escolher (fixo na função) |
| Faturar OS › destinação | "Vai revender · 12%" | "O que o cliente vai fazer com a mercadoria?" com "Vai revender", "Vai usar como peça/insumo na produção dele", "Recebe em consignação", "Vai usar na manutenção", "Uso e consumo", "Vai virar equipamento/patrimônio dele (ativo)"; abaixo, o exemplo e o efeito em uma linha ("ICMS 12%, IPI fora da base" ou "ICMS 17%, IPI dentro da base"), com aviso quando o cliente não é contribuinte (sempre 17%) |
| Faturar OS › origem do produto novo | "1 · Estrangeira, importação direta" | "Importado por nós (direto ou por conta e ordem) (1)", "Importado, comprado de distribuidor no Brasil (2)", "Fabricação nossa com componentes importados (CI …)" (5/3/8) e os casos raros 4/6/7 no fim; exemplo abaixo |
| Faturar OS, Faturar NFS-e, Devolução, Remessa para conserto, Retorno de terceiros › frete e pagamento | "0 · Por conta do remetente", "15 · Boleto bancário" | "Segau paga o frete (CIF) (0)", "Boleto bancário (15)"; a tela da OS mostra `modFrete`/`tPag` pequenos abaixo |
| Importação › forma de pagamento da nota de débito | BOLETO, PIX… | "Boleto (BOLETO)", "PIX (PIX)"… da mesma lista central |

Não mudaram (decisão do Gabriel): tela de perfis fiscais e listas de NF-e (informativas, de quem
entende). CST IPI na tela de faturar OS: ver a resposta no relato de 18/09 (o campo só aparece ao
criar um produto fabricado novo; para produto cadastrado o CST vem do cadastro fiscal).
