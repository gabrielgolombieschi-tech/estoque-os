# 🔧 Fix: hh_tipo_id Hardcoded Bug - COMPLETE PATCH

## 📋 Issue

**Bug**: When saving an HH (labor hours) entry, `hh_tipo_id` was being sent as a hardcoded value (likely 1) from a generic "tipo de hora" lookup, instead of using the actual `cliente_hh_servicos.id` selected by the user.

**Impact**: 
- Backend validates `hh_tipo_id` against `cliente_hh_servicos` table
- ID 1 doesn't exist for most clients (valid IDs are: 3,4,5,6,7,8,9,10,11,12,82)
- Insert fails with "Serviço HH 1 não existe" error

**Root Cause**: 
- Code was calling RPC `get_hh_tipo_id_for_tenant()` to fetch a "default tipo de hora"
- This returned a generic type (e.g., 1) instead of the selected service ID
- Selected service ID was already captured in `lancamentoForm.hh_servico_id` but ignored

## ✅ Solution Applied

### File: `app/os/[id]/components/RelatorioHHSection.tsx`

#### Change 1: Use Selected Service ID as hh_tipo_id (lines 1225-1233)

**Before** (WRONG):
```typescript
// Resolver hh_tipo_id padrão para o tenant usando RPC
let hhTipoId: number | null = null;
try {
  const { data: tipoIdData, error: tipoIdErr } = await supabase.rpc(
    "get_hh_tipo_id_for_tenant",
    { p_tenant_id: ctx.tenant }
  );
  if (!tipoIdErr && tipoIdData) {
    hhTipoId = Number(tipoIdData);  // ← WRONG: Generic tipo_hora, not the selected service!
  }
} catch (e) {
  console.warn("[salvarLancamento] Erro ao resolver hh_tipo_id via RPC:", e);
}

if (!hhTipoId || !Number.isFinite(hhTipoId)) {
  setErr(
    "Nenhum tipo de hora configurado para este tenant. " +
    "Verifique se tipos_horas existe e possui registro ativo."
  );
  setLancamentoBusy(false);
  return false;
}
```

**After** (CORRECT):
```typescript
// hh_tipo_id DEVE SER o ID do serviço HH selecionado, não um tipo de hora genérico
// hhServicoId já foi validado acima, é o ID real do cliente_hh_servicos
const hhTipoId = hhServicoId;

console.warn("[salvarLancamento] hh_tipo_id resolvido:", {
  servicoId: hhServicoId,
  tipoId: hhTipoId,
  isFinite: Number.isFinite(hhTipoId),
});
```

#### Change 2: Enhanced Payload Logging (lines 1263-1272)

**Before**:
```typescript
console.warn("[salvarLancamento] PAYLOAD FINAL A INSERIR/ATUALIZAR:", basePayload);
```

**After**:
```typescript
console.warn("[HH_SAVE_PAYLOAD] Payload final a ser enviado:", {
  ...basePayload,
  // Highlight critical field
  hh_tipo_id_IMPORTANTE: `${hhTipoId} (deve ser ID real do serviço HH, NÃO 1!)`,
});
```

## 🔍 Verification Steps

### 1. **Check Console Logs**

When saving an HH entry, look for:

```javascript
[HH_SAVE_PAYLOAD] Payload final a ser enviado: {
  tenant_id: "uuid...",
  empresa_id: "uuid...",
  os_id: 123,
  colaborador_id: "uuid...",
  hh_tipo_id: 3,  // ✅ CORRECT: Real service ID (not 1!)
  hh_tipo_id_IMPORTANTE: "3 (deve ser ID real do serviço HH, NÃO 1!)",
  data: "2025-01-15",
  hora_entrada: "07:30",
  hora_saida: "17:00",
  percentual_aplicado: 0,
  observacao: null,
  valor_hora: 150.00,
}
```

### 2. **Test Scenarios**

**Scenario A**: Create new HH entry
1. Open OS detail → "Lançar Horas"
2. Select Colaborador
3. Dropdown shows services (should NOT include ID 1 if not valid for client)
4. Select service ID 3 (or any valid ID > 1)
5. Check console log shows `hh_tipo_id: 3` ✅

**Scenario B**: Edit existing HH entry
1. Click "Editar" on existing entry
2. Verify dropdown pre-loads with correct service ID (not 1)
3. Change selection to different service
4. Check log shows new service ID in payload

**Scenario C**: Backend validation
1. Save entry
2. Backend should accept `hh_tipo_id: 3` (exists in `cliente_hh_servicos`)
3. Entry saves successfully ✅

## 📊 Data Flow

```
User selects service → lancamentoForm.hh_servico_id = "3"
                   ↓
Validate numeric   → hhServicoId = Number("3") = 3
                   ↓
Check exists       → Query cliente_hh_servicos WHERE id=3 ✓
                   ↓
Load preços        → Query precos based on id=3 ✓
                   ↓
Load vínculo       → Validate colaborador has vínculo with service 3 ✓
                   ↓
Build payload      → hh_tipo_id: 3  (NOT 1!)
                   ↓
Log payload        → console.warn("[HH_SAVE_PAYLOAD]", {hh_tipo_id: 3, ...})
                   ↓
Insert/Update      → INSERT INTO hh_lancamentos (hh_tipo_id=3, ...) ✓
```

## 🎯 Key Points

✅ **Before**: `hh_tipo_id` was hardcoded/default from RPC (wrong generic type)
✅ **After**: `hh_tipo_id` is the actual `cliente_hh_servicos.id` selected by user
✅ **Validation**: Service ID is already validated before reaching this point
✅ **Type Safety**: `hhServicoId` is always numeric and validated
✅ **Logging**: Clear console.warn shows exact payload being sent
✅ **No Breaking Changes**: Field name and structure remain the same

## 🚀 Deployment

1. Deploy `RelatorioHHSection.tsx` changes
2. Check browser console for "[HH_SAVE_PAYLOAD]" log
3. Verify `hh_tipo_id` matches selected service ID (never 1 if not valid)
4. Monitor backend logs for any validation issues
5. Expected: All HH entries save successfully with correct service IDs

## 📝 Related Code

**State Management** (line 440):
```typescript
const [lancamentoForm, setLancamentoForm] = useState({
  data: new Date().toISOString().slice(0, 10),
  colaborador_id: "",
  hh_servico_id: "",  // ← Stores selected service ID
  observacao: "",
});
```

**Dropdown Binding** (line 1735):
```typescript
<select
  value={lancamentoForm.hh_servico_id}
  onChange={(e) => {
    const servicoId = e.target.value;
    setLancamentoForm((prev) => ({ ...prev, hh_servico_id: servicoId }));
    // ... load preços
  }}
>
  {especialidadesOptions.map((esp) => (
    <option key={esp.id} value={esp.id}>  // ← Real service ID
      {esp.descricao ?? esp.id}
    </option>
  ))}
</select>
```

**Payload Assembly** (line 1263):
```typescript
const basePayload = {
  // ... other fields
  hh_tipo_id: hhTipoId,  // ← Now equals hhServicoId (3, 4, 5, etc)
  // ... other fields
};
```

---

**Status**: ✅ Complete  
**Last Updated**: 2025-01-15  
**Version**: 1.0 - Production Ready
