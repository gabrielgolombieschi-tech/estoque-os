begin;

-- Reconstroi as lacunas numero a numero para que inutilizacoes parciais sejam
-- retiradas da lista e os trechos restantes continuem aparecendo separados.
create or replace function f.fn_nfe_lacunas()
returns table (
  serie integer, numero_inicial integer, numero_final integer,
  detectada_em date, prazo_inutilizar date, alerta boolean
)
language sql security definer set search_path = pg_catalog set row_security = off stable
as $function$
  with scope as (
    select * from f.fn_operacao_assert_acesso()
  ), numeros as (
    select distinct d.serie::integer serie, d.numero::integer numero,
      coalesce(d.emissao_date, d.created_at::date) emissao
    from f.documento_fiscal d, scope s
    where d.tenant_id = s.tenant_id and d.empresa_id = s.empresa_id
      and d.modelo = '55' and d.serie ~ '^[0-9]+$' and d.numero ~ '^[0-9]+$'
      and d.deleted_at is null
  ), limites as (
    select serie, max(numero) maximo from numeros group by serie
  ), faltantes as (
    select l.serie, gs.numero,
      (select min(n.emissao) from numeros n where n.serie=l.serie and n.numero>gs.numero) detectada_em
    from limites l
    cross join lateral generate_series(1, greatest(l.maximo-1,0)) gs(numero)
    where not exists (select 1 from numeros n where n.serie=l.serie and n.numero=gs.numero)
      and not exists (
        select 1 from f.nfe_inutilizacao ni, scope s
        where ni.tenant_id=s.tenant_id and ni.empresa_id=s.empresa_id
          and ni.serie=l.serie and ni.status='AUTORIZADA'
          and gs.numero between ni.numero_inicial and ni.numero_final
      )
  ), ilhas as (
    select f.*, f.numero-row_number() over(partition by f.serie order by f.numero) grupo
    from faltantes f
  )
  select i.serie, min(i.numero)::integer, max(i.numero)::integer, min(i.detectada_em),
    (date_trunc('month', min(i.detectada_em))::date + interval '1 month 9 days')::date,
    current_date >= (date_trunc('month', min(i.detectada_em))::date + interval '1 month 4 days')::date
  from ilhas i
  group by i.serie, i.grupo
  order by i.serie, min(i.numero);
$function$;

create or replace function f.fn_nfe_inutilizacao_validar(
  p_serie integer, p_numero_inicial integer, p_numero_final integer, p_justificativa text
)
returns jsonb language plpgsql security definer set search_path = pg_catalog set row_security = off stable
as $function$
declare v_scope record; v_cnpj text;
begin
  select * into v_scope from f.fn_operacao_assert_acesso();
  if p_serie is null or p_serie not between 0 and 999 then raise exception 'Serie invalida.'; end if;
  if p_numero_inicial is null or p_numero_inicial <= 0 or p_numero_final < p_numero_inicial then raise exception 'Faixa de numeracao invalida.'; end if;
  if char_length(btrim(coalesce(p_justificativa, ''))) not between 15 and 255 then raise exception 'Justificativa deve ter entre 15 e 255 caracteres.'; end if;
  if exists (
    select 1 from f.documento_fiscal d
    where d.tenant_id = v_scope.tenant_id and d.empresa_id = v_scope.empresa_id
      and d.modelo = '55' and d.serie = p_serie::text and d.numero ~ '^[0-9]+$'
      and d.numero::integer between p_numero_inicial and p_numero_final and d.deleted_at is null
  ) then raise exception 'Faixa contem numero ja registrado (autorizado, cancelado, denegado ou rejeitado).'; end if;
  if exists (
    select 1 from f.nfe_inutilizacao ni
    where ni.tenant_id=v_scope.tenant_id and ni.empresa_id=v_scope.empresa_id
      and ni.serie=p_serie and ni.status='AUTORIZADA'
      and int4range(ni.numero_inicial,ni.numero_final,'[]') && int4range(p_numero_inicial,p_numero_final,'[]')
  ) then raise exception 'Faixa sobrepoe numeracao ja inutilizada.'; end if;
  select e.cnpj into v_cnpj from c.empresa e where e.tenant_id = v_scope.tenant_id and e.id = v_scope.empresa_id;
  if v_cnpj !~ '^[0-9]{14}$' then raise exception 'Empresa sem CNPJ valido para inutilizacao.'; end if;
  return jsonb_build_object('tenant_id', v_scope.tenant_id, 'empresa_id', v_scope.empresa_id,
    'cnpj', v_cnpj, 'serie', p_serie, 'numero_inicial', p_numero_inicial,
    'numero_final', p_numero_final, 'justificativa', btrim(p_justificativa), 'ambiente', 'HOMOLOGACAO');
end;
$function$;

commit;
