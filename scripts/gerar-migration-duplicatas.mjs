/**
 * Gera supabase/migrations/20260905130000_nfe_duplicatas_e_parcelas_ar.sql a
 * partir das definicoes atuais (dumps no scratchpad + migration 20260905110000).
 * Uso unico, mantido para auditoria de como a migration foi montada.
 *
 *   node scripts/gerar-migration-duplicatas.mjs <pasta-com-salvar.sql-e-ar.sql>
 */
import fs from "node:fs";
import path from "node:path";

const S = process.argv[2];
let salvar = fs.readFileSync(path.join(S, "salvar.sql"), "utf8").trim();
let ar = fs.readFileSync(path.join(S, "ar.sql"), "utf8").trim();
const mig110 = fs.readFileSync("supabase/migrations/20260905110000_nfe_serie_no_snapshot_e_origem_item_3629.sql", "utf8");
const ini = mig110.indexOf("CREATE OR REPLACE FUNCTION f.fn_solicitacao_nfe_congelar_cadastro");
const fim = mig110.indexOf("$function$;", ini) + "$function$;".length;
let congelar = mig110.slice(ini, fim);

function trocar(texto, de, para, rotulo) {
  if (!texto.includes(de)) throw new Error(`ancora nao encontrada: ${rotulo}`);
  return texto.replace(de, para);
}

// --- salvar_conferencia: validar/normalizar parcelas e gravar a coluna ---
salvar = trocar(salvar, `  -- xPag e obrigatorio quando tPag = 99 (outros).`, `  -- Parcelas (grupo cobr/dup da NF-e e parcelas do titulo AR). Cada parcela
  -- e "dias apos a emissao" + valor; a data absoluta so existe na emissao.
  -- A prazo sem parcelas informadas recebe o padrao historico do AR: 1 parcela
  -- em 15 dias com o total. Valor nulo em parcela unica significa "o total".
  if (p_operacao->>'pagamento_indicador')::smallint = 1 then
    v_parcelas := f.fn_nfe_normalizar_parcelas(p_operacao->'pagamento_parcelas');
  else
    v_parcelas := null;
  end if;

  -- xPag e obrigatorio quando tPag = 99 (outros).`, "validacao");
salvar = trocar(salvar, `  v_ipi_fonte text;\nbegin`, `  v_ipi_fonte text;\n  v_parcelas jsonb;\nbegin`, "declare");
salvar = trocar(salvar, `      pagamento_descricao = nullif(btrim(p_operacao->>'pagamento_descricao'), ''),`,
`      pagamento_descricao = nullif(btrim(p_operacao->>'pagamento_descricao'), ''),
      pagamento_parcelas = v_parcelas,`, "update");
if (!salvar.endsWith("$function$")) throw new Error("fim inesperado salvar: " + salvar.slice(-30));
salvar += ";";

// --- congelar: parcelas e numero da fatura no snapshot ---
congelar = trocar(congelar, `          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao
          )`, `          'pagamento', jsonb_build_object(
            'forma', pagamento_forma,
            'indicador', pagamento_indicador,
            'descricao', pagamento_descricao,
            'parcelas', case when pagamento_indicador = 1 then pagamento_parcelas else null end,
            'fatura_numero', (
              select os.codigo
              from f.solicitacao_item si
              join public.ordens_servico os on os.id::text = si.origem_id
              where si.tenant_id = v_sf.tenant_id and si.empresa_id = v_sf.empresa_id
                and si.solicitacao_id = v_sf.id and si.origem_tipo = 'OV'
              order by si.ordem limit 1
            )
          )`, "snapshot");

// --- AR: parcelas do snapshot ---
ar = trocar(ar, `  v_venc date;`, `  v_venc date;
  v_parcelas jsonb;
  v_parcela jsonb;
  v_n integer := 0;
  v_pvalor numeric(15,2);`, "ar declare");
ar = trocar(ar, `  v_venc := coalesce(v_df.emissao_date, current_date) + 15;`, `  v_venc := coalesce(v_df.emissao_date, current_date) + 15;

  -- Parcelas confirmadas na conferencia da NF-e (mesma fonte das duplicatas
  -- enviadas a SEFAZ). Sem snapshot, vale o padrao historico de 15 dias.
  select sf.operacao_snapshot->'pagamento'->'parcelas' into v_parcelas
  from f.documento_fiscal_emissao dfe
  join f.solicitacao_faturamento sf
    on sf.tenant_id = dfe.tenant_id and sf.empresa_id = dfe.empresa_id and sf.id = dfe.solicitacao_id
  where dfe.tenant_id = v_df.tenant_id
    and dfe.empresa_id = v_df.empresa_id
    and dfe.documento_fiscal_id = v_df.id
    and dfe.ambiente = 'PRODUCAO'
  limit 1;
  if jsonb_typeof(v_parcelas) is distinct from 'array' or jsonb_array_length(v_parcelas) = 0 then
    v_parcelas := null;
  end if;`, "ar venc");
ar = trocar(ar, `     insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
     values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);`, `     if v_parcelas is null then
       insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
       values (v_df.tenant_id, v_titulo_id, '1', v_venc, v_valor, v_valor);
     else
       for v_parcela in select * from jsonb_array_elements(v_parcelas) loop
         v_n := v_n + 1;
         v_pvalor := coalesce(nullif(v_parcela->>'valor', '')::numeric,
                              case when jsonb_array_length(v_parcelas) = 1 then v_valor end);
         if v_pvalor is null then
           raise exception 'Parcela % da NF-e sem valor no snapshot fiscal.', v_n;
         end if;
         insert into f.titulo_parcela (tenant_id, titulo_id, numero, vencimento_date, valor, valor_aberto)
         values (
           v_df.tenant_id, v_titulo_id, v_n::text,
           coalesce(v_df.emissao_date, current_date) + coalesce((v_parcela->>'dias')::integer, 15),
           v_pvalor, v_pvalor
         );
       end loop;
     end if;`, "ar insert");
if (!ar.endsWith("$function$")) throw new Error("fim inesperado ar: " + ar.slice(-30));
ar += ";";

const head = `-- Duplicatas na NF-e e parcelas do titulo com a mesma origem (05/09/2026).
--
-- A NF-e real 2/1 saiu sem o grupo cobr/dup, enquanto o emissor antigo sempre
-- imprimia as duplicatas; e o Contas a Receber nascia com vencimento fixo em
-- emissao + 15 dias, sem relacao com a nota. Agora:
--
--   * a conferencia grava f.solicitacao_faturamento.pagamento_parcelas como
--     [{numero, dias, valor}] ("dias apos a emissao"; valor nulo em parcela
--     unica = total). A prazo sem parcelas informadas recebe 1 x 15 dias;
--   * o snapshot congelado leva as parcelas e o codigo da OV como numero da
--     fatura; a Edge monta cobr/fat e cobr/dup a partir dele, com as datas
--     calculadas na emissao;
--   * f.fn_upsert_ar_from_nfe_venda cria uma parcela do titulo por duplicata
--     (vencimento = data de emissao + dias), mantendo o padrao antigo quando
--     nao ha snapshot (importacao de XML).

alter table f.solicitacao_faturamento
  add column if not exists pagamento_parcelas jsonb;

comment on column f.solicitacao_faturamento.pagamento_parcelas is
  'Parcelas confirmadas na conferencia: [{numero, dias, valor}]. dias = dias apos a emissao; valor nulo em parcela unica = total. Origem das duplicatas da NF-e e das parcelas do AR.';

-- Normaliza e valida o JSON de parcelas vindo da tela.
create or replace function f.fn_nfe_normalizar_parcelas(p_parcelas jsonb)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_saida jsonb := '[]'::jsonb;
  v_item jsonb;
  v_n integer := 0;
  v_dias integer;
  v_valor numeric;
begin
  if p_parcelas is null or jsonb_typeof(p_parcelas) <> 'array' or jsonb_array_length(p_parcelas) = 0 then
    return jsonb_build_array(jsonb_build_object('numero', '001', 'dias', 15, 'valor', null));
  end if;
  if jsonb_array_length(p_parcelas) > 24 then
    raise exception using errcode = '22023', message = 'No maximo 24 parcelas por NF-e.';
  end if;
  for v_item in select * from jsonb_array_elements(p_parcelas) loop
    v_n := v_n + 1;
    if jsonb_typeof(v_item) <> 'object' then
      raise exception using errcode = '22023', message = format('Parcela %s invalida.', v_n);
    end if;
    begin
      v_dias := (v_item->>'dias')::integer;
    exception when others then
      raise exception using errcode = '22023', message = format('Parcela %s: informe os dias apos a emissao.', v_n);
    end;
    if v_dias is null or v_dias < 0 or v_dias > 3650 then
      raise exception using errcode = '22023', message = format('Parcela %s: dias apos a emissao deve ficar entre 0 e 3650.', v_n);
    end if;
    v_valor := nullif(btrim(coalesce(v_item->>'valor', '')), '')::numeric;
    if v_valor is not null and v_valor <= 0 then
      raise exception using errcode = '22023', message = format('Parcela %s: valor deve ser positivo.', v_n);
    end if;
    if v_valor is null and jsonb_array_length(p_parcelas) > 1 then
      raise exception using errcode = '22023', message = format('Parcela %s: informe o valor quando houver mais de uma parcela.', v_n);
    end if;
    v_saida := v_saida || jsonb_build_object(
      'numero', lpad(v_n::text, 3, '0'),
      'dias', v_dias,
      'valor', case when v_valor is null then null else round(v_valor, 2) end
    );
  end loop;
  return v_saida;
end;
$function$;

`;
const out = head + salvar + "\n\n" + congelar + "\n\n" + ar + "\n";
fs.writeFileSync("supabase/migrations/20260905130000_nfe_duplicatas_e_parcelas_ar.sql", out);
console.log("migration escrita:", out.split("\n").length, "linhas");
