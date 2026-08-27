-- Quem pode cadastrar um item precisa consultar os fornecedores já cadastrados
-- para vinculá-los no agente de cadastro. A política restritiva de escopo ativo
-- continua garantindo tenant e empresa da sessão.

set local role postgres;

drop policy if exists fornecedores_select on public.fornecedores;

create policy fornecedores_select
  on public.fornecedores
  for select
  to authenticated
  using (
    public.can__legacy_40734('estoque', 'read')
    or public.can__legacy_40734('cad_fornecedores', 'write')
    or public.can('cad_itens', 'write')
  );
