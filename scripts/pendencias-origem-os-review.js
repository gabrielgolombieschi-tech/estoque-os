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

(async () => {
  const [movs, itens] = await Promise.all([
    fetchAll('movimentacoes', 'id,tenant_id,empresa_id,item_id,tipo,quantidade,motivo,origem_os_id,data_movimentacao,created_at'),
    fetchAll('itens', 'id,codigo_interno,nome'),
  ]);

  const itemMap = new Map(itens.map((i) => [Number(i.id), i]));

  const corrigidos = new Set(
    movs
      .map((m) => {
        const mt = String(m.motivo ?? '').match(/CORRECAO RASTREIO OS: neutraliza mov #(\d+)/i);
        return mt ? Number(mt[1]) : null;
      })
      .filter((x) => Number.isFinite(x))
  );

  const pendentes = movs.filter((m) => {
    if (m.tipo !== 'saida' || m.origem_os_id != null) return false;
    if (corrigidos.has(Number(m.id))) return false;
    const motivo = String(m.motivo ?? '').toUpperCase();
    return motivo.includes('OS') || motivo.includes('BAIXA');
  });

  const histByItem = new Map();
  for (const m of movs) {
    if (m.origem_os_id == null) continue;
    const key = `${m.tenant_id}__${m.empresa_id}__${m.item_id}`;
    const arr = histByItem.get(key) ?? [];
    arr.push(m);
    histByItem.set(key, arr);
  }

  const rows = pendentes.map((p) => {
    const key = `${p.tenant_id}__${p.empresa_id}__${p.item_id}`;
    const hist = histByItem.get(key) ?? [];
    const osFreq = new Map();
    for (const h of hist) {
      const os = Number(h.origem_os_id);
      osFreq.set(os, (osFreq.get(os) ?? 0) + 1);
    }
    const sugestoes = Array.from(osFreq.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([os, freq]) => ({ os_id: os, freq }));

    const item = itemMap.get(Number(p.item_id));
    return {
      mov_id: p.id,
      tenant_id: p.tenant_id,
      empresa_id: p.empresa_id,
      item_id: Number(p.item_id),
      codigo: item?.codigo_interno ?? '',
      item: item?.nome ?? '',
      quantidade: Number(p.quantidade ?? 0),
      data_movimentacao: p.data_movimentacao,
      motivo: p.motivo,
      sugestoes_os: sugestoes,
    };
  });

  fs.mkdirSync('tmp', { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const jsonFile = `tmp/pendencias_origem_os_review_${ts}.json`;
  fs.writeFileSync(jsonFile, JSON.stringify({ total: rows.length, rows }, null, 2));

  const csvHeader = [
    'mov_id','tenant_id','empresa_id','item_id','codigo','item','quantidade','data_movimentacao','motivo',
    'sugestao1_os','sugestao1_freq','sugestao2_os','sugestao2_freq','sugestao3_os','sugestao3_freq'
  ];
  const csvLines = [csvHeader.join(';')];
  for (const r of rows) {
    const s = r.sugestoes_os;
    const vals = [
      r.mov_id, r.tenant_id, r.empresa_id, r.item_id, r.codigo, r.item, r.quantidade, r.data_movimentacao, String(r.motivo ?? '').replaceAll(';', ','),
      s[0]?.os_id ?? '', s[0]?.freq ?? '', s[1]?.os_id ?? '', s[1]?.freq ?? '', s[2]?.os_id ?? '', s[2]?.freq ?? ''
    ];
    csvLines.push(vals.join(';'));
  }
  const csvFile = `tmp/pendencias_origem_os_review_${ts}.csv`;
  fs.writeFileSync(csvFile, csvLines.join('\n'));

  console.log('TOTAL_PENDENTES', rows.length);
  console.log('JSON', jsonFile);
  console.log('CSV', csvFile);
})();
