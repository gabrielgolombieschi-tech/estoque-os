const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

function loadEnv(path) {
  const raw = fs.readFileSync(path, 'utf8');
  return Object.fromEntries(
    raw
      .split(/\r?\n/)
      .filter((line) => line && !line.trim().startsWith('#') && line.includes('='))
      .map((line) => {
        const idx = line.indexOf('=');
        return [line.slice(0, idx), line.slice(idx + 1)];
      })
  );
}

const env = loadEnv('.env.local');
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function fetchAll(table, columns, chunk = 1000) {
  let from = 0;
  const out = [];
  for (;;) {
    const { data, error } = await supabase.from(table).select(columns).range(from, from + chunk - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    out.push(...data);
    if (data.length < chunk) break;
    from += chunk;
  }
  return out;
}

const n = (v) => Number(v ?? 0) || 0;

(async () => {
  const [estoque, movs, itens] = await Promise.all([
    fetchAll('estoque', 'tenant_id,empresa_id,item_id,quantidade_atual'),
    fetchAll('movimentacoes', 'tenant_id,empresa_id,item_id,tipo,quantidade,origem_os_id,origem_nf_entrada_id,motivo'),
    fetchAll('itens', 'id,codigo_interno,nome'),
  ]);

  const itemMap = new Map(itens.map((i) => [Number(i.id), i]));
  const byItem = new Map();
  for (const m of movs) {
    const k = `${m.tenant_id}__${m.empresa_id}__${m.item_id}`;
    const cur = byItem.get(k) ?? {
      ent: 0,
      sai: 0,
      adj: 0,
      ent_os_nf: 0,
      sai_os_sem_origem: 0,
      sai_com_origem: 0,
      qtd_os_refs: new Set(),
    };
    if (m.tipo === 'entrada') cur.ent += n(m.quantidade);
    if (m.tipo === 'saida') cur.sai += n(m.quantidade);
    if (m.tipo === 'ajuste') cur.adj += n(m.quantidade);
    if (m.tipo === 'entrada' && m.origem_os_id != null && m.origem_nf_entrada_id != null) cur.ent_os_nf += n(m.quantidade);
    if (m.tipo === 'saida' && m.origem_os_id == null && /OS|BAIXA/i.test(String(m.motivo ?? ''))) cur.sai_os_sem_origem += n(m.quantidade);
    if (m.tipo === 'saida' && m.origem_os_id != null) {
      cur.sai_com_origem += n(m.quantidade);
      cur.qtd_os_refs.add(Number(m.origem_os_id));
    }
    byItem.set(k, cur);
  }

  const neg = [];
  for (const e of estoque) {
    const saldo = n(e.quantidade_atual);
    if (saldo >= 0) continue;
    const k = `${e.tenant_id}__${e.empresa_id}__${e.item_id}`;
    const c = byItem.get(k) ?? { ent: 0, sai: 0, adj: 0, ent_os_nf: 0, sai_os_sem_origem: 0, sai_com_origem: 0, qtd_os_refs: new Set() };
    const i = itemMap.get(Number(e.item_id));
    neg.push({
      tenant_id: e.tenant_id,
      empresa_id: e.empresa_id,
      item_id: Number(e.item_id),
      codigo: i?.codigo_interno ?? '',
      item: i?.nome ?? '',
      saldo_atual: saldo,
      sugestao_ajuste_para_zero: Math.abs(saldo),
      ent_total: c.ent,
      sai_total: c.sai,
      ajuste_total: c.adj,
      ent_os_nf: c.ent_os_nf,
      sai_os_sem_origem: c.sai_os_sem_origem,
      sai_com_origem: c.sai_com_origem,
      qtd_os_refs: c.qtd_os_refs.size,
      flag_dupla_saida_prob: c.sai_total > 0 && c.ent_total > 0 && Math.abs(c.sai_total - c.ent_total * 2) < 0.001,
    });
  }

  neg.sort((a, b) => a.saldo_atual - b.saldo_atual);

  fs.mkdirSync('tmp', { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const jsonFile = `tmp/negativos_review_${ts}.json`;
  fs.writeFileSync(jsonFile, JSON.stringify({ total: neg.length, rows: neg }, null, 2));

  const csvHead = [
    'tenant_id','empresa_id','item_id','codigo','item','saldo_atual','sugestao_ajuste_para_zero',
    'ent_total','sai_total','ajuste_total','ent_os_nf','sai_os_sem_origem','sai_com_origem','qtd_os_refs','flag_dupla_saida_prob'
  ];
  const lines = [csvHead.join(';')];
  for (const r of neg) {
    lines.push([
      r.tenant_id,r.empresa_id,r.item_id,r.codigo,String(r.item).replaceAll(';',','),r.saldo_atual,r.sugestao_ajuste_para_zero,
      r.ent_total,r.sai_total,r.ajuste_total,r.ent_os_nf,r.sai_os_sem_origem,r.sai_com_origem,r.qtd_os_refs,r.flag_dupla_saida_prob
    ].join(';'));
  }
  const csvFile = `tmp/negativos_review_${ts}.csv`;
  fs.writeFileSync(csvFile, lines.join('\n'));

  const dupla = neg.filter((r) => r.flag_dupla_saida_prob).length;
  console.log(JSON.stringify({ total_negativos: neg.length, suspeita_dupla_saida: dupla, json: jsonFile, csv: csvFile }, null, 2));
})();
