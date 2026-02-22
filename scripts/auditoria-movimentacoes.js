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

const num = (v) => Number(v ?? 0) || 0;
const round3 = (v) => Math.round(v * 1000) / 1000;
const key3 = (a, b, c) => `${a}__${b}__${c}`;

async function fetchAll(table, columns, chunk = 1000) {
  let from = 0;
  const all = [];
  for (;;) {
    const { data, error } = await supabase.from(table).select(columns).range(from, from + chunk - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    all.push(...data);
    if (data.length < chunk) break;
    from += chunk;
  }
  return all;
}

(async () => {
  const [movs, estoque] = await Promise.all([
    fetchAll(
      'movimentacoes',
      'id,tenant_id,empresa_id,item_id,tipo,quantidade,origem_os_id,origem_nf_entrada_id,motivo,data_movimentacao,created_at'
    ),
    fetchAll('estoque', 'tenant_id,empresa_id,item_id,quantidade_atual'),
  ]);

  const deltaByItem = new Map();
  const saidaSemOrigemOsComMotivo = [];
  const ajustesCorrecaoMovIds = new Set();

  for (const m of movs) {
    let delta = 0;
    if (m.tipo === 'entrada' || m.tipo === 'ajuste') delta = num(m.quantidade);
    else if (m.tipo === 'saida') delta = -num(m.quantidade);
    else continue;

    const k = key3(m.tenant_id, m.empresa_id, m.item_id);
    deltaByItem.set(k, round3(num(deltaByItem.get(k)) + delta));

    const motivo = String(m.motivo ?? '').toUpperCase();
    const mCorr = String(m.motivo ?? '').match(/CORRECAO RASTREIO OS: neutraliza mov #(\d+)/i);
    if (mCorr) {
      const originalId = Number(mCorr[1]);
      if (Number.isFinite(originalId)) ajustesCorrecaoMovIds.add(originalId);
    }
    if (m.tipo === 'saida' && m.origem_os_id == null && (motivo.includes('OS ') || motivo.includes('BAIXA'))) {
      saidaSemOrigemOsComMotivo.push({
        id: m.id,
        tenant_id: m.tenant_id,
        empresa_id: m.empresa_id,
        item_id: m.item_id,
        quantidade: num(m.quantidade),
        motivo: m.motivo,
      });
    }
  }

  const estoqueByItem = new Map();
  const estoqueNegativo = [];
  for (const e of estoque) {
    const k = key3(e.tenant_id, e.empresa_id, e.item_id);
    const saldo = round3(num(e.quantidade_atual));
    estoqueByItem.set(k, saldo);
    if (saldo < 0) {
      estoqueNegativo.push({
        tenant_id: e.tenant_id,
        empresa_id: e.empresa_id,
        item_id: e.item_id,
        saldo,
      });
    }
  }

  const allKeys = new Set([...deltaByItem.keys(), ...estoqueByItem.keys()]);
  const divergenciasSaldo = [];
  for (const k of allKeys) {
    const calc = round3(num(deltaByItem.get(k)));
    const atual = round3(num(estoqueByItem.get(k)));
    if (Math.abs(calc - atual) > 0.001) {
      const [tenant_id, empresa_id, item_id] = k.split('__');
      divergenciasSaldo.push({
        tenant_id,
        empresa_id,
        item_id: Number(item_id),
        saldo_calc: calc,
        saldo_estoque: atual,
        diff: round3(atual - calc),
      });
    }
  }

  const entradasDiretoOsXml = movs.filter(
    (m) => m.tipo === 'entrada' && m.origem_os_id != null && m.origem_nf_entrada_id != null
  );

  const saidasSemOrigemOsPendentesReais = saidaSemOrigemOsComMotivo.filter(
    (r) => !ajustesCorrecaoMovIds.has(Number(r.id))
  );

  const resumo = {
    movimentos_total: movs.length,
    estoque_rows: estoque.length,
    divergencias_saldo: divergenciasSaldo.length,
    estoque_negativo: estoqueNegativo.length,
    saida_sem_origem_os_com_motivo_os: saidaSemOrigemOsComMotivo.length,
    saida_sem_origem_os_ja_reclassificadas: Array.from(ajustesCorrecaoMovIds).length,
    saida_sem_origem_os_pendentes_reais: saidasSemOrigemOsPendentesReais.length,
    entradas_direto_os_xml: entradasDiretoOsXml.length,
  };

  const out = {
    resumo,
    top_divergencias_saldo: divergenciasSaldo.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff)).slice(0, 50),
    top_estoque_negativo: estoqueNegativo.sort((a, b) => a.saldo - b.saldo).slice(0, 50),
    top_saida_sem_origem_os: saidaSemOrigemOsComMotivo.slice(0, 100),
    top_saida_sem_origem_os_pendentes_reais: saidasSemOrigemOsPendentesReais.slice(0, 100),
    amostra_entradas_direto_os_xml: entradasDiretoOsXml.slice(0, 50).map((m) => ({
      id: m.id,
      tenant_id: m.tenant_id,
      empresa_id: m.empresa_id,
      item_id: m.item_id,
      origem_os_id: m.origem_os_id,
      quantidade: num(m.quantidade),
      motivo: m.motivo,
      data_movimentacao: m.data_movimentacao,
    })),
  };

  fs.mkdirSync('tmp', { recursive: true });
  const file = `tmp/auditoria_movimentacoes_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(file, JSON.stringify(out, null, 2));

  console.log('Resumo:', resumo);
  console.log('Arquivo:', file);
})();
