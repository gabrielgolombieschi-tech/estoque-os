\set ON_ERROR_STOP on

-- Cancelar a nota tira a OS do faturamento e a devolve para concluida (09/09/2026).
-- Cobre tambem os dois casos em que NAO se pode mexer: OS com outra nota valida ainda
-- viva, e OS faturada no legado, que nunca teve documento fiscal vinculado.

begin;

insert into public.tenants (id, nome, ativo) values ('19200000-0000-4000-8000-000000000010', 'Tenant reverter', true);
insert into c.tenant (id, codigo, nome, ativo) values ('19200000-0000-4000-8000-000000000010', 'REVERTER', 'Tenant reverter', true);
insert into c.empresa (id, tenant_id, codigo, razao_social, nome_fantasia, cnpj, ativo)
values ('19200000-0000-4000-8000-000000000020', '19200000-0000-4000-8000-000000000010', 'REV-A', 'Empresa reverter', 'Empresa reverter', '19200000000100', true);
insert into public.empresas (id, tenant_id, cnpj, razao_social, nome_fantasia, ativo)
values ('19200000-0000-4000-8000-000000000020', '19200000-0000-4000-8000-000000000010', '19200000000100', 'Empresa reverter', 'Empresa reverter', true);
insert into public.clientes (id, tenant_id, empresa_id, nome, documento, razao_social)
values (919201, '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020', 'CLIENTE REVERTER', '19211111000191', 'CLIENTE REVERTER LTDA');
insert into f.plano_contas (tenant_id, codigo, nome, natureza, tipo, ativo)
values ('19200000-0000-4000-8000-000000000010', '3.01', 'RECEITA DE VENDAS', 'CREDITO', 'ANALITICA', true);

-- 919201: nota unica, sera cancelada. 919202: duas notas, so uma cancelada.
-- 919203: faturada no legado, sem documento fiscal nenhum.
insert into public.ordens_servico (id, numero_os, cliente_nome, cliente_id, status, os_num, tenant_id, empresa_id,
  status_fluxo, tipo_documento, codigo, numero_doc, descricao_servico, orcado, faturado_em)
values
  (919201, 'REV-1', 'CLIENTE REVERTER', 919201, 'concluida', 919201, '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020', 'faturada', 'OS', 'OS-REV-001', 1, 'Nota unica', 1000, now()),
  (919202, 'REV-2', 'CLIENTE REVERTER', 919201, 'concluida', 919202, '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020', 'faturada', 'OS', 'OS-REV-002', 2, 'Duas notas', 2000, now()),
  (919203, 'REV-3', 'CLIENTE REVERTER', 919201, 'concluida', 919203, '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020', 'faturada', 'OS', 'OS-REV-003', 3, 'Faturada no legado', 3000, now());

insert into f.documento_fiscal (id, tenant_id, empresa_id, chave_acesso, modelo, serie, numero, operacao, natureza,
  cliente_id, nfe_status, origem, os_id_import, valor_produtos, valor_total)
values
  ('19200000-0000-4000-8000-000000000031', '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020',
   '19200000000000000000000000000000000000000001', '55', '1', '901', 'SAIDA', 'PRODUTO', 919201, 'EMITIDA', 'IMPORTADO', 919201, 1000, 1000),
  ('19200000-0000-4000-8000-000000000032', '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020',
   '19200000000000000000000000000000000000000002', '55', '1', '902', 'SAIDA', 'PRODUTO', 919201, 'EMITIDA', 'IMPORTADO', 919202, 1000, 1000),
  ('19200000-0000-4000-8000-000000000033', '19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020',
   '19200000000000000000000000000000000000000003', '55', '1', '903', 'SAIDA', 'PRODUTO', 919201, 'EMITIDA', 'IMPORTADO', 919202, 1000, 1000);

do $reverter$
declare
  v_status text;
  v_faturado timestamptz;
  v_eventos integer;
begin
  -- 1) Nota unica cancelada: a OS sai do faturamento e volta para concluida.
  update f.documento_fiscal set nfe_status = 'CANCELADA', updated_at = now()
  where id = '19200000-0000-4000-8000-000000000031';

  select status_fluxo, faturado_em into v_status, v_faturado from public.ordens_servico where id = 919201;
  if v_status <> 'concluida' then
    raise exception 'OS de nota unica deveria voltar para concluida e ficou em %.', v_status;
  end if;
  if v_faturado is not null then
    raise exception 'OS de nota unica manteve faturado_em: %.', v_faturado;
  end if;

  select count(*) into v_eventos from public.ordens_servico_fluxo_eventos
  where os_id = 919201 and evento = 'reverter_faturada' and status_destino = 'concluida';
  if v_eventos <> 1 then
    raise exception 'Esperado 1 evento reverter_faturada na OS 919201 e foram %.', v_eventos;
  end if;

  -- 2) Sobrando outra nota emitida, a OS continua faturada.
  update f.documento_fiscal set nfe_status = 'CANCELADA', updated_at = now()
  where id = '19200000-0000-4000-8000-000000000032';

  select status_fluxo into v_status from public.ordens_servico where id = 919202;
  if v_status <> 'faturada' then
    raise exception 'OS com outra nota valida nao podia sair do faturamento (ficou %).', v_status;
  end if;

  -- 2b) Cancelada tambem a segunda, ai sim reverte.
  update f.documento_fiscal set nfe_status = 'CANCELADA', updated_at = now()
  where id = '19200000-0000-4000-8000-000000000033';

  select status_fluxo into v_status from public.ordens_servico where id = 919202;
  if v_status <> 'concluida' then
    raise exception 'OS sem nenhuma nota valida deveria voltar para concluida e ficou em %.', v_status;
  end if;

  -- 3) A faturada do legado, sem documento fiscal, nao pode ser tocada.
  if f.fn_os_reverter_faturada_sem_nota('19200000-0000-4000-8000-000000000010', '19200000-0000-4000-8000-000000000020', 919203) then
    raise exception 'Chamada direta reverteu a OS do legado; deveria exigir nota cancelada pelo gatilho.';
  end if;
end
$reverter$;

-- A OS do legado so e alcancada por chamada direta, nunca pelo gatilho: como nao tem
-- documento fiscal vinculado, nada dispara. Confere que ela segue faturada.
do $legado$
declare v_status text;
begin
  select status_fluxo into v_status from public.ordens_servico where id = 919203;
  if v_status <> 'faturada' then
    raise exception 'OS faturada no legado foi alterada (ficou %).', v_status;
  end if;
end
$legado$;

rollback;
