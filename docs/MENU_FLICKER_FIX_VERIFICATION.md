# ✅ Menu Flicker Fix - Verification Guide

## Verificação Rápida

### 1. Build Compila?
```bash
npm run build
# ✅ Deve compilar sem erros
```

### 2. TypeScript OK?
```bash
npm run type-check  # Se disponível
# ou durante build: "Running TypeScript ..."
# ✅ Deve ter 0 errors
```

### 3. Erros no Código?
```bash
npm run lint  # Se configurado
# ✅ Não deve haver errors em:
#   - components/auth/PermissionsProvider.tsx
#   - app/components/AppShell.tsx
```

---

## Teste de Funcionalidade

### Setup

```bash
npm run dev
# Abra http://localhost:3000
# Faça login com uma conta válida
```

### Teste 1: Menu Não Pisca ao Navegar ✅

**Procedimento:**
1. Após login, observe o menu superior
2. Clique em "OS"
3. Clique em "Estoque"
4. Clique em "Home"
5. Clique em diferentes menus

**Esperado:**
- Menu está sempre visível
- Menu não desaparece entre cliques
- Menu não pisca/flecha/recarrega

**Resultado:** `[ ] PASS  [ ] FAIL`

---

### Teste 2: Mudar de Aba Não Recarrega ✅

**Procedimento:**
1. Com login ativo, observe o menu
2. Clique em outra aba (abra `about:blank` em nova aba)
3. Espere 10 segundos
4. Volte para a aba da aplicação

**Esperado:**
- Menu está visível ao voltar
- Menu não desaparece durante a transição
- Nenhuma mensagem "Carregando..." aparece

**Resultado:** `[ ] PASS  [ ] FAIL`

---

### Teste 3: Logout Funciona ✅

**Procedimento:**
1. Com login ativo, clique em "Sair"
2. Observe transição

**Esperado:**
- Menu desaparece imediatamente
- Página redireciona para `/login`
- Não há erro na console

**Resultado:** `[ ] PASS  [ ] FAIL`

---

### Teste 4: Login Carrega Permissões ✅

**Procedimento:**
1. Faça login
2. Aguarde até menu aparecer
3. Observe console (abra DevTools: F12)

**Esperado:**
- Menu aparece com dados de cache
- No console: nenhuma mensagem de "refresh" repetida
- Primeira vez: 1 chamada ao Supabase RPC `can_many`
- Próximas navegações: 0 chamadas adicionais ao RPC

**Resultado:** `[ ] PASS  [ ] FAIL`

---

### Teste 5: Console Limpo ✅

**Procedimento:**
1. Faça login
2. Abra DevTools (F12 → Console)
3. Navegue entre 10 rotas diferentes

**Esperado:**
- Nenhum warning relacionado a permissões
- Nenhum erro de React
- Mensagens normais apenas: sessão refresh, etc.

**Resultado:** `[ ] PASS  [ ] FAIL`

---

## Verificação de Código

### Verificar `PermissionsProvider.tsx`

```bash
grep -n "initializedRef" components/auth/PermissionsProvider.tsx
# ✅ Deve encontrar:
#   - const initializedRef = useRef(false);
#   - initializedRef.current = true;
#   - if (initializedRef.current && ...) return;
```

### Verificar Remoção de `visibilitychange`

```bash
grep -n "visibilitychange" components/auth/PermissionsProvider.tsx
# ✅ Deve retornar: (nenhum resultado)

grep -n "visibilitychange" app/components/AppShell.tsx
# ✅ Deve retornar: (nenhum resultado)
```

### Verificar Remoção de `reload()` desnecessários

```bash
grep -n "reload()" app/components/AppShell.tsx
# ✅ Deve encontrar apenas:
#   - const reload: (...) = ...
#   - <button onClick={() => reload()}>  // No permissionsFailed warning
#   - Nada em boot useEffect
#   - Nada em auth listener useEffect
```

### Verificar Lógica de `permissionsReady`

```bash
grep -A3 "const permissionsReady" app/components/AppShell.tsx
# ✅ Deve ter:
#   const hasCapabilities = permsCapabilities !== null;
#   const permissionsReady: boolean = perms?.ready ?? hasCapabilities;
```

---

## Verificação em Browser DevTools

### Network Tab

1. Abra DevTools → Network
2. Faça login
3. Observe chamadas ao Supabase

**Esperado:**
- Login: 1 chamada POST `/auth/v1/token` (Supabase auth)
- Permissões: 1 chamada POST `sql/v1` ou RPC `can_many`
- **Navegações subsequentes:** 0 novas chamadas ao RPC

**Resultado:** `[ ] PASS  [ ] FAIL`

### Console Network Activity

1. Abra DevTools → Console
2. Cole:
```javascript
// Contar chamadas ao Supabase
console.log(
  performance.getEntries()
    .filter(e => e.name.includes('supabase'))
    .length
);
// Anotar número
```

3. Navegue entre 10 rotas
4. Cole novamente e compare

**Esperado:**
- Número de chamadas não aumenta
- Ou aumenta apenas para dados de página (não permissões)

**Resultado:** `[ ] PASS  [ ] FAIL`

---

## Verificação de Performance

### Métrica: Time to Interactive (TTI)

1. Faça logout completo
2. Limpe cache do browser (Ctrl+Shift+Del)
3. Faça login novamente
4. Abra DevTools → Lighthouse
5. Rode audit de Performance

**Esperado:**
- Nenhuma melhoria esperada (fix é sobre estabilidade, não perf)
- Mas também nenhuma piora

**Resultado:** `[ ] PASS  [ ] FAIL`

---

## Checklist de Validação Final

- [ ] Build compila sem erros
- [ ] Sem TypeScript errors em PermissionsProvider.tsx
- [ ] Sem TypeScript errors em AppShell.tsx
- [ ] Menu não pisca ao navegar
- [ ] Menu não carrega ao mudar de aba
- [ ] Logout funciona corretamente
- [ ] Login carrega permissões
- [ ] Console sem warnings relacionados
- [ ] Network: 1 call RPC por sessão
- [ ] Nenhuma chamada visibilitychange
- [ ] initializedRef presente no código
- [ ] reload() é no-op após init

---

## Rollback (Se Necessário)

Se algo der errado, reverter é simples:

```bash
git diff components/auth/PermissionsProvider.tsx
git diff app/components/AppShell.tsx
# Revisar mudanças

git checkout components/auth/PermissionsProvider.tsx
git checkout app/components/AppShell.tsx
# Reverter se necessário
```

---

## Relatório de Teste

Ao testar, preencha:

```markdown
## Menu Flicker Fix - Test Report

**Data:** 2025-01-13
**Testador:** [Seu Nome]
**Ambiente:** Development / Staging / Production

### Testes de Funcionalidade
- [x] Teste 1: Menu Não Pisca
- [x] Teste 2: Mudança de Aba
- [x] Teste 3: Logout
- [x] Teste 4: Login e Permissões
- [x] Teste 5: Console Limpo

### Verificação de Código
- [x] initializedRef presente
- [x] visibilitychange removido
- [x] reload() calls removidas
- [x] permissionsReady corrigida

### Performance
- [x] Build ok
- [x] TypeScript ok
- [x] Network: 1 RPC call
- [x] Nenhum console warning

### Resultado Final
✅ **PASS - Ready for Production**
```

---

## Contato para Problemas

Se encontrar problemas:

1. Verifique se compilou: `npm run build`
2. Limpe cache: `npm run clean` (se existir) ou delete `.next/`
3. Verifique console para mensagens de erro
4. Compare diffs: `git diff` nos arquivos modificados
5. Revert se necessário: `git checkout` nos arquivos

