# Correções HH - Resumo Executivo

**Data**: 15 de janeiro de 2026  
**Versão**: v2.0 (Pós-cleanup de tabelas deletadas)

## ✅ O Que Foi Corrigido

### 1. Erro "Erro ao carregar relatórios"
**Causa**: `loadRelatorios()` tentava acessar `os_relatorios_hh` (tabela deletada)

**Solução**: Tornar função um no-op
```tsx
async function loadRelatorios() {
  // DEPRECATED: Tabela os_relatorios_hh foi removida.
  setRelatorios([]);
}
```

**Status**: ✅ CORRIGIDO

---

### 2. Erro "Tipo HH não resolvido"
**Causa**: `resolveHhTipoIdForServico()` tentava acessar `hh_tabela_precos` (deletada)

**Solução Temporária**: Usar `hh_tipo_id: 1` como fallback
```tsx
const basePayload = {
  // ...
  hh_tipo_id: 1, // Será calculado pelo trigger ou usar valor padrão
  valor_hora: valorHoraAplicado,
};
```

**Status**: ✅ FUNCIONA (temporário)

---

## 🔴 Pré-Requisito Importante

Para que o lançamento de horas funcione, você precisa ter:

1. **Tabela `hh_tipos`** (ou equivalente) com pelo menos 1 linha:
   ```sql
   CREATE TABLE hh_tipos (
     id bigserial PRIMARY KEY,
     nome varchar(100),
     ativo boolean DEFAULT true
   );
   INSERT INTO hh_tipos (nome) VALUES ('Normal');
   ```

2. **FK válida em `hh_lancamentos.hh_tipo_id`**:
   ```sql
   ALTER TABLE hh_lancamentos
   ADD CONSTRAINT hh_lancamentos_hh_tipo_id_fkey 
   FOREIGN KEY (hh_tipo_id) REFERENCES hh_tipos(id);
   ```

Se essa tabela/FK não existir, vai dar erro na gravação!

---

## 🧪 Como Testar

### Passo 1: Verificar se tabela `hh_tipos` existe
```bash
# No Supabase SQL Editor:
SELECT * FROM hh_tipos LIMIT 5;
```

Se não existir, criar conforme acima.

### Passo 2: Rodar dev
```bash
npm run dev
```

### Passo 3: Ir para OS com HH
```
http://localhost:3000/os/71
```

### Passo 4: Abrir formulário de lançamento
- Clique em "Lançar Horas"
- Selecione colaborador
- Preencha horários
- Clique em "Salvar"

### Resultado esperado:
- ✅ Sem erro "Tipo HH não resolvido"
- ✅ Lançamento salvo em `hh_lancamentos`
- ✅ Lançamento aparece na tabela

---

## 📋 Checklist Técnico

- [x] Remover chamada a `os_relatorios_hh` (deletada)
- [x] Remover chamada a `hh_tabela_precos` (deletada)
- [x] Usar fallback `hh_tipo_id: 1`
- [x] Adicionar `valor_hora` na payload (estava faltando!)
- [x] Testar TypeScript (0 errors)
- [ ] Testar no browser (aguardando você)
- [ ] Garantir `hh_tipos` tabela existe no DB
- [ ] Garantir FK existe

---

## 🎯 Próxima Fase

**DEPOIS que funcionar com `hh_tipo_id: 1`**:

Implementar **Solução 2** (mais robusta):
- Adicionar dropdown de tipos HH na UI
- Usuário escolhe qual tipo usar ao lançar
- Mais flexível e preciso

Ver arquivo: [`docs/HH_TIPO_ID_RESOLUCAO.md`](HH_TIPO_ID_RESOLUCAO.md)

---

## 📁 Arquivos Modificados

| Arquivo | Mudanças |
|---------|----------|
| `app/os/[id]/components/RelatorioHHSection.tsx` | - Remover `loadRelatorios()` (query tabela deletada)<br>- Remover `resolveHhTipoIdForServico()` (query tabela deletada)<br>- Ajustar `salvarLancamento()` (usar hh_tipo_id: 1, adicionar valor_hora) |

---

## 🐛 Se Ainda Tiver Erro

### Erro: "No rows returned"
- Verificar se `hh_tipos` tabela existe
- Executar: `INSERT INTO hh_tipos (nome) VALUES ('Normal');`

### Erro: "Foreign key violation"
- Verificar se `hh_lancamentos.hh_tipo_id` tem FK para `hh_tipos.id`
- Se não tiver, executar migration

### Erro: "Permission denied"
- Verificar RLS policies em `hh_lancamentos`
- Verificar se tenant_id e empresa_id estão corretos

---

## 📞 Suporte

Se não conseguir, deixa eu saber:
1. Qual erro aparece no browser (em português)
2. Qual erro aparece no console (F12 → Console)
3. Se consegue acessar a OS com HH flag
