# Lista de e-mails do cliente na entrega da NF-e

Pedido do Gabriel em 18/09/2026, na entrega da NF-e 2/33 da OV-SEG-00004-026: no campo
**Entregar ao cliente**, apertar **Enter** com o campo selecionado abre a lista de e-mails
daquele cliente para escolher; e todo e-mail novo digitado ali e enviado pelo botão entra na
lista para a próxima nota.

## Como funciona

- **Enter** (ou o botão **Lista ▾**) abre. Setas ↑↓ andam, **Enter** escolhe, **Esc** fecha,
  clique fora fecha. Escolher acrescenta o e-mail ao campo e deixa uma vírgula pronta para o
  próximo; escolher de novo o mesmo não duplica.
- Digitar filtra a lista pelo que está sendo escrito depois da última vírgula (serve para o
  e-mail, o nome e o setor).
- A lista junta o **cadastro do cliente** (financeiro e principal) com os **contatos já usados**
  (`public.cliente_contatos`, os mesmos do orçamento), com nome, setor, quantas vezes foi usado
  e a data do último uso. Ordem: principal, mais recente, mais usado, alfabética.
- E-mail do domínio da própria empresa emitente aparece em vermelho, **não é escolhível**, e o
  aviso para corrigir o cadastro continua abaixo do campo.
- Depois de um envio bem-sucedido, os endereços são registrados no cliente: quem já existia
  soma um uso, quem não existia é cadastrado com o setor `NF-E` e o nome pela parte antes do @
  (dá para renomear no cadastro do cliente). Nome e setor de um contato que veio do orçamento
  nunca são sobrescritos.

## Onde está

| Camada | Arquivo |
| --- | --- |
| Banco | `supabase/migrations/20260919040000_cliente_emails_nfe.sql` |
| Campo | `components/faturamento/EmailsEntregaNfe.tsx` |
| Telas | conferência da OV (`OvNfeDraftsPanel`), Faturar OS (`app/os/[id]/faturar`), ciclo da NF-e (`NfeLifecyclePanel`) |
| Testes | `supabase/tests/cliente_emails_nfe.sql` |

RPCs (ambas `SECURITY DEFINER`, exigem sessão, empresa ativa e acesso financeiro **ou**
comercial — quem fatura nem sempre tem acesso comercial, e a RLS da tabela exige):

- `public.clientes_emails_nfe(cliente)` — lista do campo.
- `public.clientes_registrar_emails_nfe(cliente, emails)` — marca o uso e cadastra o que faltava;
  devolve a lista atualizada. E-mail inválido, vazio ou repetido (mesmo com maiúsculas) é
  ignorado. Índice único novo: `cliente_contatos_email_unico`.

O registro roda depois do envio e nunca derruba a entrega: se falhar, o erro fica só no console
do navegador, porque a nota já foi enviada.
