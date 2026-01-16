# Resolução: hh_tipos usando tipos_horas

## 📋 Problema

- Tabela `hh_tipos` **não existe**
- Existe tabela `tipos_horas` (UUID, com tenant_id)
- Campo `hh_lancamentos.hh_tipo_id` é **BIGINT** (incompatível com UUID de tipos_horas)

## ✅ Solução Implementada

Criada **migration** que:

1. **Cria tabela de mapeamento**: `hh_tipos_mapping`
   - Maps UUID (tipos_horas) → BIGINT (hh_tipo_id)
   - Scoped por tenant_id
   - Constraint UNIQUE por tenant

2. **Remove FK inválida**: `hh_lancamentos.hh_tipo_id` → ~~hh_tabela_precos~~ (deletada)

3. **Adiciona nova FK**: `hh_lancamentos.hh_tipo_id` → `hh_tipos_mapping.hh_tipo_id`

4. **Cria função RPC**: `get_hh_tipo_id_for_tenant(tenant_id)`
   - Retorna primeiro hh_tipo_id ativo para o tenant

## 🚀 Passos de Execução

### 1. Aplicar Migration
```bash
npm run db:migrate
```

Isso vai:
- ✅ Criar tabela `hh_tipos_mapping`
- ✅ Criar função RPC `get_hh_tipo_id_for_tenant`
- ✅ Atualizar constraints em `hh_lancamentos`
- ✅ Inserir mapeamento padrão (primeiro tipos_horas ativo por tenant)

### 2. Verificar Setup no Banco
```sql
-- Verificar tabela de mapeamento foi criada
SELECT * FROM public.hh_tipos_mapping;

-- Verificar função RPC
SELECT public.get_hh_tipo_id_for_tenant('SEU_TENANT_ID'::uuid);

-- Verificar constraint FK
\d public.hh_lancamentos
```

### 3. Verificar tipos_horas existentes
```sql
SELECT id, tenant_id, codigo, descricao, fator, ativo
FROM public.tipos_horas
WHERE ativo = true
LIMIT 5;
```

Se nenhum resultado, você precisa criar tipos:
```sql
INSERT INTO public.tipos_horas (tenant_id, codigo, descricao, fator)
VALUES (
  '123e4567-e89b-12d3-a456-426614174000'::uuid,
  'TIPO_PADRAO',
  'Tipo de Hora Padrão',
  1.0
);
```

## 🔧 Código Atualizado

### RelatorioHHSection.tsx - salvarLancamento()

**Antes:**
```tsx
hh_tipo_id: 1, // Hardcoded fallback (que não existia)
```

**Depois:**
```tsx
// Resolver hh_tipo_id padrão para o tenant usando RPC
let hhTipoId: number | null = null;
try {
  const { data: tipoIdData, error: tipoIdErr } = await supabase.rpc(
    "get_hh_tipo_id_for_tenant",
    { p_tenant_id: ctx.tenant }
  );
  if (!tipoIdErr && tipoIdData) {
    hhTipoId = Number(tipoIdData);
  }
} catch (e) {
  console.warn("[salvarLancamento] Erro ao resolver hh_tipo_id via RPC:", e);
}

if (!hhTipoId || !Number.isFinite(hhTipoId)) {
  setErr(
    "Nenhum tipo de hora configurado para este tenant. " +
    "Verifique se tipos_horas existe e possui registro ativo."
  );
  return false;
}

const basePayload = {
  // ...
  hh_tipo_id: hhTipoId,  // Agora resolvido dinamicamente
  // ...
};
```

## 🧪 Teste

1. **Abra navegador**: `http://localhost:3000/os/71`
2. **Clique "Lançar Horas"**
3. **Preencha e Salve**
4. **Console (F12) deve mostrar**: Nenhum erro; hh_tipo_id resolvido corretamente

## 📊 Mapeamento Lógico

```
tipos_horas (UUID)  ──→  hh_tipos_mapping  ──→  hh_lancamentos (BIGINT)
  id: uuid              tipo_hora_id         hh_tipo_id: BIGINT
  tenant_id              hh_tipo_id
  codigo                tenant_id
  descricao
```

## 🎯 Próximos Passos

**Imediato** (HOJE):
- [ ] Executar `npm run db:migrate`
- [ ] Testar fluxo de lançamento

**Curto Prazo** (Semana):
- [ ] Se houver múltiplos tipos_horas, considerar UI dropdown
- [ ] Documentar criar novos tipos para novos tenants

**Longo Prazo** (Refactoring):
- [ ] Migrar hh_tipo_id de BIGINT para UUID
- [ ] Referenciar tipos_horas diretamente (sem tabela intermediária)

## ⚠️ Notas Importantes

1. **Migration é idempotente** - Pode executar múltiplas vezes
2. **RPC resolve automaticamente** - Busca primeiro tipo_horas ativo
3. **Mapeamento por tenant** - Cada tenant pode ter seus próprios tipos
4. **Fallback se erro em RPC** - Erro mensagem claro ao usuário

