-- NFS-e: marca no log o destino da DPS quando a Focus recusa o POST de forma
-- sincrona (HTTP 4xx/5xx). O caminho assincrono (erro_autorizacao) ja e coberto
-- por f.fn_nfse_aplicar_retorno; o retry renumera e marca a antiga de qualquer
-- forma. Objeto novo; sem baseline.
create or replace function f.fn_nfse_dps_marcar(p_documento_fiscal_id uuid, p_resultado text, p_mensagem text default null)
returns void
language plpgsql
security definer
set search_path = pg_catalog
set row_security = off
as $$
declare
  v_emissao f.documento_fiscal_emissao%rowtype;
begin
  if session_user <> 'postgres' and coalesce(auth.jwt()->>'role', '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Somente o backend fiscal marca a DPS.';
  end if;
  if p_resultado not in ('REJEITADO', 'ERRO') then
    raise exception using errcode = '22023', message = 'Resultado invalido para a DPS.';
  end if;
  select dfe.* into v_emissao from f.documento_fiscal_emissao dfe where dfe.documento_fiscal_id = p_documento_fiscal_id and dfe.modelo = 'NFSE';
  if not found then return; end if;
  update f.dps_numero_log
  set resultado = p_resultado, mensagem = left(coalesce(p_mensagem, mensagem), 1000), updated_at = now()
  where documento_fiscal_id = v_emissao.documento_fiscal_id and serie = v_emissao.dps_serie and numero = v_emissao.dps_numero
    and resultado in ('RESERVADO', 'REJEITADO', 'ERRO');
end;
$$;
revoke all on function f.fn_nfse_dps_marcar(uuid, text, text) from public;
grant execute on function f.fn_nfse_dps_marcar(uuid, text, text) to service_role;
