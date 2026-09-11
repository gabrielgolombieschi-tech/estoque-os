-- ISS do 07.02 em Guaramirim, e as tabelas fiscais da NFS-e fechadas para escrita.
--
-- 1. GUARAMIRIM. A NFS-e em homologacao da OS 139 (WEG Tintas, pedido 4518572701, R$ 74.038,36)
--    parou em "aliquota de ISS do subitem 07.02 no municipio 4206504 (local da obra) nao
--    cadastrada". A regra do contador de 06/09/2026 e nao chutar: sem linha, a obra bloqueia.
--
--    A linha entra com 2% pelo HISTORICO, nao pela lei. As 11 NFS-e de obra (07.02, com material
--    deduzido) para a WEG Tintas em Guaramirim, de dez/2025 a jun/2026, sairam todas com ISS de 2%
--    retido pelo tomador — inclusive a 1843, deste mesmo pedido. As notas de 5% para o mesmo
--    tomador sao servicos com ISS na sede (Joinville), sem deducao de material.
--
--    O texto da lei municipal nao foi conferido (a versao consolidada nao abriu). A fonte da linha
--    diz isso, e a confirmacao do contador fica como condicao para liberar a producao — a
--    homologacao nao tem efeito fiscal.
--
-- 2. RLS. f.nfse_aliquota_iss, f.nfse_tributos_aproximados e f.tributacao_provisoria_nfse_homologacao
--    estavam sem RLS e com INSERT/UPDATE/DELETE para authenticated: qualquer usuario logado, de
--    qualquer empresa, podia trocar a aliquota de ISS que vai para a nota. A migration que as criou
--    (20260906090000) dava so SELECT; a escrita veio do privilegio padrao do schema. Nenhuma tela
--    grava nelas — a conferencia le por SECURITY DEFINER, e a tela de faturar a OS so le a fixture.
--    Ficam com leitura pela empresa ativa e escrita so por migration, que e a disciplina dos
--    valores fiscais de servico (scripts/nfse-perfil-revisar.mjs e migrations com a justificativa).

insert into f.nfse_aliquota_iss (tenant_id, empresa_id, item_servico, municipio_ibge, aliquota, fonte)
select distinct p.tenant_id, p.empresa_id, '07.02', '4206504', 2.00,
  'Historico, sem conferencia da lei municipal: 11 NFS-e 07.02 (obra com material deduzido) para a WEG Tintas em Guaramirim, dez/2025 a jun/2026, todas com ISS de 2% retido pelo tomador (1843, do pedido 4518572701; 1852, 1856, 1858, 1865, 1879, 1881, 1882; 1729, 1730, 1733). Confirmar com o contador antes de liberar a producao.'
from f.perfil_operacao p
where p.modelo = 'NFSE' and p.item_servico = '07.02' and p.empresa_id is not null
on conflict (tenant_id, empresa_id, item_servico, municipio_ibge) do nothing;

do $tabelas$
declare
  v_tabela text;
begin
  foreach v_tabela in array array['nfse_aliquota_iss', 'nfse_tributos_aproximados', 'tributacao_provisoria_nfse_homologacao'] loop
    execute format('alter table f.%I enable row level security', v_tabela);
    execute format('revoke insert, update, delete, truncate, references, trigger on f.%I from authenticated, anon', v_tabela);
    execute format('grant select on f.%I to authenticated', v_tabela);
    execute format('drop policy if exists %I on f.%I', v_tabela || '_leitura_empresa', v_tabela);
    execute format(
      'create policy %I on f.%I for select to authenticated using ('
      || 'tenant_id = (select public.current_tenant_id()) '
      || 'and empresa_id = (select public.current_empresa_id()) '
      || 'and (select public.has_active_empresa_access(public.current_tenant_id(), public.current_empresa_id())))',
      v_tabela || '_leitura_empresa', v_tabela);
  end loop;
end
$tabelas$;

do $conferencia$
begin
  if not exists (
    select 1 from f.nfse_aliquota_iss a
    join f.perfil_operacao p on p.tenant_id = a.tenant_id and p.empresa_id = a.empresa_id
    where p.modelo = 'NFSE' and p.item_servico = '07.02'
      and a.item_servico = '07.02' and a.municipio_ibge = '4206504' and a.aliquota = 2.00
  ) and exists (select 1 from f.perfil_operacao where modelo = 'NFSE' and item_servico = '07.02' and empresa_id is not null) then
    raise exception 'A aliquota do 07.02 em Guaramirim nao ficou em 2%%.';
  end if;
  if exists (
    select 1 from information_schema.role_table_grants
    where table_schema = 'f'
      and table_name in ('nfse_aliquota_iss', 'nfse_tributos_aproximados', 'tributacao_provisoria_nfse_homologacao')
      and grantee in ('authenticated', 'anon')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'Sobrou escrita para authenticated/anon nas tabelas fiscais da NFS-e.';
  end if;
end
$conferencia$;
