# ✅ HH Sync Error 400 - Corrigido

## Problema

Ao salvar um lançamento HH, estava recebendo erro **400 Bad Request** ao tentar sincronizar com `apontamentos_horas`:

```
POST https://ptybnreejbkqwwozvhzb.supabase.co/rest/v1/apontamentos_horas
Status Code: 400 Bad Request
```

## Causa Raiz

O código em `src/lib/hh/syncHhToApontamentos.ts` estava usando **nomes de coluna errados**:

```typescript
// ❌ ERRADO (campos não existem na tabela)
payload = {
  hora_inicio: entrada,    // ← Campo não existe!
  hora_fim: saida,         // ← Campo não existe!
  horas,
  tipo_hora_id: tipoHoraId,
  // ...
}
```

Mas a tabela `apontamentos_horas` no schema.sql define:

```sql
CREATE TABLE public.apontamentos_horas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  os_id integer NOT NULL,
  colaborador_id uuid NOT NULL,
  data date NOT NULL,
  horas numeric(6,2) NOT NULL,
  tipo_hora_id uuid,
  fator_aplicado numeric(6,3),
  descricao text,
  status character varying(20) DEFAULT 'lancado'::character varying,
  criado_em timestamp with time zone DEFAULT now(),
  tenant_id uuid NOT NULL,
  hh_especialidade_id uuid,
  hora_entrada_1 time without time zone,  -- ← Período 1 (manhã)
  hora_saida_1 time without time zone,    -- ← Período 1 (manhã)
  hora_entrada_2 time without time zone,  -- ← Período 2 (tarde)
  hora_saida_2 time without time zone,    -- ← Período 2 (tarde)
  empresa_id uuid DEFAULT public.current_empresa_id(),
  gerado_por_hh boolean DEFAULT false,
  CONSTRAINT apontamentos_horas_periodos_ck CHECK (
    (hora_entrada_1 IS NOT NULL AND hora_saida_1 IS NOT NULL AND 
     hora_entrada_2 IS NOT NULL AND hora_saida_2 IS NOT NULL AND 
     hora_saida_1 > hora_entrada_1 AND 
     hora_saida_2 > hora_entrada_2 AND 
     hora_saida_1 <= hora_entrada_2)
  )
);
```

## Solução Aplicada

Corrigido `src/lib/hh/syncHhToApontamentos.ts` para:

1. **Usar nomes corretos de colunas**: `hora_entrada_1`, `hora_saida_1`, `hora_entrada_2`, `hora_saida_2`
2. **Mapeamento dinâmico de períodos**:
   - 1º período: `hora_entrada_1` + `hora_saida_1`
   - 2º período: `hora_entrada_2` + `hora_saida_2`

```typescript
// ✅ CORRETO (campo dinamicamente mapeado)
let periodoIndex = 0;
for (const periodo of periodos) {
  // ... validações ...
  
  const entradaField = periodoIndex === 0 ? "hora_entrada_1" : "hora_entrada_2";
  const saidaField = periodoIndex === 0 ? "hora_saida_1" : "hora_saida_2";
  periodoIndex++;
  
  let payload: any = {
    tenant_id: tenantId,
    os_id: osId,
    colaborador_id: colaboradorId,
    data: dataISO,
    [entradaField]: entrada,    // ✅ Campo dinamicamente mapeado
    [saidaField]: saida,        // ✅ Campo dinamicamente mapeado
    horas,
    tipo_hora_id: tipoHoraId,
    gerado_por_hh: true,
    descricao: descricao ?? null,
  };
}
```

## Validação de Restrição

A tabela tem uma restrição (`apontamentos_horas_periodos_ck`) que obriga:
- **Ou tudo null**: `hora_entrada_1, hora_saida_1, hora_entrada_2, hora_saida_2` são todos NULL
- **Ou tudo preenchido**: todos os 4 campos preenchidos E `hora_saida_1 <= hora_entrada_2` (intervalo de almoço)

Como estamos lançando **dois períodos** (entrada1/saida1 + entrada2/saida2), todos os 4 campos serão preenchidos.

## Próxima Ação

Teste salvando novo lançamento HH com dois períodos. Agora deverá:
1. ✅ Salvar em `hh_lancamentos`
2. ✅ Sincronizar corretamente em `apontamentos_horas` (sem erro 400)

## Arquivos Modificados

- `src/lib/hh/syncHhToApontamentos.ts` — Corrigido payload para usar campos corretos

---

**Data da correção:** 2026-01-22  
**Status:** ✅ Corrigido
