/**
 * Leitura das NFS-e importadas (XML em f.documento_fiscal_xml) por tomador:
 * quantas com ISS retido (tpRetISSQN 2), quantas sem, e as retencoes federais
 * observadas. Somente leitura: NAO grava clientes.iss_retido nem retem_*.
 *
 *   node scripts/nfse-retencoes-por-tomador.mjs [2026-07-01] [2026-08-31]
 */
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const raiz = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const inicio = process.argv[2] ?? "2026-07-01";
const fim = process.argv[3] ?? "2026-08-31";
if (!/^\d{4}-\d{2}-\d{2}$/.test(inicio) || !/^\d{4}-\d{2}-\d{2}$/.test(fim)) {
  console.error("Datas no formato AAAA-MM-DD.");
  process.exit(1);
}
const sql = `set role postgres;
select c.id as cliente_id, left(coalesce(c.razao_social, c.nome, ''), 40) as tomador, c.cidade,
       c.iss_retido as cadastro_iss_retido, c.retem_pcc, c.retem_irrf, c.retem_inss,
       count(*) as notas,
       sum(case when substring(x.xml_raw from '<tpRetISSQN>([0-9])') = '2' then 1 else 0 end) as iss_retido,
       sum(case when substring(x.xml_raw from '<tpRetISSQN>([0-9])') = '1' then 1 else 0 end) as iss_nao_retido,
       sum(case when x.xml_raw like '%<vRetIRRF>%' then 1 else 0 end) as irrf,
       sum(case when x.xml_raw like '%<vRetCSLL>%' then 1 else 0 end) as pcc,
       sum(case when x.xml_raw like '%<vRetCP>%' then 1 else 0 end) as inss,
       string_agg(distinct substring(x.xml_raw from '<cTribNac>([0-9]+)'), ',') as ctrib_nac,
       string_agg(distinct substring(x.xml_raw from '<cLocPrestacao>([0-9]+)'), ',') as local_prestacao
from f.documento_fiscal d
join f.documento_fiscal_xml x on x.documento_fiscal_id = d.id and x.deleted_at is null
left join public.clientes c on c.id = d.cliente_id
where d.modelo = 'NFSE' and d.operacao = 'SAIDA' and d.deleted_at is null
  and d.emissao_date between '${inicio}' and '${fim}'
group by 1, 2, 3, 4, 5, 6, 7
order by notas desc, 2;`;
const resultado = spawnSync(process.execPath, [path.join(raiz, "scripts", "db-query.js"), sql], { encoding: "utf8" });
process.stdout.write(resultado.stdout ?? "");
if (resultado.status !== 0) {
  process.stderr.write(resultado.stderr ?? "");
  process.exit(resultado.status ?? 1);
}
console.log("\nSugestao por tomador (nao gravada): iss_retido = true quando todas as notas do periodo tiveram tpRetISSQN 2; false quando todas tiveram 1; misto = decidir por servico.");
