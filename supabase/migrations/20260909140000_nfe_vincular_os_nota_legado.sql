-- Vincular OS a NF-e de saida do legado volta a funcionar.
--
-- Gabriel, 09/09/2026: a tela de detalhe da NF-e (Salvar OS) devolvia "Erro inesperado
-- ao salvar a OS vinculada" ao amarrar a NF-e 55/1/3752 da INCEPA na OS 251. A causa
-- era a trava final de f.fn_nfe_bloquear_documento_dml_direto, escrita sobre o ESTADO
-- ("o resultado nao pode ser EMITIDA") e nao sobre a TRANSICAO ("nao pode passar a
-- EMITIDA"). Com isso qualquer update numa nota de saida modelo 55 ja emitida era
-- recusado, inclusive um que so preenche os_id_import.
--
-- Alcance do problema: 193 notas importadas de saida modelo 55 estao EMITIDA, 159 delas
-- sem OS vinculada — nenhuma podia ser amarrada a carteira por esta tela.
--
-- O que continua barrado: nascer EMITIDA, passar de qualquer status para EMITIDA e
-- alterar qualquer outro campo de uma nota emitida. Documentos do pipeline (com
-- f.documento_fiscal_emissao) seguem parando no bloco anterior, que e mais restritivo.
-- Liberado apenas o update que so mexe em os_id_import, que e vinculo de carteira e
-- nao toca em nada do documento fiscal.

CREATE OR REPLACE FUNCTION f.fn_nfe_bloquear_documento_dml_direto()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_vinculado boolean := false;
  v_authenticated boolean := current_user = 'authenticated'
    or coalesce(auth.jwt()->>'role', '') = 'authenticated';
begin
  if not v_authenticated then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op <> 'INSERT' then
    select exists (
      select 1
      from f.documento_fiscal_emissao dfe
      where dfe.tenant_id = old.tenant_id
        and dfe.empresa_id = old.empresa_id
        and dfe.documento_fiscal_id = old.id
    ) into v_vinculado;

    if v_vinculado then
      -- Descarte autenticado de HOM RASCUNHO nunca tentada.
      if tg_op = 'UPDATE'
         and old.nfe_status = 'RASCUNHO'
         and new.nfe_status = 'CANCELADA'
         and (to_jsonb(new) - array['nfe_status','updated_at']::text[])
             is not distinct from
             (to_jsonb(old) - array['nfe_status','updated_at']::text[])
         and exists (
           select 1
           from f.documento_fiscal_emissao hom
           where hom.tenant_id = old.tenant_id
             and hom.empresa_id = old.empresa_id
             and hom.documento_fiscal_id = old.id
             and hom.ambiente = 'HOMOLOGACAO'
             and hom.status = 'CANCELADA'
             and hom.tentativa_count = 0
             and hom.payload_enviado is null
             and hom.enviado_em is null
             and hom.ultima_tentativa_em is null
         )
         and not exists (
           select 1
           from f.documento_fiscal_emissao prod
           where prod.tenant_id = old.tenant_id
             and prod.empresa_id = old.empresa_id
             and prod.solicitacao_id = (
               select hom.solicitacao_id
               from f.documento_fiscal_emissao hom
               where hom.tenant_id = old.tenant_id
                 and hom.empresa_id = old.empresa_id
                 and hom.documento_fiscal_id = old.id
                 and hom.ambiente = 'HOMOLOGACAO'
               limit 1
             )
             and prod.ambiente = 'PRODUCAO'
         ) then
        return new;
      end if;

      -- Vinculo de operacao fiscal em rascunho, anterior a qualquer claim.
      if tg_op = 'UPDATE'
         and (to_jsonb(new) - array['nfe_referenciada','updated_at','updated_by']::text[])
             is not distinct from
             (to_jsonb(old) - array['nfe_referenciada','updated_at','updated_by']::text[])
         and exists (
           select 1
           from f.documento_fiscal_emissao hom
           where hom.tenant_id = old.tenant_id
             and hom.empresa_id = old.empresa_id
             and hom.documento_fiscal_id = old.id
             and hom.ambiente = 'HOMOLOGACAO'
             and hom.status = 'RASCUNHO'
             and hom.tentativa_count = 0
             and hom.payload_enviado is null
             and hom.enviado_em is null
             and hom.ultima_tentativa_em is null
         )
         and not exists (
           select 1
           from f.documento_fiscal_emissao prod
           where prod.tenant_id = old.tenant_id
             and prod.empresa_id = old.empresa_id
             and prod.solicitacao_id = (
               select hom.solicitacao_id
               from f.documento_fiscal_emissao hom
               where hom.tenant_id = old.tenant_id
                 and hom.empresa_id = old.empresa_id
                 and hom.documento_fiscal_id = old.id
                 and hom.ambiente = 'HOMOLOGACAO'
               limit 1
             )
             and prod.ambiente = 'PRODUCAO'
         )
         and exists (
           select 1
           from f.operacao_fiscal op
           where op.tenant_id = old.tenant_id
             and op.empresa_id = old.empresa_id
             and op.deleted_at is null
             and (
               (
                 op.documento_primeira_nota_id = old.id
                 and new.nfe_referenciada is not distinct from op.nfe_referenciada
               )
               or (
                 op.documento_segunda_nota_id = old.id
                 and new.nfe_referenciada is not distinct from op.chave_primeira_nota
               )
             )
         ) then
        return new;
      end if;

      raise exception using
        errcode = '42501',
        message = 'Documento fiscal gerenciado pelo pipeline de NF-e so pode ser alterado ou excluido por RPC fiscal.';
    end if;
  end if;

  -- A trava e sobre a TRANSICAO para EMITIDA, nao sobre o documento ja emitido.
  -- Escrita como estava, ela recusava qualquer update cujo resultado fosse EMITIDA e
  -- deixava as notas do legado intocaveis: vincular a OS pela tela de detalhe da NF-e
  -- caia aqui (09/09/2026, NF-e 55/1/3752 da INCEPA e a OS 251). Segue barrado promover
  -- um documento a EMITIDA por fora do pipeline e alterar qualquer campo de uma nota ja
  -- emitida; liberado apenas amarrar ou desamarrar a OS, que e vinculo de carteira.
  if tg_op <> 'DELETE'
     and upper(btrim(coalesce(new.operacao, ''))) = 'SAIDA'
     and btrim(coalesce(new.modelo, '')) = '55'
     and upper(btrim(coalesce(new.nfe_status, ''))) = 'EMITIDA'
     and not (
       tg_op = 'UPDATE'
       and upper(btrim(coalesce(old.nfe_status, ''))) = 'EMITIDA'
       and (to_jsonb(new) - array['os_id_import','updated_at','updated_by']::text[])
           is not distinct from
           (to_jsonb(old) - array['os_id_import','updated_at','updated_by']::text[])
     ) then
    raise exception using
      errcode = '42501',
      message = 'NF-e de saida modelo 55 nao pode ser marcada EMITIDA diretamente; use o pipeline fiscal autorizado.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$
;
