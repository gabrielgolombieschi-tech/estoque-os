begin;

alter table f.solicitacao_faturamento
  add column transportador_dados jsonb,
  add column volumes_dados jsonb,
  add constraint solicitacao_faturamento_transportador_dados_ck
    check (transportador_dados is null or jsonb_typeof(transportador_dados) = 'object'),
  add constraint solicitacao_faturamento_volumes_dados_ck
    check (volumes_dados is null or jsonb_typeof(volumes_dados) = 'array');

comment on column f.solicitacao_faturamento.transportador_dados is
  'Dados de transporte confirmados na tela. Nulo significa ausência de transportadora e força modFrete 9 no payload.';
comment on column f.solicitacao_faturamento.volumes_dados is
  'Volumes confirmados na tela, congelados em operacao_snapshot antes da emissão.';

create or replace function f.fn_solicitacao_nfe_salvar_transporte(
  p_solicitacao_id uuid,
  p_transporte jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
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
  if v_transportador is not null and (
    jsonb_typeof(v_transportador) is distinct from 'object'
    or nullif(btrim(v_transportador->>'nome'), '') is null
  ) then
    raise exception using errcode = '22023', message = 'Transportador invalido: informe ao menos o nome ou deixe o campo vazio.';
  end if;

  v_volumes := p_transporte->'volumes';
  if jsonb_typeof(v_volumes) is distinct from 'array' or jsonb_array_length(v_volumes) = 0 then
    raise exception using errcode = '22023', message = 'Informe ao menos um volume transportado.';
  end if;
  for v_volume in select value from jsonb_array_elements(v_volumes)
  loop
    v_indice := v_indice + 1;
    if jsonb_typeof(v_volume) is distinct from 'object'
       or nullif(btrim(v_volume->>'quantidade'), '') is null
       or nullif(btrim(v_volume->>'especie'), '') is null
       or nullif(btrim(v_volume->>'marca'), '') is null
       or nullif(btrim(v_volume->>'numero'), '') is null
       or nullif(btrim(v_volume->>'peso_liquido'), '') is null
       or nullif(btrim(v_volume->>'peso_bruto'), '') is null then
      raise exception using errcode = '22023', message = format('Volume %s incompleto: quantidade, especie, marca, numeracao e pesos sao obrigatorios.', v_indice);
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
    'ok', true,
    'solicitacao_id', v_sf.id,
    'tenant_id', v_sf.tenant_id,
    'empresa_id', v_sf.empresa_id,
    'volumes', jsonb_array_length(v_volumes),
    'possui_transportador', v_transportador is not null
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'Quantidade e pesos dos volumes devem ser numeros validos.';
end;
$function$;

comment on function f.fn_solicitacao_nfe_salvar_transporte(uuid, jsonb) is
  'Salva transporte e volumes no rascunho autenticado, sempre no escopo tenant/empresa da solicitacao.';
revoke all on function f.fn_solicitacao_nfe_salvar_transporte(uuid, jsonb) from public, anon;
grant execute on function f.fn_solicitacao_nfe_salvar_transporte(uuid, jsonb) to authenticated, service_role;

create or replace function f.tg_solicitacao_nfe_congelar_transporte()
returns trigger
language plpgsql
set search_path = pg_catalog
as $function$
begin
  if jsonb_typeof(new.operacao_snapshot) = 'object' then
    new.operacao_snapshot := new.operacao_snapshot || jsonb_build_object(
      'transportador', new.transportador_dados,
      'volumes', new.volumes_dados
    );
  end if;
  return new;
end;
$function$;

create trigger tg_solicitacao_nfe_congelar_transporte
before insert or update of operacao_snapshot on f.solicitacao_faturamento
for each row execute function f.tg_solicitacao_nfe_congelar_transporte();

commit;
