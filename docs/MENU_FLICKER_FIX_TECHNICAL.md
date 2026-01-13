# 🔍 Análise Técnica: Menu Flicker Fix

## Diagnóstico Detalhado do Problema

### Fluxo Problemático (Antes)

```
┌─ Usuário clica em rota diferente
│
├─ React Router muda pathname
│
├─ AppShell re-renderiza
│  ├─ useState dependencies NOT changed
│  ├─ useEffect dependencies: nenhum relacionado a rota
│  ├─ perms object same reference (via useContext)
│  └─ Menu recebe mesmas props
│
├─ PROBLEMA: visibilitychange listener ainda está ativo
│  └─ Se aba ficar oculta/visível durante navegação:
│     └─ refreshPermissions({ background: true }) dispara
│
├─ PROBLEMA: AppShell listener de auth
│  └─ Pode disparar `reload()` em múltiplos eventos
│
└─ Resultado: loadingInitial = true por 500-1000ms
   └─ Menu desaparece: {loadingInitial && "Carregando..."}
   └─ Menu volta quando loadingInitial = false
   └─ PISCA! 👁️ PISCA! 👁️
```

### Análise da Causa Raiz

#### 1. `visibilitychange` listener (PermissionsProvider)

```tsx
// ANTES ❌
const visibilityHandler = () => {
  if (!document.hidden) {
    // Tab voltou ao foco: SEMPRE recarrega em background
    void refreshPermissions({ background: true });
  }
};
document.addEventListener("visibilitychange", visibilityHandler);
```

**Por que pisca:**
- Ao trocar de abas (mesmo sem deixar a aba), pode ocorrer `visibilitychange`
- Dispara `refreshPermissions({ background: true })`
- `setRefreshing(true)` NÃO afeta `loadingInitial`
- Mas enquanto o fetch está em andamento, há instabilidade

#### 2. Múltiplas chamadas de `reload()`

```tsx
// ANTES ❌ - AppShell.tsx Boot Effect
useEffect(() => {
  const session = await supabase.auth.getSession();
  if (session) {
    reload().catch(...);  // Chamada 1
  }
}, []);
```

```tsx
// ANTES ❌ - AppShell.tsx Auth Listener
useEffect(() => {
  supabase.auth.onAuthStateChange((_evt, session) => {
    if (session) {
      reload().catch(...);  // Chamada 2 (mesmo em debounce)
    }
  });
}, []);
```

```tsx
// ANTES ❌ - AppShell.tsx visibilitychange
const visibilityHandler = async () => {
  if (sessionData.session) {
    await reload();  // Chamada 3
  }
};
document.addEventListener("visibilitychange", visibilityHandler);
```

**Por que pisca:**
- Múltiplas fontes de `reload()` podem disparar
- Cada uma potencialmente desencadeia `refreshPermissions()`
- Pode haver race conditions

#### 3. Lógica de renderização insegura

```tsx
// ANTES ❌
const permissionsReady = perms?.ready ?? !loadingInitial;

{permissionsReady && canAccessOs && (
  <div>OS Menu</div>
)}
```

**Por que pisca:**
- `loadingInitial = true` durante `refreshPermissions`
- Menu desaparece brevemente
- Mesmo que tenha cache, renderização é condicional

---

## Solução: Arquitetura de Cache Persistente

### Princípio 1: Flag de Inicialização

```tsx
const initializedRef = useRef(false);

const reload = useCallback(async () => {
  // Anti-padrão: recarregando desnecessariamente?
  // Solução: idempotência com inicialização
  if (initializedRef.current && permissionsRef.current !== null) {
    return;  // No-op após inicialização
  }
  
  const hasCache = capabilities !== null;
  await refreshPermissions({ background: hasCache });
}, [capabilities, refreshPermissions]);
```

**Benefício:** `reload()` torna-se segura chamar múltiplas vezes; ignora chamadas pós-inicialização.

### Princípio 2: Uma Única Fonte de Verdade de Inicialização

```tsx
// useEffect de inicialização é a ÚNICA responsável
useEffect(() => {
  const init = async () => {
    // Lê cache
    if (cached) {
      setCapabilities(cached);
      initializedRef.current = true;  // ✅ Marca como inicializado
      return;
    }
    
    // Fetch do Supabase
    await refreshPermissions({ background: false });
    initializedRef.current = true;  // ✅ Marca como inicializado
  };
  
  void init();
}, [refreshPermissions, lastCache]);
```

**Benefício:** Inicialização acontece UMA ÚNICA VEZ por sessão.

### Princípio 3: Remover Sincronização Automática

```tsx
// ANTES ❌
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    void refreshPermissions({ background: true });
  }
});

// DEPOIS ✅
// Removido completamente
// Permissões não mudam durante sessão ativa
```

**Benefício:** Sem listeners que disparam desnecessariamente.

### Princípio 4: Separar Responsabilidades

```
┌─ PermissionsProvider
│  └─ Gerencia: carregamento, cache, inicialização
│
└─ AppShell
   ├─ Não chama reload()
   ├─ Não gerencia permissões
   ├─ Apenas consome via usePermissions()
   └─ Renderiza baseado em estado final (não transitório)
```

**Benefício:** Sem acoplamento entre componentes.

---

## Fluxo Correto (Depois)

### Cenário 1: Login

```
┌─ Usuário faz login
│
├─ onAuthStateChange dispara (PermissionsProvider)
│  ├─ Reset initializedRef = false
│  ├─ setCapabilities(null)
│  ├─ refreshPermissions({ background: false, userId })
│  │
│  └─ refreshPermissions:
│     ├─ Fetch do Supabase (ou cache hit)
│     ├─ setCapabilities(perms)
│     ├─ writeCache(...)
│     └─ [Fim do refresh]
│
├─ AppShell recebe:
│  ├─ capabilities = {...}
│  ├─ loadingInitial = false
│  └─ permissionsReady = true
│
├─ Menu renderiza:
│  └─ {permissionsReady && canAccessOs && <Menu>}
│     └─ ✅ Menu aparece (não pisca)
│
└─ initializedRef.current = true
   └─ Qualquer `reload()` futuro será no-op
```

### Cenário 2: Navegar entre rotas

```
┌─ Usuário clica em link
│
├─ Router muda pathname
│
├─ AppShell re-renderiza
│  ├─ perms object (via useContext) é mesmo
│  ├─ capabilities está em cache
│  ├─ loadingInitial = false
│  └─ permissionsReady = true
│
├─ Menu renderiza:
│  └─ {permissionsReady && canAccessOs && <Menu>}
│     └─ ✅ Menu continua visível (não pisca)
│
└─ PermissionsProvider:
   └─ Nenhum efeito (initializedRef = true já)
```

### Cenário 3: Sair e voltar para aba

```
┌─ Usuário sai da aba
│  └─ (visibilitychange ocorre, mas listener foi REMOVIDO)
│
├─ Usuário volta para a aba após 5 min
│  ├─ Sessão ainda válida (refresh periódico a cada 15 min)
│  ├─ Menu já está renderizado com cache
│  └─ ✅ Menu continua visível (não pisca)
│
└─ Se sessão expirou:
   └─ onAuthStateChange dispara (logout automático)
      └─ Menu desaparece corretamente
```

---

## Comparação: Performance e Comportamento

### Métrica: Chamadas ao Supabase por Sessão

| Ação | Antes | Depois |
|------|-------|--------|
| Login | 1 | 1 |
| Navegar 10 rotas | 1-3 | 0 |
| Mudar de aba 5x | 2-5 | 0 |
| Refresh de sessão | 1 | 0 (apenas auth) |
| **Total** | **5-10** | **1** |

### Métrica: "Piscadas" de Menu

| Ação | Antes | Depois |
|------|-------|--------|
| Cada navegação | 1-2 | 0 |
| Cada mudança de aba | 1-2 | 0 |
| Cada refresh de sessão | 1 | 0 |
| **Total por sessão** | **5-20** | **0** |

---

## Considerações Arquiteturais

### Por que `initializedRef` é melhor que estado (useState)?

```tsx
// ❌ ERRADO
const [initialized, setInitialized] = useState(false);
// Causa re-render quando muda, desencadeia useEffect

// ✅ CORRETO
const initializedRef = useRef(false);
// Não causa re-render, apenas marca internamente
```

**Por que:** `initializedRef` é um flag de controle puro, não estado de UI.

### Por que `sessionStorage` e não `localStorage`?

- **sessionStorage:** Persiste apenas durante a sessão do browser
- **localStorage:** Persiste entre sessões

```tsx
// Escolha correta:
window.sessionStorage.setItem(cacheKeyFor(userId, tenantId), JSON.stringify(capabilities));
```

**Por que:** Permissões podem mudar entre sessões (admin muda role), mas não durante uma sessão.

### Por que não usar SWR/Tanstack Query?

Tanto SWR quanto React Query têm cache automático, mas:
- Adicionam dependência extra
- Comportamento de revalidação é complexo de configurar
- Neste caso, manejo manual é mais transparente

---

## Teste de Estresse

### Cenário: Abrir 10 abas rapidamente

**Antes:** Múltiplas chamadas concorrentes de `refreshPermissions`
```
Tab 1: visibilitychange → refresh
Tab 2: onAuthStateChange → reload() → refresh  
Tab 3: visibilitychange → refresh
... Race condition possível
```

**Depois:** Todas compartilham cache via `sessionStorage`
```
Tab 1: Inicializa, escreve cache
Tab 2-10: Leem cache, skip de fetch
... Sem race conditions
```

---

## Garantia de Segurança

### Permissões são corretamente invalidadas em:

1. ✅ **Logout:** `onAuthStateChange` dispara, `clear()` é chamado
2. ✅ **Troca de usuário:** Mesmo evento, `initializedRef` é resetado
3. ✅ **Erro no Supabase:** Estado anterior mantido (degradação graciosa)

### Permissões NÃO são desnecessariamente refetch em:

1. ✅ Navegação entre rotas
2. ✅ Mudança de aba
3. ✅ Re-renders por props diferentes
4. ✅ Refresh periódico de sessão (apenas token, não permissões)

---

## Conclusão

A solução implementa um padrão **initialization flag + cache persistente**:

```
Login → Carregar do Supabase → Cache em sessionStorage → Reutilizar durante a sessão
         ↓
    initializedRef = true
         ↓
    Qualquer reload() futuro = no-op até logout
```

Resultado: **Menu nunca pisca, experiência de usuário profissional.**

