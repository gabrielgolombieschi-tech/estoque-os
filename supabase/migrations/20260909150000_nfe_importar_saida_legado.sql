-- Importar NF-e de saida do sistema antigo volta a funcionar.
--
-- Gabriel, 09/09/2026: importou a NF-e 55/1/3804 (ARCELORMITTAL, R$ 433.434,55,
-- autorizada em 03/09 sob o protocolo 242260415804053) e ela nao apareceu na lista de
-- saidas. O documento ficou parado como ENTRADA, sem cliente e sem nfe_status.
--
-- O importador (app/api/faturamento/nfe/importar-xml) trabalha em duas fases: cria o
-- documento a partir da nf_entrada, que nasce ENTRADA com o fornecedor sintetico
-- "FATURAMENTO (EMITENTE)", e depois o promove para SAIDA/EMITIDA amarrando cliente e
-- OS. A segunda fase roda como authenticated e batia na mesma trava de EMITIDA que
-- ja tinha quebrado o vinculo de OS (20260909140000). Reproduzido em teste.
--
-- Por isso as notas 3793, 3795, 3798, 3799 e 3801 entraram certas (importadas em 01/09,
-- antes da trava, que e de 20260903123000) e a 3804 nao (09/09, depois dela).
--
-- A trava nasceu para o pipeline de emissao: ninguem pode declarar autorizada uma NF-e
-- que nao passou pelo claim e pela SEFAZ. Importar XML e outro fluxo — nao emite nada,
-- registra uma nota que a SEFAZ ja autorizou. Documento do pipeline nem chega nesta
-- linha: para no bloco anterior, que so aceita dois updates nomeados.
--
-- Liberado apenas o que traz prova de carga de XML: origem IMPORTADO, nf_entrada de
-- origem preenchida e chave de 44 digitos. Segue barrado promover a EMITIDA qualquer
-- documento sem essas tres marcas, e continua valendo a excecao de os_id_import da
-- migration anterior.

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
     )
     and not (
       -- Carga de NF-e que a SEFAZ ja autorizou, trazida por XML pelo importador de
       -- saida. Esse fluxo nao emite nada: registra uma nota que ja existe, com chave
       -- de 44 digitos e o XML guardado na nf_entrada de origem. Documento do pipeline
       -- nunca chega aqui — para no bloco anterior, que e mais restritivo.
       coalesce(new.origem, '') = 'IMPORTADO'
       and new.source_nf_entrada_id is not null
       and coalesce(new.chave_acesso, '') ~ '^[0-9]{44}'
       and length(coalesce(new.chave_acesso, '')) = 44
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
