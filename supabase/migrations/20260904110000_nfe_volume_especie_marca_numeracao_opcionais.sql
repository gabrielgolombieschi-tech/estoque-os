-- Torna especie, marca e numeracao do volume opcionais.
--
-- PROBLEMA
-- f.fn_solicitacao_nfe_salvar_transporte exigia os seis campos do volume. No
-- layout da NF-e o grupo vol (X26) e inteiramente opcional, e as notas de
-- producao da propria SEGAU saem sem esses tres: conferido na NF 3772 / serie 1,
-- autorizada sob o protocolo 242260375531137 em 12/08/2026, que traz somente
-- quantidade 1 e pesos 0,20 — especie, marca e numeracao em branco.
-- Com a regra antiga era impossivel reproduzir no sistema uma nota que a empresa
-- ja emite normalmente. A validacao equivalente do frontend
-- (camposObrigatoriosPendentes, em OvNfeDraftsPanel.tsx) foi relaxada junto, para
-- as duas pontas nao divergirem.
--
-- O que continua obrigatorio quando ha transporte: a transportadora, ao menos um
-- volume, a quantidade e os dois pesos — deles a expedicao depende. As validacoes
-- numericas (quantidade inteira e positiva, peso bruto >= peso liquido) seguem
-- iguais.

begin;

create or replace function f.fn_solicitacao_nfe_salvar_transporte(p_solicitacao_id uuid, p_transporte jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
 set row_security to 'off'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', '');
  v_sf f.solicitacao_faturamento%rowtype;
  v_transportador jsonb;
  v_volumes jsonb;
  v_volume jsonb;
  v_indice integer := 0;
begin
  select * into v_sf
  from f.solicitacao_faturamento sf
  where sf.id = p_solicitacao_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Rascunho de NF-e nao encontrado.';
  end if;
  if session_user <> 'postgres' and v_role <> 'service_role' and (
    public.current_tenant_id() is distinct from v_sf.tenant_id
    or public.current_empresa_id() is distinct from v_sf.empresa_id
    or not f.has_finance_access()
  ) then
    raise exception using errcode = '42501', message = 'Sem permissao para conferir o transporte desta NF-e.';
  end if;
  if v_sf.status not in ('RASCUNHO', 'PREVIA', 'APROVADA') then
    raise exception using errcode = '22023', message = 'Esta solicitacao nao pode mais ser alterada.';
  end if;
  if jsonb_typeof(p_transporte) is distinct from 'object' then
    raise exception using errcode = '22023', message = 'Os dados de transporte sao obrigatorios.';
  end if;

  v_transportador := p_transporte->'transportador';
  if v_transportador = 'null'::jsonb then v_transportador := null; end if;
  v_volumes := coalesce(p_transporte->'volumes', '[]'::jsonb);

  if v_sf.modalidade_frete = 9 and v_transportador is null then
    update f.solicitacao_faturamento
    set transportador_dados = null,
        volumes_dados = null,
        operacao_snapshot = null,
        snapshot_cadastro_em = null,
        updated_at = now()
    where tenant_id = v_sf.tenant_id
      and empresa_id = v_sf.empresa_id
      and id = v_sf.id;
    return jsonb_build_object(
      'ok', true, 'solicitacao_id', v_sf.id, 'tenant_id', v_sf.tenant_id,
      'empresa_id', v_sf.empresa_id, 'volumes', 0, 'possui_transportador', false
    );
  end if;

  if v_transportador is null
     or jsonb_typeof(v_transportador) is distinct from 'object'
     or nullif(btrim(v_transportador->>'nome'), '') is null then
    raise exception using errcode = '22023', message = 'Quando houver transporte, informe a transportadora.';
  end if;
  if jsonb_typeof(v_volumes) is distinct from 'array' or jsonb_array_length(v_volumes) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos um volume quando houver transporte.';
  end if;
  for v_volume in select value from jsonb_array_elements(v_volumes)
  loop
    v_indice := v_indice + 1;
    -- especie, marca e numero sao opcionais (grupo vol X26 da NF-e).
    if jsonb_typeof(v_volume) is distinct from 'object'
       or nullif(btrim(v_volume->>'quantidade'), '') is null
       or nullif(btrim(v_volume->>'peso_liquido'), '') is null
       or nullif(btrim(v_volume->>'peso_bruto'), '') is null then
      raise exception using errcode = '22023', message = format(
        'Volume %s incompleto: quantidade e pesos sao obrigatorios.',
        v_indice
      );
    end if;
    if (v_volume->>'quantidade')::numeric <= 0
       or trunc((v_volume->>'quantidade')::numeric) <> (v_volume->>'quantidade')::numeric
       or (v_volume->>'peso_liquido')::numeric < 0
       or (v_volume->>'peso_bruto')::numeric < (v_volume->>'peso_liquido')::numeric then
      raise exception using errcode = '22023', message = format('Volume %s possui quantidade ou pesos invalidos.', v_indice);
    end if;
  end loop;

  update f.solicitacao_faturamento
  set transportador_dados = v_transportador,
      volumes_dados = v_volumes,
      operacao_snapshot = null,
      snapshot_cadastro_em = null,
      updated_at = now()
  where tenant_id = v_sf.tenant_id
    and empresa_id = v_sf.empresa_id
    and id = v_sf.id;

  return jsonb_build_object(
    'ok', true, 'solicitacao_id', v_sf.id, 'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id, 'volumes', jsonb_array_length(v_volumes),
    'possui_transportador', true
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Quantidade e pesos dos volumes devem ser numeros validos.';
end;
$function$;

commit;
