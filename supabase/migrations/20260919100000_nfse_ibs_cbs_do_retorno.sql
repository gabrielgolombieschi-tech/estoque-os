-- IBS/CBS que o ambiente nacional devolveu na NFS-e autorizada.
--
-- Pedido do Gabriel em 18/09/2026: o calculo do ERP vale como previa; na nota autorizada quem
-- manda sao os valores devolvidos. O XML da NFS-e ja e arquivado em f.documento_fiscal_xml, entao
-- nao ha o que recalcular: esta funcao le o grupo IBSCBS do XML guardado e devolve base, IBS, CBS
-- e o municipio de incidencia, para a tela mostrar ao lado da previa.
--
-- Exemplo (NFS-e de teste 23 da OS 298, 18/09/2026): base 49.735,00, IBS UF 49,74, IBS mun 0,00,
-- CBS 447,62, incidencia Blumenau.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local role postgres;

create or replace function f.fn_nfse_ibs_cbs_retorno(p_documento_fiscal_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog'
set row_security to 'off'
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_doc f.documento_fiscal%rowtype;
  v_xml text;
  v_bloco text;
  v_num numeric;
begin
  select * into v_doc from f.documento_fiscal d where d.id = p_documento_fiscal_id and d.deleted_at is null;
  if not found then
    raise exception using errcode = 'P0002', message = 'Documento fiscal nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_doc.tenant_id
    or public.current_empresa_id() is distinct from v_doc.empresa_id
    or not f.has_finance_access(v_doc.tenant_id, v_doc.empresa_id)
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para ler esta nota.';
  end if;

  select x.xml_raw into v_xml
  from f.documento_fiscal_xml x
  where x.documento_fiscal_id = p_documento_fiscal_id and x.deleted_at is null
  order by x.created_at desc
  limit 1;
  if v_xml is null then
    return jsonb_build_object('tem_retorno', false, 'motivo', 'XML da NFS-e ainda nao arquivado.');
  end if;

  v_bloco := substring(v_xml from '<IBSCBS>(.*?)</IBSCBS>');
  if v_bloco is null then
    return jsonb_build_object('tem_retorno', false, 'motivo', 'O XML desta nota nao traz o grupo IBS/CBS.');
  end if;

  v_num := nullif(substring(v_bloco from '<vBC>([0-9.]+)</vBC>'), '')::numeric;
  return jsonb_build_object(
    'tem_retorno', v_num is not null,
    'base', v_num,
    'ibs_uf', nullif(substring(v_bloco from '<gIBSUFTot><vIBSUF>([0-9.]+)</vIBSUF>'), '')::numeric,
    'ibs_mun', nullif(substring(v_bloco from '<gIBSMunTot><vIBSMun>([0-9.]+)</vIBSMun>'), '')::numeric,
    'cbs', nullif(substring(v_bloco from '<gCBS><vCBS>([0-9.]+)</vCBS>'), '')::numeric,
    'total_nota', nullif(substring(v_bloco from '<vTotNF>([0-9.]+)</vTotNF>'), '')::numeric,
    'municipio_incidencia', nullif(substring(v_bloco from '<cLocalidadeIncid>([0-9]+)</cLocalidadeIncid>'), ''),
    'municipio_incidencia_nome', nullif(substring(v_bloco from '<xLocalidadeIncid>([^<]*)</xLocalidadeIncid>'), '')
  );
end;
$$;

comment on function f.fn_nfse_ibs_cbs_retorno(uuid) is
  'IBS/CBS devolvido pelo ambiente nacional, lido do XML arquivado da NFS-e: base, IBS UF/mun, CBS e municipio de incidencia (20260919100000).';

revoke all on function f.fn_nfse_ibs_cbs_retorno(uuid) from public, anon;
grant execute on function f.fn_nfse_ibs_cbs_retorno(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
