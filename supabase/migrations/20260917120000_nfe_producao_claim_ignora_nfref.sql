-- O claim de producao compara o payload real com o da homologacao autorizada e so tolera as
-- diferencas de ambiente (datas, nome do destinatario). O retorno de mercadoria de terceiros
-- leva o NFref (notas_referenciadas) SO em producao — a SEFAZ de homologacao nao conhece a
-- chave de producao da nota de origem (rejeicao 267 em 16/09/2026) — e a producao da WEG
-- 900356/1 parou aqui: "O payload de producao diverge do payload HOM autorizado fora das
-- diferencas legitimas de ambiente". O montador (nfe-payload.ts) ja ignora o grupo na mesma
-- comparacao; o banco passa a ignorar tambem. A chave continua congelada no infCpl.
--
-- Mesma definicao de f.fn_nfe_producao_preparar_e_claimar, so a lista de chaves toleradas
-- muda (o texto e substituido na definicao atual, sem repetir a funcao inteira).
do $$
declare
  v_oid oid;
  v_def text;
  v_antes text := 'array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'']::text[]';
  v_depois text := 'array[''data_emissao'',''data_entrada_saida'',''nome_destinatario'',''ambiente'',''ambiente_emissao'',''notas_referenciadas'']::text[]';
  v_ocorrencias integer;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'f' and p.proname = 'fn_nfe_producao_preparar_e_claimar';
  if v_oid is null then
    raise exception 'f.fn_nfe_producao_preparar_e_claimar nao encontrada';
  end if;
  v_def := pg_get_functiondef(v_oid);
  v_ocorrencias := (length(v_def) - length(replace(v_def, v_antes, ''))) / length(v_antes);
  if v_ocorrencias = 0 then
    if position(v_depois in v_def) > 0 then
      raise notice 'fn_nfe_producao_preparar_e_claimar ja ignora notas_referenciadas';
      return;
    end if;
    raise exception 'fn_nfe_producao_preparar_e_claimar sem a lista de diferencas esperada; conferir a definicao antes de trocar';
  end if;
  if v_ocorrencias <> 2 then
    raise exception 'fn_nfe_producao_preparar_e_claimar com % ocorrencia(s) da lista (esperadas 2)', v_ocorrencias;
  end if;
  execute replace(v_def, v_antes, v_depois);
end $$;
