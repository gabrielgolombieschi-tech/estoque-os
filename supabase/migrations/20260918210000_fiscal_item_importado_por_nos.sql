-- "Importado por nos (DIR/DI no nosso CNPJ)": caminho manual, na tela fiscal do item, para
-- marcar o produto como importado pela propria empresa.
--
-- Pedido do Gabriel em 18/09/2026 (OV-SEG-00004-026, CPU de CLP OMRON CQM1H-CPU61, item 3629):
-- a Segau e a importadora (DIR 260191366846, NF-e de entrada 2/24), entao na revenda ela e
-- equiparada a industrial (RIPI, Decreto 7.212/2010, art. 9o, I) e destaca o IPI da TIPI.
-- Ate aqui so a entrada de importacao em 3101/3102 marcava isso (20260918020000); a 2/24 saiu
-- em 3556 (uso e consumo) e o cadastro ficou como comprado de distribuidor (origem 2, IPI 53).
--
-- O que a marcacao faz no cadastro fiscal do item, de uma vez:
--   origem 1 (estrangeira, importacao direta), origem_entrada 1, equiparado_industrial true,
--   CST IPI 50 com a aliquota vigente do NCM em f.tipi_ncm (51 com 0% quando a TIPI e zero).
--   cEnq nao e do produto (tg_fiscal_item_bloquear_cenq_produto): sai do perfil da operacao.
-- Exige o numero da DIR (12 digitos) ou da DI (10 digitos) e a nota de entrada (numero/serie ou
-- chave); quando a nota existe no ERP e esta ligada a uma importacao, a DIR tem de ser a mesma.
-- Grava quem marcou e quando (colunas importado_por_nos_*); o audit_log de fiscal_itens guarda
-- o antes e o depois.
--
-- Permissao: a mesma da tela fiscal do item (fiscal_itens.write).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

alter table public.fiscal_itens
  add column if not exists importado_por_nos_dir text,
  add column if not exists importado_por_nos_nota text,
  add column if not exists importado_por_nos_documento_fiscal_id uuid references f.documento_fiscal(id) on delete set null,
  add column if not exists importado_por_nos_em timestamptz,
  add column if not exists importado_por_nos_por uuid;

comment on column public.fiscal_itens.importado_por_nos_dir is
  'Numero da DIR (12 digitos) ou DI (10 digitos) registrada no CNPJ da empresa que prova a importacao direta do item (equiparacao a industrial, RIPI art. 9o, I).';
comment on column public.fiscal_itens.importado_por_nos_nota is
  'Nota de entrada da importacao como foi informada (numero/serie ou chave).';
comment on column public.fiscal_itens.importado_por_nos_documento_fiscal_id is
  'NF-e de entrada da importacao no ERP, quando a nota informada foi encontrada.';
comment on column public.fiscal_itens.importado_por_nos_em is
  'Quando o item foi marcado como importado pela propria empresa pela tela fiscal.';
comment on column public.fiscal_itens.importado_por_nos_por is
  'auth.uid() de quem marcou.';

-- A mesma checagem da copia de similar, com nome que diz o que ela e.
create or replace function public.fiscal_item_permissao_editar()
returns void
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $fn$
declare
  v_tenant uuid := public.current_tenant_id();
  v_empresa uuid := public.current_empresa_id();
begin
  if auth.uid() is null
     or v_tenant is null
     or v_empresa is null
     or not public.has_active_empresa_access(v_tenant, v_empresa)
     or not coalesce(public.can('fiscal_itens', 'write'), false) then
    raise exception using errcode = '42501',
      message = 'Sem permissao para editar o cadastro fiscal de itens.';
  end if;
end;
$fn$;

revoke all on function public.fiscal_item_permissao_editar() from public, anon;
grant execute on function public.fiscal_item_permissao_editar() to authenticated;

create or replace function public.web_fiscal_item_marcar_importado_por_nos(
  p_item_id integer,
  p_dir_numero text,
  p_nota_entrada text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $fn$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_dir text := regexp_replace(coalesce(p_dir_numero, ''), '[^0-9]', '', 'g');
  v_nota text := btrim(coalesce(p_nota_entrada, ''));
  v_nota_digitos text;
  v_serie text;
  v_numero text;
  v_doc f.documento_fiscal%rowtype;
  v_dir_da_nota text;
  v_fi public.fiscal_itens%rowtype;
  v_antes public.fiscal_itens%rowtype;
  v_ncm text;
  v_tipi numeric;
  v_cst_ipi text;
begin
  perform public.fiscal_item_permissao_editar();
  v_tenant := public.current_tenant_id();
  v_empresa := public.current_empresa_id();

  if v_dir !~ '^[0-9]{10,12}$' then
    raise exception using errcode = '22023',
      message = 'Informe o numero da DIR (12 digitos) ou da DI (10 digitos) registrada no CNPJ da empresa.';
  end if;
  if v_nota = '' then
    raise exception using errcode = '22023',
      message = 'Informe a nota de entrada da importacao: numero/serie (ex.: 2/24) ou a chave de 44 digitos.';
  end if;
  if length(v_nota) > 60 then
    raise exception using errcode = '22023', message = 'Nota de entrada com mais de 60 caracteres.';
  end if;

  select fi.* into v_fi
  from public.fiscal_itens fi
  where fi.tenant_id = v_tenant and fi.empresa_id = v_empresa and fi.item_id = p_item_id
  for update;
  if not found then
    raise exception using errcode = 'P0002',
      message = format('O item #%s nao tem cadastro fiscal nesta empresa. Salve NCM e origem antes.', p_item_id);
  end if;
  v_antes := v_fi;

  v_ncm := regexp_replace(coalesce(v_fi.ncm, ''), '[^0-9]', '', 'g');
  if v_ncm !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023',
      message = 'O NCM do item precisa ter 8 digitos antes de marcar a importacao.';
  end if;

  -- Quem importa e equiparado a industrial e destaca o IPI da TIPI na saida: sem a
  -- aliquota cadastrada nao ha o que destacar, e a nota sairia errada.
  select t.aliquota into v_tipi
  from f.tipi_ncm t
  where t.ncm = v_ncm
    and t.vigencia_inicio <= current_date
    and (t.vigencia_fim is null or t.vigencia_fim >= current_date)
  order by t.vigencia_inicio desc
  limit 1;
  if v_tipi is null then
    raise exception using errcode = '22023',
      message = format('NCM %s sem aliquota na TIPI (f.tipi_ncm). Cadastre a aliquota antes: o importador destaca o IPI da TIPI ao revender.', v_ncm);
  end if;

  -- Nota de entrada: chave de 44 digitos ou "serie/numero". Se existir no ERP, tem de ser
  -- de ENTRADA e, quando ligada a uma importacao, da mesma DIR.
  v_nota_digitos := regexp_replace(v_nota, '[^0-9]', '', 'g');
  if length(v_nota_digitos) = 44 then
    select d.* into v_doc
    from f.documento_fiscal d
    where d.tenant_id = v_tenant and d.empresa_id = v_empresa and d.deleted_at is null
      and regexp_replace(coalesce(d.chave_acesso, ''), '[^0-9]', '', 'g') = v_nota_digitos
    order by d.created_at desc
    limit 1;
  elsif v_nota ~ '^[0-9]+\s*/\s*[0-9]+$' then
    v_serie := split_part(regexp_replace(v_nota, '\s', '', 'g'), '/', 1);
    v_numero := split_part(regexp_replace(v_nota, '\s', '', 'g'), '/', 2);
    select d.* into v_doc
    from f.documento_fiscal d
    where d.tenant_id = v_tenant and d.empresa_id = v_empresa and d.deleted_at is null
      and d.modelo = '55' and d.operacao = 'ENTRADA'
      and ltrim(coalesce(d.serie, ''), '0') = ltrim(v_serie, '0')
      and ltrim(coalesce(d.numero, ''), '0') = ltrim(v_numero, '0')
    order by d.created_at desc
    limit 1;
  end if;
  if v_doc.id is not null then
    if v_doc.operacao <> 'ENTRADA' then
      raise exception using errcode = '22023',
        message = format('A NF-e %s/%s e de saida; informe a nota de ENTRADA da importacao.', v_doc.serie, v_doc.numero);
    end if;
    select regexp_replace(coalesce(r.dir_numero, ''), '[^0-9]', '', 'g') into v_dir_da_nota
    from f.importacao_remessa r
    where r.documento_fiscal_id = v_doc.id and r.deleted_at is null
    limit 1;
    if nullif(v_dir_da_nota, '') is not null and v_dir_da_nota <> v_dir then
      raise exception using errcode = '22023',
        message = format('A NF-e %s/%s e da DIR %s, nao da %s.', v_doc.serie, v_doc.numero, v_dir_da_nota, v_dir);
    end if;
  end if;

  v_cst_ipi := case when v_tipi > 0 then '50' else '51' end;

  update public.fiscal_itens fi
     set origem = 1,
         origem_entrada = 1,
         equiparado_industrial = true,
         cst_ipi = v_cst_ipi,
         aliq_ipi = v_tipi,
         importado_por_nos_dir = v_dir,
         importado_por_nos_nota = v_nota,
         importado_por_nos_documento_fiscal_id = v_doc.id,
         importado_por_nos_em = now(),
         importado_por_nos_por = auth.uid(),
         atualizado_em = now()
   where fi.id = v_fi.id
  returning fi.* into v_fi;

  return jsonb_build_object(
    'ok', true,
    'item_id', p_item_id,
    'antes', jsonb_build_object(
      'origem', v_antes.origem, 'origem_entrada', v_antes.origem_entrada,
      'equiparado_industrial', v_antes.equiparado_industrial,
      'cst_ipi', v_antes.cst_ipi, 'aliq_ipi', v_antes.aliq_ipi),
    'depois', jsonb_build_object(
      'origem', v_fi.origem, 'origem_entrada', v_fi.origem_entrada,
      'equiparado_industrial', v_fi.equiparado_industrial,
      'cst_ipi', v_fi.cst_ipi, 'aliq_ipi', v_fi.aliq_ipi,
      'dir', v_fi.importado_por_nos_dir, 'nota', v_fi.importado_por_nos_nota,
      'documento_fiscal_id', v_fi.importado_por_nos_documento_fiscal_id,
      'em', v_fi.importado_por_nos_em, 'por', v_fi.importado_por_nos_por),
    'documento_fiscal', case when v_doc.id is null then null else jsonb_build_object(
      'id', v_doc.id, 'serie', v_doc.serie, 'numero', v_doc.numero,
      'chave', v_doc.chave_acesso, 'emissao', v_doc.emissao_date) end,
    'tipi', v_tipi
  );
end;
$fn$;

comment on function public.web_fiscal_item_marcar_importado_por_nos(integer, text, text) is
  'Tela fiscal do item: marca o produto como importado pela propria empresa (DIR/DI no CNPJ dela): origem 1, equiparado a industrial, IPI 50 com a aliquota da TIPI. Exige DIR/DI e nota de entrada; grava quem e quando.';

revoke all on function public.web_fiscal_item_marcar_importado_por_nos(integer, text, text) from public, anon;
grant execute on function public.web_fiscal_item_marcar_importado_por_nos(integer, text, text) to authenticated;

do $assertions$
begin
  if to_regprocedure('public.web_fiscal_item_marcar_importado_por_nos(integer, text, text)') is null then
    raise exception 'web_fiscal_item_marcar_importado_por_nos nao existe';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'fiscal_itens' and column_name = 'importado_por_nos_em'
  ) then
    raise exception 'fiscal_itens.importado_por_nos_em nao foi criada';
  end if;
end;
$assertions$;

notify pgrst, 'reload schema';

commit;
