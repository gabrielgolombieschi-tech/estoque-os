# 📋 MUDANÇAS RÁPIDAS: LINE-BY-LINE

## 🔧 MIGRATION SQL (NEW FILE)

**File**: `supabase/migrations/20260218_fix_hh_lancamentos_validation.sql`

**Key Changes**:
```sql
❌ REMOVED: validate_apontamento_colaborador_contrato() reference to colaborador_cliente_funcao
✅ ADDED:   Same function now references colaborador_funcao_hh

❌ REMOVED: Validation checking empresa_id column
✅ ADDED:   New function validate_hh_lancamento() with correct logic

✅ ADDED:   Trigger trigger_validate_hh_lancamento on hh_lancamentos
✅ ADDED:   Automatic data sync from old table (if exists)
```

**Critical Functions**:

### Function 1: validate_apontamento_colaborador_contrato()
```sql
-- BEFORE:
FROM public.colaborador_cliente_funcao  ← WRONG TABLE

-- AFTER:
FROM public.colaborador_funcao_hh       ← CORRECT TABLE
```

### Function 2: validate_hh_lancamento() (NEW)
```sql
-- NEW FUNCTION (didn't exist before)
CREATE FUNCTION validate_hh_lancamento() RETURNS TRIGGER
  Validates:
  1. Service HH exists + active (cliente_hh_servicos)
  2. Vínculo exists + active (colaborador_funcao_hh)
  WHERE tenant_id, cliente_id, colaborador_id, servico_hh_id = ?
  
  NO empresa_id check ✅
  NO relatório check ✅
```

---

## 📝 FRONTEND UPDATES (RelatorioHHSection.tsx)

**File**: `app/os/[id]/components/RelatorioHHSection.tsx`

### Location 1 - Line 554 (loadColaboradores function)

```diff
  const { data: vinculosData, error: vinculosErr } = await applyTenant(
    supabase
-     .from("colaborador_cliente_funcao")
+     .from("colaborador_funcao_hh")
-     .select("colaborador_id,hh_servico_id,ativo,cliente_id")
+     .select("colaborador_id,servico_hh_id,ativo,cliente_id")
      .eq("cliente_id", clienteId)
      .eq("ativo", true)
      .order("colaborador_id", { ascending: true }),
    ctx.tenant
  );
```

**Changed**:
- Table name: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Column name: `hh_servico_id` → `servico_hh_id`

---

### Location 2 - Line 647 (loadEspecialidadesParaColaborador function)

```diff
  const { data, error } = await applyTenant(
    supabase
-     .from("colaborador_cliente_funcao")
+     .from("colaborador_funcao_hh")
-     .select("hh_servico_id,ativo")
+     .select("servico_hh_id,ativo")
      .eq("colaborador_id", colaboradorId)
      .eq("cliente_id", clienteId)
      .eq("ativo", true),
    ctx.tenant
  );
```

**Changed**:
- Table name: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Column name: `hh_servico_id` → `servico_hh_id`

---

### Location 3 - Line 1140 (Validation check in salvarLancamento)

```diff
  // 1. Verificar se o vínculo existe na tabela colaborador_funcao_hh
  const { data: vinculoExistente, error: checkVinculoErr } = await applyTenant(
    supabase
-     .from("colaborador_cliente_funcao")
+     .from("colaborador_funcao_hh")
      .select("id,ativo")
      .eq("tenant_id", ctx.tenant)
      .eq("cliente_id", clienteIdContext)
      .eq("colaborador_id", lancamentoForm.colaborador_id)
-     .eq("hh_servico_id", hhServicoId)
+     .eq("servico_hh_id", hhServicoId)
      .maybeSingle(),
    ctx.tenant
  );
```

**Changed**:
- Table name: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Column name: `hh_servico_id` → `servico_hh_id`

---

### Location 4 - Line 1161 (Create vínculo auto)

```diff
  // 2. Se não existe, criar o vínculo
  if (!vinculoExistente) {
    console.warn("[salvarLancamento] Vínculo não encontrado, criando automaticamente...");
    const { error: criarVinculoErr } = await applyTenant(
-     supabase.from("colaborador_cliente_funcao").insert({
+     supabase.from("colaborador_funcao_hh").insert({
        tenant_id: ctx.tenant,
        cliente_id: clienteIdContext,
        colaborador_id: lancamentoForm.colaborador_id,
-       hh_servico_id: hhServicoId,
+       servico_hh_id: hhServicoId,
        ativo: true,
      }),
      ctx.tenant
    );
```

**Changed**:
- Table name: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Column name: `hh_servico_id` → `servico_hh_id`

---

### Location 5 - Line 1187 (Activate vínculo)

```diff
  } else if (vinculoExistente && !vinculoExistente.ativo) {
    // 3. Se existe mas está inativo, ativar
    console.warn("[salvarLancamento] Vínculo inativo, ativando...");
    const { error: ativarErr } = await applyTenant(
      supabase
-       .from("colaborador_cliente_funcao")
+       .from("colaborador_funcao_hh")
        .update({ ativo: true })
        .eq("tenant_id", ctx.tenant)
        .eq("cliente_id", clienteIdContext)
        .eq("colaborador_id", lancamentoForm.colaborador_id)
-       .eq("hh_servico_id", hhServicoId),
+       .eq("servico_hh_id", hhServicoId),
      ctx.tenant
    );
```

**Changed**:
- Table name: `colaborador_cliente_funcao` → `colaborador_funcao_hh`
- Column name: `hh_servico_id` → `servico_hh_id`

---

## 📊 SUMMARY TABLE

| Location | Type | Before | After | Reason |
|----------|------|--------|-------|--------|
| Line 554 | loadColaboradores | `colaborador_cliente_funcao` | `colaborador_funcao_hh` | Use real table name |
| Line 554 | loadColaboradores | `hh_servico_id` | `servico_hh_id` | Use real column name |
| Line 647 | loadEspecialidades | `colaborador_cliente_funcao` | `colaborador_funcao_hh` | Use real table name |
| Line 647 | loadEspecialidades | `hh_servico_id` | `servico_hh_id` | Use real column name |
| Line 1140 | Validation | `colaborador_cliente_funcao` | `colaborador_funcao_hh` | Use real table name |
| Line 1140 | Validation | `hh_servico_id` | `servico_hh_id` | Use real column name |
| Line 1161 | Insert vinculo | `colaborador_cliente_funcao` | `colaborador_funcao_hh` | Use real table name |
| Line 1161 | Insert vinculo | `hh_servico_id` | `servico_hh_id` | Use real column name |
| Line 1187 | Update vinculo | `colaborador_cliente_funcao` | `colaborador_funcao_hh` | Use real table name |
| Line 1187 | Update vinculo | `hh_servico_id` | `servico_hh_id` | Use real column name |

---

## ✨ TOTAL CHANGES

| Type | Count | Files |
|------|-------|-------|
| **New Migration** | 1 | `20260218_fix_hh_lancamentos_validation.sql` |
| **Frontend Updates** | 5 locations | `RelatorioHHSection.tsx` |
| **Documentation** | 3 files | `.md` files |
| **Functions Created** | 1 | `validate_hh_lancamento()` |
| **Triggers Created** | 1 | `trigger_validate_hh_lancamento` |
| **Total Lines Changed** | ~200 | SQL + Frontend |

---

## 🚀 DEPLOY STEPS

### Step 1: Run Migration
```bash
npm run db:migrate -- --from 20260218_fix_hh_lancamentos_validation.sql
```

### Step 2: No code changes needed for frontend
(Already updated in this PR)

### Step 3: Test
```
See HH_LANCAMENTOS_FIX_FINAL.md for test cases
```

---

## ✅ VERIFICATION

After running migration, verify:

```sql
-- Check functions exist
SELECT proname FROM pg_proc 
WHERE proname IN ('validate_apontamento_colaborador_contrato', 'validate_hh_lancamento');

-- Check triggers exist
SELECT tgname FROM pg_trigger 
WHERE tgname = 'trigger_validate_hh_lancamento';

-- Result: Should show all 3
```

---

## 🎯 WHAT GETS FIXED

- ✅ "Serviço HH não está vinculado" error (when vínculo truly missing)
- ✅ "column empresa_id does not exist" (no more references)
- ✅ HH lançamento saves without relatório dependency
- ✅ Validation uses correct tables and columns
- ✅ Error messages are clear and accurate

---

## ⚠️ NO BREAKING CHANGES

- ✅ RLS policies unchanged
- ✅ hh_lancamentos table structure unchanged
- ✅ Existing data intact
- ✅ Backward compatible
- ✅ Can rollback if needed

