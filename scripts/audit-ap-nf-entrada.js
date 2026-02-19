/* eslint-disable @typescript-eslint/no-require-imports */
const { createClient } = require("@supabase/supabase-js");
const fs = require("fs");
const path = require("path");

function loadEnvFile(fileName) {
  const file = path.join(process.cwd(), fileName);
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*=/.test(line)) continue;
    const idx = line.indexOf("=");
    const key = line.slice(0, idx).trim();
    if (process.env[key]) continue;
    const value = line.slice(idx + 1).trim().replace(/^"|"$/g, "");
    process.env[key] = value;
  }
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value.trim();
}

function parseTargets() {
  const json = process.env.AP_AUDIT_TARGETS;
  if (json && json.trim()) {
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error("AP_AUDIT_TARGETS must be a non-empty JSON array");
    }
    return parsed.map((t) => ({
      tenant_id: String(t.tenant_id ?? "").trim(),
      empresa_id: String(t.empresa_id ?? "").trim(),
    }));
  }

  const tenant = String(process.env.AP_AUDIT_TENANT_ID ?? "").trim();
  const empresa = String(process.env.AP_AUDIT_EMPRESA_ID ?? "").trim();
  if (!tenant || !empresa) {
    throw new Error("Provide AP_AUDIT_TARGETS or AP_AUDIT_TENANT_ID + AP_AUDIT_EMPRESA_ID");
  }
  return [{ tenant_id: tenant, empresa_id: empresa }];
}

function dateOnly(d) {
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

async function main() {
  loadEnvFile(".env");
  loadEnvFile(".env.local");

  const url = requiredEnv("NEXT_PUBLIC_SUPABASE_URL");
  const service = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const client = createClient(url, service, { auth: { persistSession: false } });

  const targets = parseTargets();
  const daysBack = Number(process.env.AP_AUDIT_DAYS_BACK ?? "90");
  const end = dateOnly(new Date());
  const startDate = new Date();
  startDate.setUTCDate(startDate.getUTCDate() - (Number.isFinite(daysBack) && daysBack > 0 ? daysBack : 90));
  const start = dateOnly(startDate);

  let totalIssues = 0;

  for (const target of targets) {
    if (!target.tenant_id || !target.empresa_id) {
      throw new Error(`Invalid audit target: ${JSON.stringify(target)}`);
    }

    const { data, error } = await client.rpc("fn_auditar_ap_por_nf_entrada_range", {
      p_tenant_id: target.tenant_id,
      p_empresa_id: target.empresa_id,
      p_comp_ini: start,
      p_comp_fim: end,
    });
    if (error) throw new Error(error.message);

    const rows = data || [];
    const issues = rows.filter((r) => Boolean(r.has_issue));
    totalIssues += issues.length;

    const byCode = {};
    for (const row of issues) {
      for (const code of String(row.issue_codes || "").split(",").filter(Boolean)) {
        byCode[code] = (byCode[code] || 0) + 1;
      }
    }

    console.log(`[AP-AUDIT] tenant=${target.tenant_id} empresa=${target.empresa_id} range=${start}..${end}`);
    console.log(`[AP-AUDIT] docs=${rows.length} issues=${issues.length} by_code=${JSON.stringify(byCode)}`);
    if (issues.length) {
      console.log("[AP-AUDIT] sample_issues:", JSON.stringify(issues.slice(0, 10)));
    }
  }

  if (totalIssues > 0) {
    process.exitCode = 2;
    console.error(`[AP-AUDIT] FAILED: ${totalIssues} issue(s) found.`);
    return;
  }

  console.log("[AP-AUDIT] OK: no issues found.");
}

main().catch((err) => {
  console.error("[AP-AUDIT] ERROR:", err?.message || err);
  process.exitCode = 1;
});
