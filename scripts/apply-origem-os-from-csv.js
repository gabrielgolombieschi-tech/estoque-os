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

function parseCsv(content) {
  const lines = content.split(/\r?\n/).filter(Boolean);
  if (lines.length < 2) return [];
  const header = lines[0].split(';');
  return lines.slice(1).map((line) => {
    const cols = line.split(';');
    const row = {};
    header.forEach((h, i) => { row[h] = cols[i] ?? ''; });
    return row;
  });
}

const env = loadEnv('.env.local');
const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const csvPath = process.argv[2];
const APPLY = process.argv.includes('--apply');

if (!csvPath) {
  console.error('Uso: node scripts/apply-origem-os-from-csv.js <arquivo.csv> [--apply]');
  process.exit(1);
}

(async () => {
  const csv = fs.readFileSync(csvPath, 'utf8');
  const rows = parseCsv(csv);

  const itens = rows
    .map((r) => ({
      mov_id: Number(r.mov_id ?? 0),
      os_manual: Number(r.os_manual ?? 0),
    }))
    .filter((r) => Number.isFinite(r.mov_id) && r.mov_id > 0 && Number.isFinite(r.os_manual) && r.os_manual > 0);

  let ok = 0;
  let err = 0;
  const errors = [];

  if (APPLY) {
    for (const it of itens) {
      const { error } = await supabase.rpc('reclassificar_mov_saida_para_os', {
        p_mov_id: it.mov_id,
        p_origem_os_id: it.os_manual,
        p_realizado_por: 'auditoria_sistema',
      });
      if (error) {
        err += 1;
        errors.push({ mov_id: it.mov_id, os_manual: it.os_manual, error: error.message });
      } else {
        ok += 1;
      }
    }
  }

  const out = {
    csv: csvPath,
    apply: APPLY,
    rows_total_csv: rows.length,
    rows_com_os_manual: itens.length,
    reclassificacoes_ok: ok,
    reclassificacoes_erro: err,
    errors: errors.slice(0, 100),
  };

  fs.mkdirSync('tmp', { recursive: true });
  const file = `tmp/apply_origem_os_from_csv_${APPLY ? 'apply' : 'dryrun'}_${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
  fs.writeFileSync(file, JSON.stringify(out, null, 2));

  console.log(JSON.stringify(out, null, 2));
  console.log('report', file);
})();
