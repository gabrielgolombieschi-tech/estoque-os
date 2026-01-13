# 🎨 Menu Flicker Fix - Diagrama de Fluxo

## Antes vs Depois

### ANTES ❌ (Problema: Menu Pisca)

```
┌─────────────────────────────────────────────────────────────────┐
│                         USUÁRIO NAVEGA                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Router muda    │
                    │  pathname       │
                    └────────┬────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼─────────┐       │       ┌────────▼──────────┐
    │ visibilitychange│       │       │ Reload desnecessário
    │ listener ativa │       │       │ (AppShell + Auth) │
    │ (random evento)│       │       └────────┬──────────┘
    └──────┬─────────┘       │                 │
           │                 │                 │
           └─────────────────┼─────────────────┘
                             │
                    ┌────────▼────────┐
                    │ refreshPermissions
                    │({ background }) │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
      ┌─────▼──────┐  ┌──────▼────┐  ┌──────▼───────┐
      │ setLoading  │  │ setRefresh │  │ Fetch RPC   │
      │(true/false) │  │ (true/false)│  │ can_many    │
      └─────┬──────┘  └──────┬────┘  └──────┬───────┘
            │                │              │
            │                │              │
      ┌─────▼─────────────────▼──────────────▼────────┐
      │   loadingInitial = true                       │
      │   (Menu perde condição: permissionsReady)     │
      └─────┬────────────────────────────────────────┘
            │
      ┌─────▼──────────────────┐
      │  {loadingInitial && "Carregando..."}
      │  Menu DESAPARECE! 👁️ PISCA
      └─────┬──────────────────┘
            │
      ┌─────▼──────────────────┐
      │ RPC completa           │
      │ setCapabilities(data)  │
      │ loadingInitial = false │
      └─────┬──────────────────┘
            │
      ┌─────▼──────────────────┐
      │ Menu REAPARECE! 👁️ PISCA
      │ {permissionsReady && Menu}
      └───────────────────────┘

RESULTADO: Menu pisca 500-1000ms a cada navegação
```

---

### DEPOIS ✅ (Solução: Menu Estável)

```
┌─────────────────────────────────────────────────────────────────┐
│                         USUÁRIO NAVEGA                           │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │  Router muda    │
                    │  pathname       │
                    └────────┬────────┘
                             │
                    ┌────────▼────────────────┐
                    │ PermissionsProvider     │
                    │ useState não muda       │
                    │ useContext same ref     │
                    └────────┬────────────────┘
                             │
                    ┌────────▼────────┐
                    │ AppShell checa:  │
                    │ initializedRef?  │
                    │ -> true          │
                    └────────┬────────┘
                             │
                    ┌────────▼────────────────────┐
                    │ reload() chamado (se fosse)  │
                    │ mas é no-op:                 │
                    │ if (initializedRef &&       │
                    │     capabilities !== null)  │
                    │   return;  ← EXIT EARLY     │
                    └────────┬────────────────────┘
                             │
                    ┌────────▼────────┐
                    │ Nenhuma mudança │
                    │ de estado       │
                    │ capabilities ok │
                    │ loadingInitial  │
                    │ sempre false    │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Menu renderiza: │
                    │ {permissionsReady
                    │  && canAccess... │
                    │ Menu CONTINUA   │
                    │ VISÍVEL! ✅      │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │ Navegação OK    │
                    │ SEM PISCAR! 🎯  │
                    └─────────────────┘

RESULTADO: Menu nunca pisca, sempre visível durante navegação
```

---

## Fluxo de Inicialização

### 1️⃣ PRIMEIRO LOGIN (Sem Cache)

```
┌─────────────────────────────┐
│ Usuário faz login           │
│ onAuthStateChange dispara   │
└────────────┬────────────────┘
             │
    ┌────────▼────────┐
    │ initializedRef  │
    │ = false         │
    │ (reset)         │
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │ Tenta ler cache │
    │ sessionStorage  │
    └────────┬────────┘
             │
         ❌ MISS
             │
    ┌────────▼────────────────┐
    │ Fetch do Supabase       │
    │ RPC can_many            │
    │ (PRIMEIRA E ÚNICA vez)  │
    └────────┬────────────────┘
             │
    ┌────────▼────────┐
    │ setCapabilities │
    │ writeCache      │
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │ initializedRef  │
    │ = true          │
    │ MARCADO! ✅     │
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │ Menu renderiza  │
    │ com dados       │
    └─────────────────┘
```

### 2️⃣ NAVEGAÇÃO APÓS LOGIN (Com Cache)

```
┌──────────────────────────┐
│ Usuário navega rota      │
│ (pathname muda)          │
└────────┬─────────────────┘
         │
    ┌────▼──────────────┐
    │ reload() chamado? │
    │ (não é)           │
    │ PermsProvider NOT │
    │ disparado         │
    └────┬──────────────┘
         │
    ┌────▼──────────────────────┐
    │ Menu renderiza com cache  │
    │ capabilities já carregadas│
    │ loadingInitial = false    │
    │ (NUNCA muda)              │
    └────┬──────────────────────┘
         │
    ┌────▼──────────────┐
    │ Menu SEMPRE       │
    │ VISÍVEL ✅        │
    │ NÃO PISCA! 🎯     │
    └───────────────────┘
```

### 3️⃣ LOGOUT (Reset)

```
┌─────────────────────────────┐
│ Usuário clica em "Sair"     │
│ supabase.auth.signOut()     │
└────────┬────────────────────┘
         │
    ┌────▼──────────────────┐
    │ onAuthStateChange     │
    │ (logout event)        │
    └────┬──────────────────┘
         │
    ┌────▼──────────────────┐
    │ initializedRef = false│
    │ (reset)               │
    │ setCapabilities(null) │
    │ clearCache()          │
    └────┬──────────────────┘
         │
    ┌────▼──────────────────┐
    │ Menu desaparece       │
    │ {permissionsReady &&} │
    │ -> false              │
    └────┬──────────────────┘
         │
    ┌────▼──────────────────┐
    │ Redireciona /login    │
    │ Comportamento OK ✅   │
    └──────────────────────┘
```

---

## Comparação de Chamadas

### Antes ❌

```
┌─────────────────────────────────────────┐
│ SESSÃO TÍPICA: 5-10 CHAMADAS            │
├─────────────────────────────────────────┤
│ 1. Login                    → Fetch 1    │
│ 2. Boot de AppShell         → Fetch 2   │
│ 3. Auth listener            → Fetch 3   │
│ 4. Navegar rota 1           → Cache     │
│ 5. visibilitychange (aba 1) → Fetch 4   │
│ 6. visibilitychange (aba 2) → Fetch 5   │
│ 7. Navegar rota 2           → Cache     │
│ 8. visibilitychange (volta) → Fetch 6   │
│ ... mais navegações/abas     → Fetch+    │
└─────────────────────────────────────────┘
TOTAL: 6+ chamadas ao Supabase por sessão ❌
```

### Depois ✅

```
┌─────────────────────────────────────────┐
│ MESMA SESSÃO TÍPICA: 1 CHAMADA          │
├─────────────────────────────────────────┤
│ 1. Login                    → Fetch 1    │
│ 2. Boot de AppShell         → no-op      │
│ 3. Auth listener            → no-op      │
│ 4. Navegar rota 1           → Cache      │
│ 5. visibilitychange         → REMOVIDO   │
│ 6. visibilitychange         → REMOVIDO   │
│ 7. Navegar rota 2           → Cache      │
│ 8. visibilitychange         → REMOVIDO   │
│ ... mais navegações/abas    → Cache      │
└─────────────────────────────────────────┘
TOTAL: 1 chamada ao Supabase por sessão ✅
```

---

## Estados Possíveis

### PermissionsProvider State Machine

```
         ┌─────────────────┐
         │ INITIAL STATE   │
         │ capabilities=null
         │ loading=true    │
         │ initialized=false
         └────────┬────────┘
                  │
        ┌─────────▼─────────┐
        │  TRY READ CACHE   │
        └─────┬──────────┬──┘
              │          │
          ✅ HIT         ❌ MISS
              │          │
    ┌─────────▼───┐  ┌────▼─────────┐
    │ setCapabilit│  │ Fetch RPC     │
    │ from cache  │  │ can_many      │
    │ loading=false   │ from Supabase │
    │ init=true   │  └────┬──────────┘
    └─────┬───────┘       │
          │         ┌──────▼──────┐
          │         │ setCapabilitie
          │         │ from RPC     │
          │         │ writeCache   │
          │         │ init=true    │
          │         └──────┬───────┘
          │                │
          └────┬───────────┘
               │
        ┌──────▼──────────┐
        │ READY STATE     │
        │ capabilities!=null
        │ loading=false   │
        │ initialized=true
        │ (STABLE!)       │
        └────────┬────────┘
                 │
    ┌────────────▼────────────┐
    │ reload() = no-op        │
    │ (until logout)          │
    └────────┬─────────────────┘
             │
        ┌────▼────────────┐
        │ LOGOUT          │
        │ reset + go/login│
        └─────────────────┘
```

---

## Impacto Visual

### User Experience Timeline

```
ANTES ❌
├─ T=0ms   Login ✅
├─ T=100ms Menu aparece (cache)
├─ T=150ms [visibilitychange] ↓ PISCA
├─ T=160ms Menu desaparece ❌
├─ T=500ms RPC complete
├─ T=550ms Menu reaparece ✅
├─ T=600ms [Navega rota]
├─ T=650ms Menu pisca NOVAMENTE ❌
└─ T=1000ms Menu volta ✅

PERCEPÇÃO DO USUÁRIO: "App é instável" 😞

DEPOIS ✅
├─ T=0ms   Login ✅
├─ T=100ms Menu aparece (cache)
├─ T=150ms [visibilitychange] listener REMOVIDO
├─ T=160ms Menu continua visível ✅
├─ T=500ms RPC complete, nada muda
├─ T=550ms Menu ainda visível ✅
├─ T=600ms [Navega rota]
├─ T=650ms Menu continua visível ✅
└─ T=1000ms Menu permanece ✅

PERCEPÇÃO DO USUÁRIO: "App é profissional" 🎉
```

---

## Resumo Visual

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│  ANTES                          DEPOIS                   │
│  ━━━━━━                         ━━━━━━                   │
│                                                          │
│  Menu pisca ❌              Menu sempre visível ✅       │
│  5-10 RPC calls            1 RPC call per session      │
│  Multiple reload() calls    No-op reload()              │
│  visibilitychange listener  No listener                 │
│  Complex state management   Simple: initialized flag    │
│  User perception: Amateur   User perception: Pro 🎉      │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

