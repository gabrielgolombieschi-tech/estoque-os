# 🔧 CORREÇÕES URGENTES - APLICAR AGORA

## ⚠️ ERROS ENCONTRADOS:

1. ❌ "Sem acesso a empresas. Fale com o admin."
2. ❌ "isEmpresaSelection is not defined"

---

## ✅ CORREÇÕES APLICADAS:

### 1️⃣ **Frontend (AppShell.tsx)**
- ✅ Removido uso de `isEmpresaSelection` (linha 410)
- ✅ Removido bloco de redirecionamento para seleção de empresa

### 2️⃣ **Frontend (TenantEmpresaProvider.tsx)**
- ✅ Corrigido `fetchEmpresasList()` para usar `empresa_memberships` + embed
- ✅ Evita loop infinito (antes usava SELECT direto em `empresas`)

### 3️⃣ **Banco de Dados (RLS)**
- ⚠️ **PRECISA APLICAR**: `PARTE3_CORRIGIR_RLS_EMPRESAS.sql`

---

## 🚨 PRÓXIMO PASSO OBRIGATÓRIO:

### **Aplicar PARTE3 no Supabase:**

```sql
1. Acesse: https://supabase.com/dashboard/project/ptybnreejbkqwwozvhzb/sql/new
2. Abra: PARTE3_CORRIGIR_RLS_EMPRESAS.sql
3. Copie TODO o conteúdo
4. Cole no editor SQL
5. Clique RUN
```

**O que faz:**
- 🔧 Remove políticas RLS antigas da tabela `empresas`
- ✅ Cria novas políticas que NÃO dependem de `current_empresa_id()`
- ✅ Permite SELECT via `empresa_memberships` (sem loop infinito)
- ✅ Mantém controle de admin para INSERT/UPDATE/DELETE

---

## 🔄 DEPOIS DE APLICAR PARTE3:

1. **No navegador:**
   - F5 para recarregar a página
   - Ou Ctrl+Shift+R (hard reload)
   - Limpar cache se necessário

2. **Fazer logout e login novamente**

3. **Verificar:**
   - ✅ Não aparece mais "Sem acesso a empresas"
   - ✅ Não aparece mais erro "isEmpresaSelection"
   - ✅ Menu carrega normalmente
   - ✅ Mostra "Empresa: Elétrica Segau" no header

---

## 📋 RESUMO DO PROBLEMA:

**Causa Raiz:**
- A tabela `empresas` tinha política RLS que dependia de `current_empresa_id()`
- Mas `current_empresa_id()` precisa ler a tabela `empresas`
- **LOOP INFINITO** → Query bloqueada → `empresas.length === 0`

**Solução:**
- Políticas RLS de `empresas` agora usam `empresa_memberships` para verificação
- `fetchEmpresasList()` usa embed `empresa_memberships → empresas`
- Quebra o loop infinito

---

## ✅ CHECKLIST:

- [x] Código frontend corrigido (AppShell + Provider)
- [ ] **PARTE3 aplicada no Supabase** ← FAZER AGORA!
- [ ] Hard reload no navegador (Ctrl+Shift+R)
- [ ] Logout + Login novamente
- [ ] Testar se carrega normalmente

---

**🎯 Aplique PARTE3 AGORA e depois teste!**
