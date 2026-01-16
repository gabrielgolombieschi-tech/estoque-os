# Resolução de hh_tipo_id no Fluxo HH

**Status**: 🔴 BLOQUEANTE - Aguardando definição da estratégia

## Problema Identificado

### Tabela deletada
- **Tabela deletada**: `hh_tabela_precos`
- **Função quebrada**: `resolveHhTipoIdForServico()` tentava mapear automáticamente
- **Erro**: "Tipo HH não resolvido. Verifique se existe um tipo de hora compatível."

### Campo obrigatório
```sql
CREATE TABLE hh_lancamentos (
  hh_tipo_id bigint NOT NULL,  -- ❌ OBRIGATÓRIO
  ...
)
```

## Situação Atual

### O que temos:
- ✅ `cliente_hh_servicos`: Tabela de especialidades com preços
- ✅ `cliente_hh_tabelas`: Tabela de preços com vigência
- ✅ `colaborador_cliente_funcao`: Vínculo colaborador ↔ serviço
- ✅ `hh_lancamentos`: Tabela de lançamentos de horas
- ✅ Trigger `fn_hh_lancamentos_calc`: Calcula `horas_trabalhadas`, `valor_total`

### O que não temos:
- ❌ `hh_tabela_precos`: DELETADA (era a fonte de `hh_tipo_id`)
- ❌ Forma de mapear `cliente_hh_servicos` → `hh_tipo_id`
- ❌ Valor padrão/fallback para `hh_tipo_id`

## Possíveis Soluções

### Solução 1: Usar Primeiro Tipo Padrão (Simples)

**Implementação**:
```tsx
// Em salvarLancamento():
const basePayload = {
  // ...
  hh_tipo_id: 1, // Tipo padrão (sempre a primeira linha de alguma tabela)
  // ...
};
```

**Prós**:
- ✅ Rápido de implementar
- ✅ Não precisa de UI adicional
- ✅ Funciona se houver um tipo "padrão" fixo

**Contras**:
- ❌ Nem sempre correto (tipos diferentes têm preços diferentes)
- ❌ Perde informação de qual tipo foi usado
- ❌ Relatórios podem ficar confusos

---

### Solução 2: Adicionar Dropdown na UI (Recomendado)

**Mudança de Schema Necessária**:
Criar tabela simples de tipos:
```sql
CREATE TABLE hh_tipos (
  id bigserial PRIMARY KEY,
  nome varchar(100) NOT NULL,
  descricao text,
  ativo boolean DEFAULT true,
  criado_em timestamp DEFAULT now()
);

INSERT INTO hh_tipos (nome, descricao) VALUES
  ('Normal', 'Hora normal/regular'),
  ('Extra 50%', 'Hora extra 50%'),
  ('Extra 100%', 'Hora extra 100%'),
  ('Noturna', 'Hora noturna'),
  ('Adicional', 'Hora com adicional');
```

**Implementação na UI**:
```tsx
// Em RelatorioHHSection:
const [hhTiposOptions, setHhTiposOptions] = useState<Array<{ id: number; nome: string }>>([]);

useEffect(() => {
  // Carregar tipos HH disponíveis
  const { data } = await supabase
    .from("hh_tipos")
    .select("id,nome")
    .eq("ativo", true)
    .order("nome");
  setHhTiposOptions(data ?? []);
}, []);

// No formulário:
<select
  value={lancamentoForm.hh_tipo_id ?? ""}
  onChange={(e) => setLancamentoForm(prev => ({ ...prev, hh_tipo_id: Number(e.target.value) }))}
>
  <option value="">Selecione o tipo...</option>
  {hhTiposOptions.map(tipo => (
    <option key={tipo.id} value={tipo.id}>{tipo.nome}</option>
  ))}
</select>
```

**Prós**:
- ✅ Usuário tem controle total
- ✅ Flexível para diferentes tipos
- ✅ Relatórios mais precisos
- ✅ Escalável

**Contras**:
- ❌ Requer UI adicional
- ❌ Requer criação de tabela `hh_tipos`
- ❌ Mais lógica no código

---

### Solução 3: Auto-Mapear via Trigger (Avançado)

**Implementação**:
Modificar trigger `fn_hh_lancamentos_calc` para:
1. Receber `hh_servico_id` 
2. Mapear automaticamente para `hh_tipo_id` baseado em regra interna

```sql
CREATE OR REPLACE FUNCTION fn_hh_lancamentos_calc()
RETURNS TRIGGER AS $$
BEGIN
  -- ... código existente ...
  
  -- Auto-resolver hh_tipo_id se não fornecido
  IF NEW.hh_tipo_id IS NULL THEN
    SELECT id INTO NEW.hh_tipo_id
    FROM hh_tipos
    WHERE nome = 'Normal'
    LIMIT 1;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**Prós**:
- ✅ Lógica centralizada no banco
- ✅ UI permanece simples

**Contras**:
- ❌ Precisa modificar trigger existente
- ❌ Lógica "mágica" (usuário não vê o que está acontecendo)

---

## Recomendação

**Para HOJE** (correção imediata):
- ✅ Usar **Solução 1**: `hh_tipo_id: 1` como padrão
- ✅ Deixar comentário no código explicando a situação
- ✅ Permitir salvar lançamentos de forma funcional

**Para AMANHÃ/PRÓXIMA SEMANA**:
- Implementar **Solução 2**: Dropdown de tipos na UI
- Criar tabela `hh_tipos` com tipos padrão
- Atualizar `salvarLancamento()` para validar tipo selecionado

## Status das Correções

| Problema | Status | Solução |
|----------|--------|---------|
| loadRelatorios | ✅ CORRIGIDO | Tornar no-op (tabela deletada) |
| resolveHhTipoIdForServico | ✅ PARCIAL | Retorna null; usar fallback 1 |
| salvarLancamento | ✅ AJUSTADO | Usar hh_tipo_id: 1 como default |
| Relatórios HH | 🟡 FUNCIONAL | Gera PDF direto de hh_lancamentos |

## Próximos Passos

1. **Testar com solução atual** (hh_tipo_id: 1)
   ```bash
   npm run dev
   # Ir para http://localhost:3000/os/71
   # Tentar lançar horas
   ```

2. **Se funcionar**: OK! Deixar como está por enquanto

3. **Se não funcionar**: Verificar se:
   - `hh_tipos` tabela existe com pelo menos 1 linha
   - FK `hh_lancamentos.hh_tipo_id` → `hh_tipos.id` existe
   - Trigger está permitindo `hh_tipo_id: 1` (não override)

4. **Depois**: Implementar UI dropdown como Solução 2

## Arquivos Afetados

- ✅ `app/os/[id]/components/RelatorioHHSection.tsx`
  - Removido: `loadRelatorios()` (acessa tabela deletada)
  - Removido: `resolveHhTipoIdForServico()` (acessa tabela deletada)
  - Ajustado: `salvarLancamento()` (usa `hh_tipo_id: 1` como fallback)

## Questão para o User

**Qual solução prefere?**
1. Manter `hh_tipo_id: 1` como padrão (simples, agora)
2. Adicionar dropdown de tipos (melhor, depois)
3. Outra?
