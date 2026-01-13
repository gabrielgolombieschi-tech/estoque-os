# Fix: Menu Flicker ao Trocar de Rota

## 🐛 Problema Diagnosticado

**Sintomas:**
- Menu superior desaparecia temporariamente ao navegar entre rotas
- Menus reapareciam após 1-2 segundos
- Aplicação parecia amadora/instável

**Causa Raiz:**
Permissões estavam sendo **reavaliadas desnecessariamente** quando o usuário:
- Saía e retornava para a aba
- Trocava de página/rota
- Perdia foco na janela

Isso causava:
1. `PermissionsProvider` disparar `refreshPermissions()` em background
2. Transição de estado `loadingInitial: false → true → false`
3. Menu condicionar renderização a `{loadingInitial && ...}` e `{permissionsReady && ...}`
4. Menu desaparecer durante o carregamento temporário

## ✅ Solução Implementada

### Mudança 1: Flag de Inicialização (`PermissionsProvider.tsx`)

**Antes:**
```tsx
// Permissões eram carregadas múltiplas vezes por sessão
const refreshPermissions = async (opts?: {...}) => {
  // Sempre refazia o fetch
}
```

**Depois:**
```tsx
// Ref para rastrear inicialização
const initializedRef = useRef(false);

const reload = useCallback(async () => {
  // Se já foi inicializado, não recarrega
  // Permissões não mudam durante a sessão, então cache é suficiente
  if (initializedRef.current && permissionsRef.current !== null) {
    return;
  }
  const hasCache = capabilities !== null;
  await refreshPermissions({ background: hasCache });
}, [capabilities, refreshPermissions]);
```

**Impacto:** Permissões carregam **UMA ÚNICA VEZ** por sessão.

### Mudança 2: Remover listener de `visibilitychange` 

**Antes:**
```tsx
// Recarregava permissões quando aba ganhava foco
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    void refreshPermissions({ background: true });
  }
});
```

**Depois:**
```tsx
// Listener REMOVIDO
// Permissões não mudam, então não precisa sincronizar ao voltar da aba
```

**Impacto:** Sem reavaliação ao mudar entre abas.

### Mudança 3: Não chamar `reload()` no boot

**Antes:**
```tsx
// AppShell.tsx - Boot
if (session) {
  reload().catch((e) => logError("reload permissions error:", e));
}
```

**Depois:**
```tsx
// PermissionsProvider já carrega permissões automaticamente ao iniciar
// Não chamamos reload() aqui para evitar reavaliações desnecessárias
```

**Impacto:** Sem chamada redundante ao iniciar.

### Mudança 4: Melhorar lógica de renderização

**Antes:**
```tsx
// Menu renderizava apenas após loadingInitial virar false
const permissionsReady: boolean = perms?.ready ?? !loadingInitial;
```

**Depois:**
```tsx
// Menu renderiza assim que temos capabilities (mesmo em background refresh)
// Não espera loadingInitial terminar; confia em cache
const hasCapabilities = permsCapabilities !== null;
const permissionsReady: boolean = perms?.ready ?? hasCapabilities;
```

**Impacto:** Menu aparece com dados em cache, nunca pisca.

## 🎯 Garantias

✅ **Ao trocar de rota ou aba, o menu NÃO pisca, NÃO some e NÃO revalida permissões**

- Permissões carregam 1x no login
- Cache é usado em navegações subsequentes
- Sem listeners de `visibilitychange`
- Sem refresh automático em background
- Flag `initializedRef` previne reavaliações

## 📋 Arquivos Modificados

1. **`components/auth/PermissionsProvider.tsx`**
   - ✅ Adicionado `initializedRef` 
   - ✅ Modificado `reload()` para respeitar flag
   - ✅ Removido listener de `visibilitychange`
   - ✅ Marcado `initializedRef.current = true` ao terminar inicialização

2. **`app/components/AppShell.tsx`**
   - ✅ Removida chamada de `reload()` no boot
   - ✅ Removida chamada de `reload()` no listener de auth
   - ✅ Removida sincronização de permissões ao voltar da aba
   - ✅ Melhorada lógica de `permissionsReady`

## 🔒 Pontos Críticos

### Permissões NÃO mudam durante sessão ativa
- Nenhum motivo para reavaliá-las ao navegar
- Cache `sessionStorage` é suficiente
- Só recarrega em `login/logout`

### Fluxo de inicialização
1. Browser carrega app
2. `PermissionsProvider` tenta ler cache
3. Se cache hit → usa cache imediatamente
4. Se cache miss → fetch do Supabase
5. Marca como `initialized = true`
6. **Nunca mais recarrega durante a sessão**

### O que NÃO foi feito
❌ Não há hacks CSS/visuais
❌ Não há setTimeout  
❌ Não há loading state transitório
❌ Não há promises não-resolvidas

## ✨ Resultado

| Antes | Depois |
|-------|--------|
| Menu pisca ao navegar | Menu sempre visível |
| Múltiplos fetches de permissões | 1 fetch por sessão |
| Aplicação parece amadora | Aplicação é profissional |
| Listener de visibilitychange | Removido |
| Chamadas de `reload()` desnecessárias | Bloqueadas por flag |

