# Gestão de Vínculos Colaboradores × Cliente × Função HH

## 📋 Visão Geral

Tela para gerenciar vínculos entre **colaboradores**, **clientes** e **funções/serviços HH** (Hora-Homem).

## 🎯 Objetivo

Permitir que administradores e coordenadores configurem quais colaboradores prestam quais serviços HH para cada cliente específico.

## 📍 Localização

**Rota**: `/cadastros/hh/colaboradores-cliente`

**Menu**: Cadastros → Contratos HH → Colaboradores × Cliente

## 🔐 Permissões

### Leitura (visualizar):
- `admin.manage_users` OU
- `financeiro.read` OU  
- `apontamentos.read`

### Escrita (criar/editar/excluir):
- `admin.manage_users` OU
- `financeiro.read`

## 🗂️ Estrutura de Dados

### Tabela Principal: `colaborador_cliente_funcao`

```sql
CREATE TABLE public.colaborador_cliente_funcao (
  id bigint PRIMARY KEY,
  tenant_id uuid NOT NULL,
  cliente_id bigint NOT NULL,
  colaborador_id uuid NOT NULL,
  hh_servico_id bigint NOT NULL,
  ativo boolean NOT NULL DEFAULT true,
  criado_em timestamp,
  atualizado_em timestamp,
  criado_por text,
  
  CONSTRAINT unique_colab_cliente_funcao 
    UNIQUE (tenant_id, cliente_id, colaborador_id, hh_servico_id),
  
  CONSTRAINT fk_colaborador_cliente_funcao_cliente 
    FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE,
  
  CONSTRAINT fk_colaborador_cliente_funcao_colaborador 
    FOREIGN KEY (colaborador_id) REFERENCES colaboradores(id) ON DELETE CASCADE,
  
  CONSTRAINT fk_colaborador_cliente_funcao_servico 
    FOREIGN KEY (hh_servico_id) REFERENCES cliente_hh_servicos(id) ON DELETE CASCADE
);
```

### Relacionamentos

```
colaborador_cliente_funcao
├── tenant_id → multi-tenant
├── cliente_id → clientes (com habilita_hh = true)
├── colaborador_id → colaboradores (ativos)
└── hh_servico_id → cliente_hh_servicos (serviços HH do cliente)
```

## 🔄 Fluxo de Uso

### 1️⃣ Pré-requisitos

Antes de vincular colaboradores, certifique-se de:

1. **Cliente habilitado para HH**:
   - Ir em `/clientes`
   - Editar o cliente
   - Marcar "Habilitar serviços de Hora-Homem (HH)"
   - Salvar

2. **Serviços HH cadastrados para o cliente**:
   - Ir em `/cadastros/hh/servicos-cliente`
   - Selecionar o cliente
   - Cadastrar serviços (Eletricista, Programador, etc.)

3. **Colaboradores cadastrados**:
   - Ir em `/colaboradores`
   - Cadastrar colaboradores
   - Marcar como "Ativo"

### 2️⃣ Criar Vínculo

1. Acessar `/cadastros/hh/colaboradores-cliente`
2. Selecionar um **Cliente** (apenas clientes com HH habilitado aparecem)
3. Clicar em **"+ Novo Vínculo"**
4. No modal:
   - Selecionar **Colaborador**
   - Selecionar **Função/Serviço HH**
   - Marcar/desmarcar **Ativo**
5. Clicar em **"Salvar"**

### 3️⃣ Editar Vínculo

1. Na lista de vínculos, clicar em **"Editar"**
2. Alterar colaborador, serviço ou status
3. Salvar

### 4️⃣ Desativar/Ativar Vínculo

- Clicar em **"Desativar"** para soft delete (mantém histórico)
- Clicar em **"Ativar"** para reativar

### 5️⃣ Excluir Vínculo

- Clicar em **"Excluir"**
- Confirmar (soft delete: apenas marca `ativo = false`)

## 🛡️ Regras de Negócio

### ✅ Validações

1. **Não duplicar vínculos**: constraint `unique_colab_cliente_funcao` impede vincular o mesmo colaborador ao mesmo serviço do mesmo cliente mais de uma vez.

2. **Cliente deve ter HH habilitado**: filtro mostra apenas clientes com `habilita_hh = true`.

3. **Cliente deve ter serviços HH**: se não tiver, mostra link para cadastrar.

4. **Colaborador deve estar ativo**: apenas colaboradores ativos aparecem.

5. **Multi-tenant**: sempre filtra por `tenant_id` atual.

### 🔒 Soft Delete

- **Excluir** = marca `ativo = false` (mantém histórico)
- Vínculos inativos aparecem na lista com opacidade reduzida
- Podem ser reativados

## 🎨 Interface

### Tabela de Vínculos

| Colaborador | Função / Serviço HH | Status | Ações |
|-------------|---------------------|--------|-------|
| João Silva | Eletricista | Ativo | Editar • Desativar • Excluir |
| Maria Santos | Programador PLC | Inativo | Editar • Ativar • Excluir |

### Modal Criar/Editar

- **Colaborador** (select)
- **Função/Serviço HH** (select, mostra preço base)
- **Ativo** (checkbox)
- Botões: Cancelar | Salvar

## 🔧 Migration Aplicada

Arquivo: `supabase/migrations/20260114_colaborador_cliente_funcao_constraints.sql`

**Conteúdo**:
- Foreign Keys (cliente, colaborador, servico)
- Constraint UNIQUE
- Índices para performance
- Trigger `atualizado_em` automático
- RLS Policies (SELECT, INSERT, UPDATE, DELETE)

**Aplicar**:
```bash
npm run db:migrate
```

## 📊 Casos de Uso

### Caso 1: Cliente XPTO com múltiplos colaboradores

**Cenário**: Cliente XPTO contrata 5 eletricistas e 3 programadores.

**Ação**:
1. Selecionar cliente XPTO
2. Criar 5 vínculos: colaboradores → serviço "Eletricista"
3. Criar 3 vínculos: colaboradores → serviço "Programador PLC"

**Resultado**: 8 vínculos ativos.

### Caso 2: Colaborador atua em múltiplos clientes

**Cenário**: João Silva é eletricista para Cliente A e Cliente B.

**Ação**:
1. Selecionar Cliente A → criar vínculo João Silva × Eletricista
2. Selecionar Cliente B → criar vínculo João Silva × Eletricista

**Resultado**: 2 vínculos independentes.

### Caso 3: Alteração de função

**Cenário**: Maria foi promovida de "Eletricista Jr" para "Eletricista Sênior".

**Ação**:
1. Editar vínculo de Maria
2. Trocar serviço de "Eletricista Jr" para "Eletricista Sênior"
3. Salvar

**Resultado**: histórico mantido (auditoria via `atualizado_em`).

## 🔗 Integração com HH Reports

Os vínculos criados aqui são usados em:

1. **Lançamento de Horas** (`/os/[id]` → aba "Relatório HH"):
   - Ao lançar horas, sistema valida se colaborador está vinculado ao serviço do cliente
   - Valor hora aplicado vem de `cliente_hh_servicos` (preco_base/50/100)

2. **Relatórios HH**:
   - Consulta `colaborador_cliente_funcao` para validar permissões
   - Agrupa horas por colaborador e serviço

## ⚠️ Troubleshooting

### Erro: "Este colaborador já está vinculado a este serviço neste cliente"

**Causa**: constraint `unique_colab_cliente_funcao`

**Solução**: já existe um vínculo (ativo ou inativo). Verificar lista e editar/ativar o existente.

### Cliente não aparece no filtro

**Causa**: `habilita_hh = false`

**Solução**: ir em `/clientes`, editar e marcar "Habilitar serviços de Hora-Homem (HH)".

### "Cliente não possui serviços HH cadastrados"

**Causa**: sem registros em `cliente_hh_servicos`

**Solução**: clicar no link → ir para `/cadastros/hh/servicos-cliente` e cadastrar.

### Vínculo criado mas não aparece em lançamento HH

**Causa**: `ativo = false` OU serviço inativo

**Solução**: verificar status do vínculo e do serviço.

## 📝 Logs & Auditoria

- **criado_em**: data/hora criação
- **atualizado_em**: atualizado automaticamente (trigger)
- **criado_por**: email do usuário que criou
- **ativo**: flag para soft delete

Consulta histórico:
```sql
SELECT * FROM colaborador_cliente_funcao 
WHERE cliente_id = ? 
ORDER BY atualizado_em DESC;
```

## 🚀 Melhorias Futuras

- [ ] Filtro por colaborador na lista
- [ ] Filtro por status (ativo/inativo)
- [ ] Bulk import (CSV)
- [ ] Cópia de vínculos entre clientes
- [ ] Dashboard: colaboradores sem vínculo ativo
- [ ] Histórico de alterações (tabela de audit)

---

**Última atualização**: 2026-01-14  
**Responsável**: Sistema HH - Gestão de Hora-Homem
