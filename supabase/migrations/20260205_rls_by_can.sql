BEGIN;
-- Drop existing policies for OS tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.ordens_servico') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='ordens_servico' LOOP
      EXECUTE format('drop policy if exists %I on public.ordens_servico', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.os_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='os_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.os_itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.os_gestao_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='os_gestao_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.os_gestao_itens', r.policyname);
    END LOOP;
  END IF;
END$$;
ALTER TABLE public.ordens_servico ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.os_gestao_itens ENABLE ROW LEVEL SECURITY;
CREATE POLICY ordens_servico_select
ON public.ordens_servico
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os','read')
);
CREATE POLICY ordens_servico_insert
ON public.ordens_servico
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os','write')
);
CREATE POLICY ordens_servico_update
ON public.ordens_servico
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os','write')
);
CREATE POLICY ordens_servico_delete
ON public.ordens_servico
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os','delete')
);
CREATE POLICY os_itens_select
ON public.os_itens
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os','read')
);
CREATE POLICY os_itens_insert
ON public.os_itens
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os_itens','write')
);
CREATE POLICY os_itens_update
ON public.os_itens
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os_itens','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os_itens','write')
);
CREATE POLICY os_itens_delete
ON public.os_itens
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os_itens','write')
);
CREATE POLICY os_gestao_itens_select
ON public.os_gestao_itens
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os','read')
);
CREATE POLICY os_gestao_itens_insert
ON public.os_gestao_itens
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os_gestao','write')
);
CREATE POLICY os_gestao_itens_update
ON public.os_gestao_itens
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os_gestao','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('os_gestao','write')
);
CREATE POLICY os_gestao_itens_delete
ON public.os_gestao_itens
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('os_gestao','write')
);
-- Drop existing policies for estoque/cadastros tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='itens' LOOP
      EXECUTE format('drop policy if exists %I on public.itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.fornecedores') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='fornecedores' LOOP
      EXECUTE format('drop policy if exists %I on public.fornecedores', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.clientes') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='clientes' LOOP
      EXECUTE format('drop policy if exists %I on public.clientes', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.estoque') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='estoque' LOOP
      EXECUTE format('drop policy if exists %I on public.estoque', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.movimentacoes') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='movimentacoes' LOOP
      EXECUTE format('drop policy if exists %I on public.movimentacoes', r.policyname);
    END LOOP;
  END IF;
END$$;
ALTER TABLE public.itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimentacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY itens_select
ON public.itens
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('estoque','read')
    OR public.can('os','read')
    OR public.can('cad_itens','write')
  )
);
CREATE POLICY itens_insert
ON public.itens
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_itens','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY itens_update
ON public.itens
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_itens','write')
    OR public.can('estoque','write')
  )
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_itens','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY itens_delete
ON public.itens
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_itens','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY fornecedores_select
ON public.fornecedores
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('estoque','read')
    OR public.can('cad_fornecedores','write')
  )
);
CREATE POLICY fornecedores_insert
ON public.fornecedores
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_fornecedores','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY fornecedores_update
ON public.fornecedores
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_fornecedores','write')
    OR public.can('estoque','write')
  )
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_fornecedores','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY fornecedores_delete
ON public.fornecedores
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('cad_fornecedores','write')
    OR public.can('estoque','write')
  )
);
CREATE POLICY clientes_select
ON public.clientes
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND (
    public.can('os','read')
    OR public.can('cad_clientes','write')
  )
);
CREATE POLICY clientes_insert
ON public.clientes
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('cad_clientes','write')
);
CREATE POLICY clientes_update
ON public.clientes
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('cad_clientes','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('cad_clientes','write')
);
CREATE POLICY clientes_delete
ON public.clientes
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('cad_clientes','write')
);
CREATE POLICY estoque_select
ON public.estoque
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','read')
);
CREATE POLICY estoque_insert
ON public.estoque
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
CREATE POLICY estoque_update
ON public.estoque
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
CREATE POLICY estoque_delete
ON public.estoque
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
CREATE POLICY movimentacoes_select
ON public.movimentacoes
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','read')
);
CREATE POLICY movimentacoes_insert
ON public.movimentacoes
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
CREATE POLICY movimentacoes_update
ON public.movimentacoes
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
CREATE POLICY movimentacoes_delete
ON public.movimentacoes
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('estoque','write')
);
-- Drop existing policies for fiscal/xml tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.nf_entrada') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='nf_entrada' LOOP
      EXECUTE format('drop policy if exists %I on public.nf_entrada', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.nf_entrada_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='nf_entrada_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.nf_entrada_itens', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.fiscal_itens') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='fiscal_itens' LOOP
      EXECUTE format('drop policy if exists %I on public.fiscal_itens', r.policyname);
    END LOOP;
  END IF;
END$$;
ALTER TABLE public.nf_entrada ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nf_entrada_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_itens ENABLE ROW LEVEL SECURITY;
CREATE POLICY nf_entrada_select
ON public.nf_entrada
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','read')
);
CREATE POLICY nf_entrada_insert
ON public.nf_entrada
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
);
CREATE POLICY nf_entrada_update
ON public.nf_entrada
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
);
CREATE POLICY nf_entrada_delete
ON public.nf_entrada
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','delete')
);
CREATE POLICY nf_entrada_itens_select
ON public.nf_entrada_itens
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','read')
);
CREATE POLICY nf_entrada_itens_insert
ON public.nf_entrada_itens
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
);
CREATE POLICY nf_entrada_itens_update
ON public.nf_entrada_itens
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','write')
);
CREATE POLICY nf_entrada_itens_delete
ON public.nf_entrada_itens
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('fiscal_nf','delete')
);
CREATE POLICY fiscal_itens_select
ON public.fiscal_itens
FOR SELECT
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND (
    public.can('fiscal_nf','read')
    OR public.can('fiscal_itens','write')
  )
);
CREATE POLICY fiscal_itens_insert
ON public.fiscal_itens
FOR INSERT
TO authenticated
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_itens','write')
);
CREATE POLICY fiscal_itens_update
ON public.fiscal_itens
FOR UPDATE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_itens','write')
)
WITH CHECK (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_itens','write')
);
CREATE POLICY fiscal_itens_delete
ON public.fiscal_itens
FOR DELETE
TO authenticated
USING (
  empresa_id IS NOT NULL
  AND tenant_id = public.current_tenant_id()
  AND public.can('fiscal_itens','write')
);
-- Drop existing policies for financeiro tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.financeiro_titulos') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='financeiro_titulos' LOOP
      EXECUTE format('drop policy if exists %I on public.financeiro_titulos', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.financeiro_categorias') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='financeiro_categorias' LOOP
      EXECUTE format('drop policy if exists %I on public.financeiro_categorias', r.policyname);
    END LOOP;
  END IF;
END$$;
ALTER TABLE public.financeiro_titulos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financeiro_categorias ENABLE ROW LEVEL SECURITY;
CREATE POLICY financeiro_titulos_select
ON public.financeiro_titulos
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','read')
);
CREATE POLICY financeiro_titulos_insert
ON public.financeiro_titulos
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','write')
);
CREATE POLICY financeiro_titulos_update
ON public.financeiro_titulos
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','write')
);
CREATE POLICY financeiro_titulos_delete
ON public.financeiro_titulos
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','delete')
);
CREATE POLICY financeiro_categorias_select
ON public.financeiro_categorias
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','read')
);
CREATE POLICY financeiro_categorias_insert
ON public.financeiro_categorias
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','config')
);
CREATE POLICY financeiro_categorias_update
ON public.financeiro_categorias
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','config')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','config')
);
CREATE POLICY financeiro_categorias_delete
ON public.financeiro_categorias
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('financeiro','config')
);
-- Drop existing policies for apontamentos tables
DO $$
DECLARE r record;
BEGIN
  IF to_regclass('public.apontamentos_horas') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='apontamentos_horas' LOOP
      EXECUTE format('drop policy if exists %I on public.apontamentos_horas', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.colaboradores') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='colaboradores' LOOP
      EXECUTE format('drop policy if exists %I on public.colaboradores', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.tipos_horas') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='tipos_horas' LOOP
      EXECUTE format('drop policy if exists %I on public.tipos_horas', r.policyname);
    END LOOP;
  END IF;
  IF to_regclass('public.colaborador_taxas') IS NOT NULL THEN
    FOR r IN SELECT policyname FROM pg_policies WHERE schemaname='public' AND tablename='colaborador_taxas' LOOP
      EXECUTE format('drop policy if exists %I on public.colaborador_taxas', r.policyname);
    END LOOP;
  END IF;
END$$;
ALTER TABLE public.apontamentos_horas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaboradores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tipos_horas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.colaborador_taxas ENABLE ROW LEVEL SECURITY;
CREATE POLICY apontamentos_select
ON public.apontamentos_horas
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','read')
);
CREATE POLICY apontamentos_insert
ON public.apontamentos_horas
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','write')
);
CREATE POLICY apontamentos_update
ON public.apontamentos_horas
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','write')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','write')
);
CREATE POLICY apontamentos_delete
ON public.apontamentos_horas
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','delete')
);
CREATE POLICY colaboradores_select
ON public.colaboradores
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','read')
);
CREATE POLICY colaboradores_insert
ON public.colaboradores
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY colaboradores_update
ON public.colaboradores
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY colaboradores_delete
ON public.colaboradores
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY tipos_horas_select
ON public.tipos_horas
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','read')
);
CREATE POLICY tipos_horas_insert
ON public.tipos_horas
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY tipos_horas_update
ON public.tipos_horas
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY tipos_horas_delete
ON public.tipos_horas
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY colaborador_taxas_select
ON public.colaborador_taxas
FOR SELECT
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','read')
);
CREATE POLICY colaborador_taxas_insert
ON public.colaborador_taxas
FOR INSERT
TO authenticated
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY colaborador_taxas_update
ON public.colaborador_taxas
FOR UPDATE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
)
WITH CHECK (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
CREATE POLICY colaborador_taxas_delete
ON public.colaborador_taxas
FOR DELETE
TO authenticated
USING (
  tenant_id = public.current_tenant_id()
  AND public.can('apontamentos','config')
);
-- RPC guards using can()
CREATE OR REPLACE FUNCTION public.import_nf_entrada(
  p_empresa_id uuid,
  p_finalidade_contexto public.item_finalidade,
  p_fornecedor_id bigint,
  p_itens_json jsonb,
  p_nf_json jsonb,
  p_tenant_id uuid,
  p_xml_raw text,
  p_gerar_contas_pagar boolean default false,
  p_parcelas_json jsonb default null,
  p_os_id integer default null,
  p_baixar_os boolean default false
) returns table(status text, message text, nf_entrada_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nf_id bigint;
  v_chave text;
  v_emitente text;
  v_numero text;
  v_serie text;
  v_data_emissao timestamptz;
  v_total_nf numeric(14,2);
  v_soma_parcelas numeric(14,2);

  v_categoria_id uuid;
  v_parcelamento_id uuid;

  v_it jsonb;

  v_item_id int;
  v_qtd numeric(14,3);
  v_vunit numeric(14,6);
  v_vtotal numeric(14,2);

  v_has_os boolean;
begin
  if auth.uid() is null then
    raise exception 'Usuario nao autenticado';
  end if;

  if p_tenant_id is null then
    raise exception 'tenant_id obrigatorio';
  end if;

  perform set_config('app.tenant_id', p_tenant_id::text, true);

  if not exists (
    select 1
    from public.tenant_memberships tm
    where tm.user_id = auth.uid()
      and tm.tenant_id = p_tenant_id
      and tm.status in ('active','ativo')
  ) then
    raise exception 'Tenant nao autorizado';
  end if;

  if not public.can('xml_import','execute') then
    raise exception 'Sem permissao para importar XML';
  end if;

  if p_nf_json is null then
    raise exception 'p_nf_json e obrigatorio';
  end if;

  v_chave := nullif(trim(p_nf_json->>'chave'), '');
  if v_chave is null then
    raise exception 'NF sem chave (p_nf_json.chave)';
  end if;

  -- Ja existe?
  select id into v_nf_id
  from public.nf_entrada
  where chave = v_chave
  limit 1;

  if v_nf_id is not null then
    status := 'ja_importada';
    message := 'NF ja importada';
    nf_entrada_id := v_nf_id;
    return next;
    return;
  end if;

  v_emitente := coalesce(nullif(p_nf_json->>'emitente_nome',''), 'Emitente');
  v_numero   := coalesce(nullif(p_nf_json->>'numero',''), '');
  v_serie    := coalesce(nullif(p_nf_json->>'serie',''), '');
  v_data_emissao := nullif(p_nf_json->>'data_emissao','')::timestamptz;
  v_total_nf := coalesce((p_nf_json->>'valor_total')::numeric, 0);

  -- Se veio OS, validar se existe e pertence ao tenant
  v_has_os := (p_os_id is not null);

  if v_has_os then
    if not exists (
      select 1
      from public.ordens_servico os
      where os.id = p_os_id
        and os.tenant_id = p_tenant_id
    ) then
      raise exception 'OS invalida (id=%) para este tenant', p_os_id;
    end if;
  end if;

  -- 1) NF
  insert into public.nf_entrada (
    chave,
    numero,
    serie,
    emitente_nome,
    emitente_cnpj,
    data_emissao,
    valor_produtos,
    valor_frete,
    valor_seguro,
    valor_desconto,
    valor_outros,
    valor_total,
    xml_raw,
    fornecedor_id,
    tenant_id,
    empresa_id,
    finalidade_contexto,
    os_id,
    baixa_os_automatica
  )
  values (
    v_chave,
    v_numero,
    v_serie,
    v_emitente,
    p_nf_json->>'emitente_cnpj',
    v_data_emissao,
    coalesce((p_nf_json->>'valor_produtos')::numeric, 0),
    coalesce((p_nf_json->>'valor_frete')::numeric, 0),
    coalesce((p_nf_json->>'valor_seguro')::numeric, 0),
    coalesce((p_nf_json->>'valor_desconto')::numeric, 0),
    coalesce((p_nf_json->>'valor_outros')::numeric, 0),
    v_total_nf,
    p_xml_raw,
    p_fornecedor_id,
    p_tenant_id,
    p_empresa_id,
    p_finalidade_contexto,
    p_os_id,
    p_baixar_os
  )
  returning id into v_nf_id;

  -- 2) NF itens
  insert into public.nf_entrada_itens (
    nf_entrada_id,
    item_id,
    codigo_fornecedor,
    descricao,
    ncm,
    cfop,
    qtd,
    v_unit,
    v_prod,
    v_icms,
    v_ipi,
    v_pis,
    v_cofins,
    aliq_icms,
    aliq_ipi,
    aliq_pis,
    aliq_cofins,
    aliquota_icms,
    aliquota_ipi,
    aliquota_pis,
    aliquota_cofins,
    tenant_id
  )
  select
    v_nf_id,
    nullif((elem->>'item_id')::bigint, 0),
    elem->>'codigo',
    elem->>'nome',
    elem->>'ncm',
    elem->>'cfop',
    coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0),
    coalesce((elem->>'valorUnit')::numeric, (elem->>'v_unit')::numeric, 0),
    coalesce((elem->>'total')::numeric, (elem->>'v_prod')::numeric, 0),
    coalesce((elem->>'v_icms')::numeric, 0),
    coalesce((elem->>'v_ipi')::numeric, 0),
    coalesce((elem->>'v_pis')::numeric, 0),
    coalesce((elem->>'v_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    nullif((elem->>'aliq_icms')::numeric, 0),
    nullif((elem->>'aliq_ipi')::numeric, 0),
    nullif((elem->>'aliq_pis')::numeric, 0),
    nullif((elem->>'aliq_cofins')::numeric, 0),
    p_tenant_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem;

  -- 3) Movimentacoes (ENTRADA)
  insert into public.movimentacoes (
    item_id,
    tipo,
    quantidade,
    motivo,
    realizado_por,
    data_movimentacao,
    custo_unitario_bruto,
    custo_unitario_real,
    credito_icms,
    credito_pis,
    credito_cofins,
    origem_nf_entrada_id,
    origem_os_id,
    v_ipi,
    v_icms,
    v_pis,
    v_cofins,
    v_frete_rateado,
    tenant_id,
    empresa_id
  )
  select
    (elem->>'item_id')::int,
    coalesce(nullif(elem->>'tipo',''), 'entrada'),
    coalesce((elem->>'quantidade')::numeric, (elem->>'qtd')::numeric, 0),
    elem->>'motivo',
    elem->>'realizado_por',
    coalesce(nullif(elem->>'data_movimentacao','')::timestamp, now()),
    nullif((elem->>'custo_unitario_bruto')::numeric, 0),
    nullif((elem->>'custo_unitario_real')::numeric, 0),
    coalesce((elem->>'credito_icms')::numeric, 0),
    coalesce((elem->>'credito_pis')::numeric, 0),
    coalesce((elem->>'credito_cofins')::numeric, 0),
    v_nf_id,
    null,
    coalesce((elem->>'v_ipi')::numeric, 0),
    coalesce((elem->>'v_icms')::numeric, 0),
    coalesce((elem->>'v_pis')::numeric, 0),
    coalesce((elem->>'v_cofins')::numeric, 0),
    coalesce((elem->>'v_frete_rateado')::numeric, 0),
    p_tenant_id,
    p_empresa_id
  from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb)) elem;

  -- 4) Financeiro (opcional)
  if coalesce(p_gerar_contas_pagar, false) then
    if not (public.can('financeiro','write') or public.can('financeiro','config')) then
      raise exception 'Sem permissao para gerar contas a pagar';
    end if;

    select c.id into v_categoria_id
    from public.financeiro_categorias c
    where c.tenant_id = p_tenant_id
      and c.tipo = 'DESPESA'
      and c.nome = 'Compras (NF Entrada)'
    limit 1;

    if v_categoria_id is null then
      insert into public.financeiro_categorias (tenant_id, nome, tipo, exige_os)
      values (p_tenant_id, 'Compras (NF Entrada)', 'DESPESA', false)
      returning id into v_categoria_id;
    end if;

    v_parcelamento_id := gen_random_uuid();

    if p_parcelas_json is null or jsonb_typeof(p_parcelas_json) <> 'array' or jsonb_array_length(p_parcelas_json) = 0 then
      p_parcelas_json := jsonb_build_array(
        jsonb_build_object(
          'numero', '001',
          'vencimento', coalesce((v_data_emissao)::date, current_date),
          'valor', v_total_nf
        )
      );
    end if;

    select coalesce(sum((p->>'valor')::numeric), 0)
      into v_soma_parcelas
    from jsonb_array_elements(p_parcelas_json) p;

    if abs(coalesce(v_soma_parcelas,0) - coalesce(v_total_nf,0)) > 0.05 then
      raise exception 'Soma das parcelas (%.2f) difere do total da NF (%.2f)', v_soma_parcelas, v_total_nf;
    end if;

    insert into public.financeiro_titulos (
      tenant_id,
      natureza,
      status,
      categoria_id,
      descricao,
      documento_ref,
      competencia,
      vencimento,
      valor_original,
      parcelamento_id,
      observacoes,
      nf_entrada_id,
      parcela_numero,
      fornecedor_id
    )
    select
      p_tenant_id,
      'PAGAR'::public.financeiro_natureza_titulo,
      'ABERTO'::public.financeiro_status_titulo,
      v_categoria_id,
      ('NF-e ' || coalesce(v_numero,'') || '/' || coalesce(v_serie,'') || ' - ' || v_emitente),
      v_chave,
      coalesce(date_trunc('month', coalesce(v_data_emissao, now()))::date, current_date),
      (p->>'vencimento')::date,
      (p->>'valor')::numeric,
      v_parcelamento_id,
      'Gerado automaticamente na importacao XML',
      v_nf_id,
      nullif(p->>'numero',''),
      p_fornecedor_id
    from jsonb_array_elements(p_parcelas_json) p
    on conflict do nothing;
  end if;

  -- 5) Vincular OS + criar/atualizar os_itens + baixa automatica (opcional)
  if v_has_os then
    for v_it in select * from jsonb_array_elements(coalesce(p_itens_json, '[]'::jsonb))
    loop
      v_item_id := (v_it->>'item_id')::int;
      v_qtd := coalesce((v_it->>'quantidade')::numeric, (v_it->>'qtd')::numeric, 0);

      v_vunit := coalesce(
        nullif((v_it->>'valorUnit')::numeric, 0),
        nullif((v_it->>'v_unit')::numeric, 0),
        nullif((v_it->>'valor_unitario')::numeric, 0),
        0
      );

      v_vtotal := coalesce(
        nullif((v_it->>'total')::numeric, 0),
        nullif((v_it->>'v_prod')::numeric, 0),
        case when v_vunit > 0 and v_qtd > 0 then (v_vunit * v_qtd)::numeric(14,2) else 0 end
      );

      if v_item_id is null or v_item_id <= 0 then
        raise exception 'Item invalido em p_itens_json (item_id=%)', v_it->>'item_id';
      end if;

      if v_qtd <= 0 then
        raise exception 'Quantidade invalida para item_id=% (qtd=%)', v_item_id, v_qtd;
      end if;

      with upd as (
        update public.os_itens oi
           set quantidade = oi.quantidade + v_qtd,
               valor_total = oi.valor_total + v_vtotal,
               valor_unitario = case when v_vunit > 0 then v_vunit else oi.valor_unitario end,
               baixa_estoque = (oi.baixa_estoque or p_baixar_os),
               observacoes = coalesce(oi.observacoes,'')
         where oi.tenant_id = p_tenant_id
           and oi.os_id = p_os_id
           and oi.item_id = v_item_id
         returning 1
      )
      insert into public.os_itens (
        os_id, item_id, quantidade, valor_unitario, valor_total,
        desconto_percentual, desconto_valor, baixa_estoque, observacoes, tenant_id
      )
      select
        p_os_id, v_item_id, v_qtd,
        case
          when v_vunit > 0 then v_vunit
          when v_qtd > 0 and v_vtotal > 0 then (v_vtotal / v_qtd)
          else 0
        end,
        v_vtotal,
        0, 0, p_baixar_os,
        ('Gerado via importacao NF-e ' || v_chave),
        p_tenant_id
      where not exists (select 1 from upd);

      if p_baixar_os then
        insert into public.movimentacoes (
          item_id,
          tipo,
          quantidade,
          motivo,
          realizado_por,
          data_movimentacao,
          origem_nf_entrada_id,
          origem_os_id,
          tenant_id,
          empresa_id
        )
        values (
          v_item_id,
          'saida',
          v_qtd,
          ('Baixa automatica OS ' || p_os_id || ' via NF-e ' || v_chave),
          'sistema',
          now(),
          v_nf_id,
          p_os_id,
          p_tenant_id,
          p_empresa_id
        );
      end if;
    end loop;
  end if;

  status := 'ok';
  message := 'Importado com sucesso';
  nf_entrada_id := v_nf_id;
  return next;
end;
$$;
CREATE OR REPLACE FUNCTION public.remove_os_item_reverte_estoque(
  p_os_item_id integer,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant uuid;
  v_empresa uuid;
  v_realizado_por text;
  v_item public.itens;
  v_row public.os_itens;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  select *
    into v_row
  from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item da OS nao encontrado';
  end if;

  select *
    into v_item
  from public.itens
  where id = v_row.item_id
    and tenant_id = v_tenant;

  if not found then
    raise exception 'Item invalido ou fora do tenant atual';
  end if;

  delete from public.os_itens
  where id = p_os_item_id
    and tenant_id = v_tenant;

  if coalesce(v_row.baixa_estoque, false)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      origem_os_id,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      v_row.item_id,
      'entrada',
      v_row.quantidade,
      coalesce(p_motivo, 'Estorno baixa OS ' || v_row.os_id),
      v_realizado_por,
      now(),
      v_row.os_id,
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = v_row.os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = v_row.os_id
    and os.tenant_id = v_tenant;
end;
$function$;
CREATE OR REPLACE FUNCTION public.add_os_item_baixa_imediata(
  p_os_id integer,
  p_item_id integer,
  p_quantidade numeric,
  p_valor_unitario numeric,
  p_desconto_percentual numeric default 0,
  p_desconto_valor numeric default 0,
  p_baixa_estoque boolean default true,
  p_realizado_por text default null,
  p_motivo text default null,
  p_empresa_id uuid default null
)
returns public.os_itens
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item public.itens;
  v_total numeric;
  v_row public.os_itens;
  v_tenant uuid;
  v_realizado_por text;
  v_empresa uuid;
begin
  if auth.uid() is null then
    raise exception 'Nao autenticado';
  end if;

  v_tenant := public.current_tenant_id();
  if v_tenant is null then
    raise exception 'Tenant atual nao definido';
  end if;

  if not public.can('os_rpcs','execute') then
    raise exception 'Sem permissao para executar operacao de OS';
  end if;

  v_empresa := coalesce(p_empresa_id, public.current_empresa_id());
  if v_empresa is null then
    raise exception 'Empresa atual nao definida. Informe p_empresa_id na chamada da RPC.';
  end if;

  perform public.set_current_empresa(v_empresa);

  v_realizado_por := coalesce(p_realizado_por, auth.uid()::text);

  if not exists (
    select 1
    from public.ordens_servico os
    where os.id = p_os_id
      and os.tenant_id = v_tenant
  ) then
    raise exception 'OS invalida ou fora do tenant atual';
  end if;

  select *
    into v_item
  from public.itens
  where id = p_item_id
    and tenant_id = v_tenant
    and ativo = true;

  if not found then
    raise exception 'Item invalido/inativo ou fora do tenant atual';
  end if;

  if p_quantidade is null or p_quantidade <= 0 then
    raise exception 'Quantidade invalida';
  end if;

  v_total := (p_quantidade * p_valor_unitario) - coalesce(p_desconto_valor, 0);

  insert into public.os_itens (
    tenant_id,
    os_id,
    item_id,
    quantidade,
    valor_unitario,
    valor_total,
    desconto_percentual,
    desconto_valor,
    baixa_estoque,
    criado_em
  )
  values (
    v_tenant,
    p_os_id,
    p_item_id,
    p_quantidade,
    p_valor_unitario,
    v_total,
    coalesce(p_desconto_percentual, 0),
    coalesce(p_desconto_valor, 0),
    coalesce(p_baixa_estoque, true),
    now()
  )
  returning * into v_row;

  if coalesce(p_baixa_estoque, true)
     and v_item.tipo = 'produto'
     and coalesce(v_item.controla_estoque, false) = true
  then
    if not (public.can('estoque','write') or public.can('os_rpcs','execute')) then
      raise exception 'Sem permissao para movimentar estoque';
    end if;

    insert into public.movimentacoes (
      tenant_id,
      empresa_id,
      item_id,
      tipo,
      quantidade,
      motivo,
      realizado_por,
      data_movimentacao,
      created_at
    )
    values (
      v_tenant,
      v_empresa,
      p_item_id,
      'saida',
      p_quantidade,
      coalesce(p_motivo, 'Baixa imediata via OS ' || p_os_id),
      v_realizado_por,
      now(),
      now()
    );
  end if;

  update public.ordens_servico os
  set valor_total = coalesce((
        select sum(oi.valor_total)
        from public.os_itens oi
        where oi.os_id = p_os_id
          and oi.tenant_id = v_tenant
      ), 0),
      atualizado_em = now()
  where os.id = p_os_id
    and os.tenant_id = v_tenant;

  return v_row;
end;
$function$;
NOTIFY pgrst, 'reload schema';
COMMIT;
