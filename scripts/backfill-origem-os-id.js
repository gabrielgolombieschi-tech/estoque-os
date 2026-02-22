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

const APPLY = process.argv.includes('--apply');
const WINDOW_MS = 5 * 60 * 1000;
const EPS = 0.0001;

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

function parseOsFromMotivo(motivo) {
  const m = String(motivo ?? '').match(/\bOS\s*([0-9]+)\b/i);
  if (!m) return null;
  const v = Number(m[1]);
  return Number.isFinite(v) ? v : null;
}

(async () => {
  const [movs, osItens] = await Promise.all([
    fetchAll(
      'movimentacoes',
      'id,tenant_id,empresa_id,item_id,tipo,quantidade,motivo,origem_os_id,data_movimentacao,created_at'
    ),
    fetchAll('os_itens', 'id,tenant_id,os_id,item_id,quantidade,baixa_estoque,criado_em'),
  ]);

  const jaReclassificadas = new Set(
    movs
      .map((m) => {
        const mt = String(m.motivo ?? '').match(/CORRECAO RASTREIO OS: neutraliza mov #(\d+)/i);
        if (!mt) return null;
        const id = Number(mt[1]);
        return Number.isFinite(id) ? id : null;
      })
      .filter((v) => v !== null)
  );

  const saidasPendentes = movs.filter((m) => {
    if (m.tipo !== 'saida' || m.origem_os_id != null) return false;
    if (jaReclassificadas.has(Number(m.id))) return false;
    const motivo = String(m.motivo ?? '').toUpperCase();
    return motivo.includes('OS') || motivo.includes('BAIXA');
  });

  const osIdx = new Map();
  for (const oi of osItens) {
    if (!oi.baixa_estoque) continue;
    const k = `${oi.tenant_id}__${oi.item_id}`;
    const arr = osIdx.get(k) ?? [];
    arr.push(oi);
    osIdx.set(k, arr);
  }

  for (const arr of osIdx.values()) {
    arr.sort((a, b) => new Date(a.criado_em).getTime() - new Date(b.criado_em).getTime());
  }

  const byRegex = [];
  const byTimeUnique = [];
  const byNearSaidaComOs = [];
  const ambiguous = [];
  const unresolved = [];

  for (const m of saidasPendentes) {
    const row = {
      id: m.id,
      tenant_id: m.tenant_id,
      empresa_id: m.empresa_id,
      item_id: m.item_id,
      quantidade: Number(m.quantidade ?? 0),
      motivo: m.motivo,
      data_movimentacao: m.data_movimentacao,
      resolved_os_id: null,
      metodo: null,
    };

    const osFromMotivo = parseOsFromMotivo(m.motivo);
    if (osFromMotivo) {
      row.resolved_os_id = osFromMotivo;
      row.metodo = 'regex_motivo';
      byRegex.push(row);
      continue;
    }

    const key = `${m.tenant_id}__${m.item_id}`;
    const cands = osIdx.get(key) ?? [];
    const t0 = new Date(m.data_movimentacao ?? m.created_at ?? 0).getTime();
    const qtd = Number(m.quantidade ?? 0);

    const near = cands.filter((oi) => {
      const t1 = new Date(oi.criado_em ?? 0).getTime();
      const dt = Math.abs(t1 - t0);
      const sameQtd = Math.abs(Number(oi.quantidade ?? 0) - qtd) <= EPS;
      return sameQtd && dt <= WINDOW_MS;
    });

    const osSet = Array.from(new Set(near.map((x) => Number(x.os_id)).filter((n) => Number.isFinite(n))));

    if (osSet.length === 1) {
      row.resolved_os_id = osSet[0];
      row.metodo = 'janela_tempo_quantidade_unica';
      byTimeUnique.push(row);
    } else if (osSet.length > 1) {
      row.metodo = 'ambiguo';
      row.os_candidates = osSet;
      ambiguous.push(row);
    } else {
      row.metodo = 'nao_resolvido';
      unresolved.push(row);
    }
  }

  // Segunda heuristica: procurar "movimentacao irma" ja com origem_os_id
  // (mesmo tenant/empresa/item/quantidade e horario proximo).
  const saidasComOs = movs.filter((m) => m.tipo === 'saida' && m.origem_os_id != null);
  const unresolvedStep1 = [...unresolved];
  unresolved.length = 0;

  for (const u of unresolvedStep1) {
    const t0 = new Date(u.data_movimentacao ?? 0).getTime();
    const near = saidasComOs.filter((m) => {
      if (m.tenant_id !== u.tenant_id || m.empresa_id !== u.empresa_id) return false;
      if (Number(m.item_id) !== Number(u.item_id)) return false;
      if (Math.abs(Number(m.quantidade ?? 0) - Number(u.quantidade ?? 0)) > EPS) return false;
      const t1 = new Date(m.data_movimentacao ?? m.created_at ?? 0).getTime();
      return Math.abs(t1 - t0) <= WINDOW_MS;
    });
    const osSet = Array.from(new Set(near.map((x) => Number(x.origem_os_id)).filter((n) => Number.isFinite(n))));
    if (osSet.length === 1) {
      byNearSaidaComOs.push({
        ...u,
        resolved_os_id: osSet[0],
        metodo: 'near_saida_com_os_unica',
      });
    } else if (osSet.length > 1) {
      ambiguous.push({
        ...u,
        metodo: 'ambiguo_near_saida_com_os',
        os_candidates: osSet,
      });
    } else {
      unresolved.push(u);
    }
  }

  const updates = [...byRegex, ...byTimeUnique, ...byNearSaidaComOs];
  const updateErrors = [];
  const updateSuccess = [];

  if (APPLY && updates.length > 0) {
    for (const u of updates) {
      const { data, error } = await supabase.rpc('reclassificar_mov_saida_para_os', {
        p_mov_id: u.id,
        p_origem_os_id: u.resolved_os_id,
        p_realizado_por: 'auditoria_sistema'
      });
      if (error) {
        updateErrors.push({ id: u.id, os_id: u.resolved_os_id, error: error.message });
      } else {
        updateSuccess.push({ id: u.id, os_id: u.resolved_os_id, data });
      }
    }
  }

  const report = {
    apply: APPLY,
    total_saidas_pendentes: saidasPendentes.length,
    resolvidos_regex: byRegex.length,
    resolvidos_tempo_unico: byTimeUnique.length,
    resolvidos_por_saida_irma: byNearSaidaComOs.length,
    ambiguos: ambiguous.length,
    nao_resolvidos: unresolved.length,
    tentativas_reclassificacao: APPLY ? updates.length : 0,
    reclassificacoes_ok: updateSuccess.length,
    reclassificacoes_erro: updateErrors.length,
    amostra_resolvidos: updates.slice(0, 120),
    amostra_erros: updateErrors.slice(0, 80),
    amostra_ambiguos: ambiguous.slice(0, 80),
    amostra_nao_resolvidos: unresolved.slice(0, 80),
  };

  fs.mkdirSync('tmp', { recursive: true });
  const f = `tmp/backfill_origem_os_id_${APPLY ? 'apply' : 'dryrun'}_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(f, JSON.stringify(report, null, 2));
  console.log('REPORT', f);
  console.log(JSON.stringify({
    total_saidas_pendentes: report.total_saidas_pendentes,
    resolvidos_regex: report.resolvidos_regex,
    resolvidos_tempo_unico: report.resolvidos_tempo_unico,
    ambiguos: report.ambiguos,
    nao_resolvidos: report.nao_resolvidos,
    tentativas_reclassificacao: report.tentativas_reclassificacao,
    reclassificacoes_ok: report.reclassificacoes_ok,
    reclassificacoes_erro: report.reclassificacoes_erro,
  }, null, 2));
})();
