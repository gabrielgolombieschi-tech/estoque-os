# Fix: Campo hh_servico_id Faltando no Payload

## Problema

**Erro ao Salvar Lançamento HH:**
```
"Serviço HH 1 não está vinculado ao colaborador 319bd50a... para o cliente 1 (colaborador_cliente_funcao)."
```

**Por Quê?**

O banco tem uma **constraint check** que valida:
- Antes de inserir em `hh_lancamentos`
- Verifica se `(tenant_id, cliente_id, colaborador_id, hh_servico_id)` existe em `colaborador_cliente_funcao`
- Se não existir → ERRO

### Raiz do Problema

O código estava:
1. ✅ Criando o vínculo automaticamente via upsert
2. ❌ **Mas NÃO enviando `hh_servico_id` no payload do INSERT**

Resultado:
- Vínculo era criado: `colaborador_cliente_funcao` ✓
- Mas INSERT falhava porque payload não tinha `hh_servico_id`
- Constraint não conseguia validar

---

## Solução

### Antes (ERRO)
```typescript
const basePayload = {
  tenant_id: ctx.tenant,
  empresa_id: ctx.empresa,
  os_id: osId,
  colaborador_id: lancamentoForm.colaborador_id,
  hh_tipo_id: hhTipoId,
  // ❌ FALTAVA: hh_servico_id
  data: lancamentoForm.data,
  // ... outros campos
};
```

### Depois (FUNCIONANDO)
```typescript
const basePayload = {
  tenant_id: ctx.tenant,
  empresa_id: ctx.empresa,
  os_id: osId,
  colaborador_id: lancamentoForm.colaborador_id,
  hh_tipo_id: hhTipoId,
  hh_servico_id: hhServicoId,  // ✅ ADICIONADO
  data: lancamentoForm.data,
  // ... outros campos
};
```

---

## Fluxo Correto Agora

```
1. Usuario seleciona colaborador + especialidade (hh_servico_id)
   ↓
2. Clica "Salvar Horas"
   ↓
3. Valida tempos, datas, valores ✓
   ↓
4. IMPORTANTE: Cria vínculo automaticamente
   INSERT INTO colaborador_cliente_funcao (tenant_id, cliente_id, colaborador_id, hh_servico_id)
   VALUES (ctx.tenant, clienteIdContext, colaborador_id, hhServicoId)
   ON CONFLICT (...) UPDATE SET ativo = true
   ↓
5. Calcula valores (valor_hora, percentual aplicado, etc)
   ↓
6. Prepara payload com TODOS os campos incluindo hh_servico_id
   ↓
7. INSERT INTO hh_lancamentos
   ↓
8. Constraint check passa: "Serviço 1 está vinculado ao colaborador X para cliente 1" ✓
   ↓
9. ✅ Sucesso!
```

---

## Arquivo Modificado

**`RelatorioHHSection.tsx`** - Função `salvarLancamento()` (linha ~1170)

```typescript
const basePayload = {
  tenant_id: ctx.tenant,
  empresa_id: ctx.empresa,
  os_id: osId,
  colaborador_id: lancamentoForm.colaborador_id,
  hh_tipo_id: hhTipoId,
  hh_servico_id: hhServicoId,  // ✅ NOVO
  data: lancamentoForm.data,
  hora_entrada: horaEntrada1,
  hora_saida: horaSaida2,
  percentual_aplicado: percentual,
  entrada_1: horaEntrada1,
  saida_1: horaSaida1,
  entrada_2: e2Raw,
  saida_2: s2Raw,
  observacao: descRaw || null,
  valor_hora: valorHoraAplicado,
};
```

---

## Por que isso funciona?

1. **Vínculo criado primeiro** (via upsert antes do insert)
   - `colaborador_cliente_funcao` agora tem a combinação

2. **Payload tem hh_servico_id**
   - Database consegue validar: "Sim, este serviço está vinculado ao colaborador"

3. **Constraint passa**
   - INSERT é permitido

---

## Teste

1. Abra: `http://localhost:3000/os/71`
2. Clique: "Lançar Horas"
3. Preencha (qualquer valor):
   - Colaborador: [qualquer]
   - Data: [hoje]
   - Horários: 07:30-12:00 e 13:00-17:00
4. Clique: "Salvar"

**Esperado**:
- ✅ Mensagem de sucesso
- ✅ Lançamento aparece na tabela
- ✅ Sem mais erros de vínculo

---

## Debugando se Falhar

Abra **F12 → Console** e procure por:

```
[salvarLancamento] Garantindo vínculo...
[salvarLancamento] Vínculo garantido/atualizado
```

Se vir essas mensagens:
- ✅ Vínculo foi criado
- ✅ hh_servico_id está no payload
- ✅ INSERT deve passar

Se ver erros:
- Verifique se `clienteIdContext` tem valor
- Verifique se `hh_servico_id` está sendo resolvido corretamente
- Verifique se tipos_horas tem pelo menos 1 registro ativo
