-- Busca por palavras antes do limite da tela. O retorno da tabela preserva os
-- relacionamentos usados pelo PostgREST e as politicas de acesso existentes.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

create or replace function public.movimentacoes_buscar(
  p_tenant_id uuid,
  p_empresa_id uuid,
  p_busca text,
  p_limite integer default 1000
)
returns setof public.movimentacoes
language sql
stable
security invoker
set search_path = pg_catalog, public
as $$
  select m.*
  from public.movimentacoes m
  left join public.itens i
    on i.id = m.item_id
   and i.tenant_id = m.tenant_id
   and i.empresa_id = m.empresa_id
  left join public.nf_entrada nf
    on nf.id = m.origem_nf_entrada_id
   and nf.tenant_id = m.tenant_id
   and nf.empresa_id = m.empresa_id
  left join public.fornecedores f
    on f.id = nf.fornecedor_id
   and f.tenant_id = m.tenant_id
   and f.empresa_id = m.empresa_id
  left join public.ordens_servico os
    on os.id = m.origem_os_id
   and os.tenant_id = m.tenant_id
   and os.empresa_id = m.empresa_id
  cross join lateral (
    select coalesce(
      nullif(btrim(os.numero_os), ''),
      case when os.os_num > 0 then os.os_num::text end,
      case when m.origem_os_id > 0 then m.origem_os_id::text end
    ) as numero
  ) numero_os
  cross join lateral (
    -- Espelha motivoExibicao da tela: o numero comercial substitui o ID interno.
    select case
      when numero_os.numero is null then btrim(m.motivo)
      when btrim(m.motivo) ~* '\s*\[OS\s+[^\]]+\]\s*$' then
        regexp_replace(btrim(m.motivo), '\s*\[OS\s+[^\]]+\]\s*$', ' [OS ' || numero_os.numero || ']', 'i')
      else regexp_replace(btrim(m.motivo), '\mOS\s+\d+\M', 'OS ' || numero_os.numero, 'i')
    end as texto
  ) motivo
  where m.tenant_id = p_tenant_id
    and m.empresa_id = p_empresa_id
    and p_tenant_id = public.current_tenant_id()
    and p_empresa_id = public.current_empresa_id()
    and public.fn_item_busca_corresponde(
      concat_ws(' ', i.busca_item, motivo.texto, f.nome,
        case when numero_os.numero is not null then concat_ws(' ',
          'OS', numero_os.numero, os.cliente_nome, os.descricao_servico
        ) end
      ),
      p_busca
    )
  order by m.id desc
  limit greatest(1, least(coalesce(p_limite, 1000), 1000));
$$;

revoke all on function public.movimentacoes_buscar(uuid, uuid, text, integer) from public, anon;
grant execute on function public.movimentacoes_buscar(uuid, uuid, text, integer) to authenticated;

comment on function public.movimentacoes_buscar(uuid, uuid, text, integer) is
  'Busca normalizada por termos no item, motivo, fornecedor e OS, limitada ao tenant/empresa e as RLS do usuario.';

notify pgrst, 'reload schema';
commit;
