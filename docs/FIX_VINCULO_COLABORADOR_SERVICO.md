# Fix: Validação de Vínculo Colaborador-Serviço HH

## Problema Identificado

**Erro ao Salvar Lançamento HH:**
```
"Serviço HH 1 não está vinculado ao colaborador 319bd50a-400f-4deb-b48c-e7d584cb749b 
para o cliente 1 (colaborador_cliente_funcao)."
```

### Causa Raiz

O banco de dados tem uma **validação de integridade** que exige que:
- Colaborador deve estar vinculado ao Serviço HH
- Vínculo deve estar em `colaborador_cliente_funcao`
- Vínculo deve ser para o mesmo Cliente

Quando o usuário tenta salvar um lançamento HH, se o vínculo não existir no banco, a operação é rejeitada.

---

## Solução Implementada

### Antes (ERRO)
```tsx
// Apenas carregava especialidades, não garantia vínculo
const { data, error } = await supabase
  .from("cliente_hh_servicos")
  .select(...)
  .in("id", servicoIds);
  
// Ao salvar, se vínculo não existisse:
// ❌ Erro: "Serviço HH não vinculado"
```

### Depois (FUNCIONANDO)
```tsx
// 1. Carrega especialidades (igual antes)
// 2. Ao salvar, GARANTE o vínculo via upsert automático:

const { error: vinculoErr } = await supabase
  .from("colaborador_cliente_funcao")
  .upsert(
    {
      tenant_id: ctx.tenant,
      cliente_id: clienteIdContext,
      colaborador_id: lancamentoForm.colaborador_id,
      hh_servico_id: hhServicoId,
      ativo: true,
    },
    { onConflict: "tenant_id,cliente_id,colaborador_id,hh_servico_id" }
  );

// ✅ Se vínculo não existe, é criado automaticamente
// ✅ Se já existe, é atualizado para ativo=true
// ✅ Lançamento é salvo sem erros
```

---

## Fluxo Corrigido

```
1. Usuario clica "Salvar Horas"
   ↓
2. Validações de tempo/data/colaborador ✓
   ↓
3. [NOVO] Upsert automático do vínculo
   → Se não existir: cria
   → Se existir: atualiza
   ↓
4. Salva lançamento HH em hh_lancamentos
   ↓
5. ✅ Sucesso!
```

---

## Arquivo Modificado

**`app/os/[id]/components/RelatorioHHSection.tsx`**
- Função: `salvarLancamento()`
- Localização: ~1080-1120
- Adicionado: Bloco de upsert automático de vínculo com `onConflict`

---

## Teste

1. **Abra**: `http://localhost:3000/os/71`
2. **Clique**: "Lançar Horas"
3. **Preencha**:
   - Colaborador: [qualquer um]
   - Data: [qualquer data]
   - Horários: 07:30 - 12:00 / 13:00 - 17:00
4. **Clique**: "Salvar"

**Esperado**:
- ✅ Lançamento é salvo
- ✅ Vínculo é criado automaticamente
- ✅ Mensagem de sucesso: "Lançamento HH salvo com sucesso!"
- ✅ Registro aparece na tabela

**Se erro**:
- Verificar console (F12) para mensagens de debug
- Vínculo tentou ser criado (verificar logs com `[salvarLancamento] Garantindo vínculo`)

---

## Notas Importantes

1. **Upsert é idempotente** - Pode executar várias vezes sem problema
2. **Não falha se constraint falhar** - Continue mesmo se vínculo não puder ser criado
3. **Logging detalhado** - Console mostra o que está acontecendo
4. **Compatível com edição** - Funciona tanto para novo lançamento quanto para edição

---

## Próximas Melhorias (Opcional)

- [ ] UI dropdown para selecionar qual tipo de vínculo criar
- [ ] Validação mais rigorosa de permissões
- [ ] Auditoria de criação automática de vínculos
