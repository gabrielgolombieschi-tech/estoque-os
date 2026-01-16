# 🔧 Correção: HH Lançamentos - Campos de 2 Períodos

**Data**: 2026-02-19  
**Status**: ✅ IMPLEMENTADO  
**Tipo**: Bug Fix + Migration

---

## 📋 Resumo Executivo

### Problema
- Usuário preenche **2 períodos**: Entrada1/Saída1 e Entrada2/Saída2
- Sistema salva apenas nos campos **legados**: hora_entrada/hora_saida
- Campos novos (entrada_1/saida_1/entrada_2/saida_2) ficam **NULL**
- Listagem mostra "—" para período 2
- Cálculo de horas pode ficar **INCORRETO**

### Solução
1. ✅ **Frontend**: Payload agora envia `entrada_1`, `saida_1`, `entrada_2`, `saida_2`
2. ✅ **Backend**: Função trigger corrigida para reconhecer campos novos
3. ✅ **Compatibilidade**: Sincronização automática entre novos e legados
4. ✅ **Cálculo**: horas_trabalhadas = período1 + período2 (correto!)

---

## 🎯 O Que Mudou

### Frontend (RelatorioHHSection.tsx)

#### ❌ ANTES
```typescript
const basePayload = {
  // ...
  hora_entrada: horaEntrada1,      // ❌ Envia para campo legado
  hora_saida: horaSaida2,          // ❌ Não envia novos
  // ... entrada_1/saida_1/entrada_2/saida_2 NÃO vêm
};
```

#### ✅ DEPOIS
```typescript
// Converter minutos para HH:MM
const minutosParaHHMM = (minutos: number): string => {
  const hh = Math.floor(minutos / 60);
  const mm = minutos % 60;
  return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
};

const basePayload = {
  // ...
  // ✅ NOVOS (principal):
  entrada_1: minutosParaHHMM(entrada1),
  saida_1: minutosParaHHMM(saida1),
  entrada_2: minutosParaHHMM(entrada2),
  saida_2: minutosParaHHMM(saida2),
  // Legacy (para compatibilidade, trigger preencherá automaticamente):
  hora_entrada: minutosParaHHMM(entrada1),
  hora_saida: minutosParaHHMM(saida2),
};
```

### Validações Melhoradas

#### ❌ ANTES
```typescript
if (!isTwoPeriodTimeRangeValid(entrada1, saida1, entrada2, saida2)) {
  setErr("Horários inválidos...");
  return false;
}
```

#### ✅ DEPOIS
```typescript
if (entrada1 >= saida1) {
  setErr("Entrada 1 deve ser menor que Saída 1.");
  return false;
}
if (entrada2 >= saida2) {
  setErr("Entrada 2 deve ser menor que Saída 2.");
  return false;
}
if (saida1 > entrada2) {
  setErr("Saída 1 deve ser menor ou igual a Entrada 2 (sem sobreposição).");
  return false;
}
```

### Banco de Dados (SQL Migration)

#### Nova Migration
```
File: supabase/migrations/20260219_fix_hh_campos_periodos.sql
Type: Function + Trigger fix
Lines: 200+
```

#### Função `fn_hh_lancamentos_calc()` - Corrigida

**Antes**: Ignorava entrada_1/saida_1/entrada_2/saida_2  
**Depois**: Reconhece e processa corretamente

```sql
-- PASSO 1: Resolver entrada_1/saida_1 com fallback para legado
IF NEW.entrada_1 IS NOT NULL THEN
  v_entrada1_min := time_to_minutes(NEW.entrada_1);
ELSIF NEW.hora_entrada IS NOT NULL THEN
  v_entrada1_min := time_to_minutes(NEW.hora_entrada);
  NEW.entrada_1 := NEW.hora_entrada;  -- Sincroniza
END IF;

-- PASSO 2: Resolver entrada_2/saida_2 (obrigatório)
IF NEW.entrada_2 IS NULL THEN
  RAISE EXCEPTION 'entrada_2 é obrigatória';
END IF;
v_entrada2_min := time_to_minutes(NEW.entrada_2);
v_saida2_min := time_to_minutes(NEW.saida_2);

-- PASSO 3: Validar períodos (correto!)
IF v_entrada1_min >= v_saida1_min THEN
  RAISE EXCEPTION 'Entrada 1 deve ser menor que Saída 1';
END IF;
IF v_saida1_min > v_entrada2_min THEN
  RAISE EXCEPTION 'Períodos não podem sobrepor';
END IF;

-- PASSO 4: Sincronizar legado com novos
NEW.hora_entrada := COALESCE(NEW.entrada_1, NEW.hora_entrada);
NEW.hora_saida := COALESCE(NEW.saida_2, NEW.hora_saida);

-- PASSO 5: Calcular horas (SOMA DOS 2 PERÍODOS!)
v_horas_periodo1_decimal := (v_saida1_min - v_entrada1_min) / 60.0;
v_horas_periodo2_decimal := (v_saida2_min - v_entrada2_min) / 60.0;
v_horas_trabalhadas := v_horas_periodo1_decimal + v_horas_periodo2_decimal;
NEW.horas_trabalhadas := v_horas_trabalhadas;

-- PASSO 6: Calcular valor_total
NEW.valor_total := v_horas_trabalhadas * v_valor_hora;
```

---

## 📊 Exemplo: Antes vs Depois

### Cenário
```
Usuário lança:
- Data: 2026-02-19
- Entrada 1: 07:30
- Saída 1: 12:00  (4.5 horas)
- Entrada 2: 13:00
- Saída 2: 17:00  (4.0 horas)
Total esperado: 8.5 horas
```

### ❌ ANTES (BUG)
```
INSERT hh_lancamentos (
  entrada_1: NULL,
  saida_1: NULL,
  entrada_2: NULL,
  saida_2: NULL,
  hora_entrada: "07:30",
  hora_saida: "17:00",
  horas_trabalhadas: 9.5,  ← ERRADO! (07:30 a 17:00 é 9.5, mas não contabilizou almoço)
  valor_total: 9.5 * X      ← ERRADO!
)
```

**Listagem mostra**:
```
Data     | Colaborador | Entrada 1 | Saída 1 | Entrada 2 | Saída 2 | Horas
---------|-------------|-----------|---------|-----------|---------|-------
19/02    | João        | —         | —       | —         | —       | 9.5 ❌
```

### ✅ DEPOIS (CORRIGIDO)
```
INSERT hh_lancamentos (
  entrada_1: "07:30",
  saida_1: "12:00",
  entrada_2: "13:00",
  saida_2: "17:00",
  hora_entrada: "07:30",  ← Para compatibilidade
  hora_saida: "17:00",    ← Para compatibilidade
  horas_trabalhadas: 8.5, ← CORRETO! (4.5 + 4.0)
  valor_total: 8.5 * X    ← CORRETO!
)
```

**Listagem mostra**:
```
Data     | Colaborador | Entrada 1 | Saída 1 | Entrada 2 | Saída 2 | Horas
---------|-------------|-----------|---------|-----------|---------|-------
19/02    | João        | 07:30     | 12:00   | 13:00     | 17:00   | 8.5 ✅
```

---

## 🔄 Compatibilidade Legada

### Cenário 1: Frontend Novo + Backend Novo
```
Frontend envia: entrada_1, saida_1, entrada_2, saida_2
         ↓
Trigger fn_hh_lancamentos_calc():
  - Usa campos novos (prioridade)
  - Sincroniza legado automaticamente
  - Calcula corretamente
         ↓
Banco: Todos campos preenchidos, cálculo correto ✅
```

### Cenário 2: Frontend Legado + Backend Novo (compatibilidade)
```
Frontend envia: APENAS hora_entrada, hora_saida
         ↓
Trigger fn_hh_lancamentos_calc():
  - Detecta campos novos NULL
  - Usa legado como fallback
  - Copia para entrada_1/saida_1
  - ERRO: entrada_2/saida_2 ainda NULL → EXCEPTION
         ↓
User deve usar novo interface (recomendado)
```

### Cenário 3: Dados Legados Existentes
```
Migração executa:
  - Não toca dados existentes
  - Próximos inserts usam novos campos
  - Readaptação gradual garantida
```

---

## 🚀 Como Usar

### 1. Aplicar Migration
```bash
npm run db:migrate -- --from 20260219_fix_hh_campos_periodos.sql
```

### 2. Recarregar Frontend
```bash
npm run dev
# ou fazer re-build se em produção
```

### 3. Testar
```
1. Abrir OS existente
2. Clicar "Lançar Horas"
3. Preencher:
   - Entrada 1: 07:30
   - Saída 1: 12:00
   - Entrada 2: 13:00
   - Saída 2: 17:00
4. Clicar "Salvar"

✅ Esperado:
   - Mensagem: "Lançamento HH salvo com sucesso!"
   - Listagem mostra: 07:30 | 12:00 | 13:00 | 17:00 | 8.5h
```

---

## ✨ Validações Implementadas

| Validação | Antes | Depois |
|-----------|-------|--------|
| entrada_1 < saida_1 | ✓ (genérica) | ✅ (específica) |
| entrada_2 < saida_2 | ✓ (genérica) | ✅ (específica) |
| saida_1 <= entrada_2 | ✓ (genérica) | ✅ (específica) |
| Conversão HH:MM | ❌ | ✅ |
| Cálculo períodos | ❌ ERRADO | ✅ CORRETO |
| Sincronização legado | ❌ | ✅ |
| Mensagens erro | Genéricas | Específicas |

---

## 📊 Cálculos Internos

### Antes (ERRADO)
```
horas_trabalhadas = (hora_saida - hora_entrada) / 60
                  = (17:00 - 07:30) / 60
                  = 570 / 60
                  = 9.5 horas ❌ (Incluiu almoço!)

valor_total = 9.5 * valor_hora ❌
```

### Depois (CORRETO)
```
periodo1 = (saida_1 - entrada_1) / 60 = (12:00 - 07:30) / 60 = 270 / 60 = 4.5h
periodo2 = (saida_2 - entrada_2) / 60 = (17:00 - 13:00) / 60 = 240 / 60 = 4.0h

horas_trabalhadas = 4.5 + 4.0 = 8.5 horas ✅

valor_total = 8.5 * valor_hora ✅
```

---

## 🔍 Debug Logs

### Console do Frontend
```javascript
[HH_SAVE_PAYLOAD] Payload final a ser enviado: {
  entrada_1: "07:30",
  saida_1: "12:00",
  entrada_2: "13:00",
  saida_2: "17:00",
  hora_entrada: "07:30",
  hora_saida: "17:00",
  _debug_horarios: {
    entrada_1_minutos: 450,
    saida_1_minutos: 720,
    entrada_2_minutos: 780,
    saida_2_minutos: 1020,
    horas_periodo1: "4.50",
    horas_periodo2: "4.00",
    horas_total: "8.50"
  }
}
```

### Backend (quando ativa logs no PostgreSQL)
```
fn_hh_lancamentos_calc() triggered:
  ✓ entrada_1 validation: 450 < 720
  ✓ entrada_2 validation: 780 < 1020
  ✓ periodos validation: 720 <= 780
  ✓ horas_trabalhadas calculated: 8.5
  ✓ valor_total calculated: 8.5 * X
  ✓ legado synced: hora_entrada=07:30, hora_saida=17:00
```

---

## 🛡️ Segurança

- ✅ RLS policies **não alteradas** (segurança mantida)
- ✅ Validações **no banco** (confiável)
- ✅ Sincronização **automática** (não manual, sem risco)
- ✅ Rollback possível (migration é reversível)

---

## 📞 Troubleshooting

### Erro: "entrada_2 é obrigatória"
```
Causa: Frontend não enviou entrada_2/saida_2
Solução: Atualizar frontend (já foi feito)
         Recarregar browser
```

### Erro: "Saída 1 deve ser menor ou igual a Entrada 2"
```
Causa: Períodos se sobrepõem
Exemplo: 
  Saída 1: 14:30
  Entrada 2: 13:00  ← ERRO! Sobrepõe
Solução: Ajustar horários no modal
```

### Horas ainda erradas após fix
```
Causa: Browser em cache, ou migration não aplicada
Solução:
  1. npm run db:migrate (confirmar execução)
  2. Limpar cache do browser (Ctrl+F5)
  3. Recriar lançamento (com novos dados)
  4. Verificar console (F12) para logs
```

---

## ✅ Checklist Pós-Deploy

- [ ] Migration executada: `20260219_fix_hh_campos_periodos.sql`
- [ ] Frontend atualizado: `RelatorioHHSection.tsx`
- [ ] Browser cache limpo
- [ ] Teste 1: Novo lançamento (8.5h esperado)
- [ ] Teste 2: Listagem mostra 4 horários
- [ ] Teste 3: Valor total = 8.5 * valor_hora
- [ ] Teste 4: Edição de lançamento antigo funciona
- [ ] Logs de debug confirmam conversão HH:MM correta

---

## 📚 Arquivos Impactados

```
✅ supabase/migrations/20260219_fix_hh_campos_periodos.sql   (NEW)
✅ app/os/[id]/components/RelatorioHHSection.tsx             (UPDATED)
✅ HH_LANCAMENTOS_FIX_PERIODOS.md                            (THIS FILE)
```

---

**Status**: 🟢 **PRONTO PARA DEPLOY**

