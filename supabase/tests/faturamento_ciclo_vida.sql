\set ON_ERROR_STOP on
begin;

insert into auth.users (id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('70000000-0000-4000-8000-000000000001','authenticated','authenticated','ciclo@example.test','{"provider":"email","providers":["email"]}','{}',now(),now());
insert into public.tenants(id,nome,ativo) values('70000000-0000-4000-8000-000000000010','Tenant ciclo',true);
insert into c.tenant(id,codigo,nome,ativo) values('70000000-0000-4000-8000-000000000010','CICLO','Tenant ciclo',true);
insert into c.empresa(id,tenant_id,codigo,razao_social,nome_fantasia,cnpj,ativo)
values('70000000-0000-4000-8000-000000000020','70000000-0000-4000-8000-000000000010','CICLO','Empresa ciclo','Empresa ciclo','13671448000189',true);
insert into public.empresas(id,tenant_id,cnpj,razao_social,nome_fantasia,ativo)
values('70000000-0000-4000-8000-000000000020','70000000-0000-4000-8000-000000000010','13671448000189','Empresa ciclo','Empresa ciclo',true);
insert into c.empresa_fiscal(empresa_id,serie_nfe,email_fisco,certificado_validade_em)
values('70000000-0000-4000-8000-000000000020',2,null,current_date+30);
insert into a.usuario(id,auth_user_id,nome,email,ativo)
values('70000000-0000-4000-8000-000000000040','70000000-0000-4000-8000-000000000001','Usuario ciclo','ciclo@example.test',true);
insert into a.usuario_tenant(usuario_id,tenant_id,papel,ativo)
values('70000000-0000-4000-8000-000000000040','70000000-0000-4000-8000-000000000010','ADMIN',true);
insert into a.usuario_empresa(usuario_id,empresa_id,papel,ativo)
values('70000000-0000-4000-8000-000000000040','70000000-0000-4000-8000-000000000020','DIRETOR',true);
insert into public.user_tenant_context(user_id,tenant_id)
values('70000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000010');
insert into public.user_empresa_context(user_id,tenant_id,empresa_id)
values('70000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020');

insert into f.solicitacao_faturamento(id,tenant_id,empresa_id,status)
values
 ('70000000-0000-4000-8000-000000000101','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','EMITIDA'),
 ('70000000-0000-4000-8000-000000000102','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','EMITIDA');
alter table f.documento_fiscal disable trigger trg_documento_fiscal__ar_nfe;
insert into f.documento_fiscal(id,tenant_id,empresa_id,chave_acesso,modelo,serie,numero,emissao_date,valor_total,valor_produtos,operacao,natureza,origem,nfe_status)
values
 ('70000000-0000-4000-8000-000000000111','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020',repeat('1',44),'55','2','1',current_date,100,100,'SAIDA','PRODUTO','EMITIDO','EMITIDA'),
 ('70000000-0000-4000-8000-000000000112','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020',repeat('2',44),'55','2','3',current_date,200,200,'SAIDA','PRODUTO','EMITIDO','EMITIDA');
alter table f.documento_fiscal enable trigger trg_documento_fiscal__ar_nfe;
insert into f.documento_fiscal_emissao(documento_fiscal_id,solicitacao_id,tenant_id,empresa_id,referencia_externa,ambiente,status,autorizado_em,xml_path,danfe_path)
values
 ('70000000-0000-4000-8000-000000000111','70000000-0000-4000-8000-000000000101','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','CICLO-1','HOMOLOGACAO','AUTORIZADA',now()-interval '1 hour','ciclo/1.xml','ciclo/1.pdf'),
 ('70000000-0000-4000-8000-000000000112','70000000-0000-4000-8000-000000000102','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','CICLO-3','HOMOLOGACAO','AUTORIZADA',now()-interval '25 hours','ciclo/3.xml','ciclo/3.pdf');
insert into f.documento_fiscal_item(tenant_id,empresa_id,documento_fiscal_id,item_n,descricao,ncm,cfop,quantidade,unidade,valor_unitario,valor_total)
values
 ('70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','70000000-0000-4000-8000-000000000111',1,'Venda interna','85365090','5102',1,'UN',100,100),
 ('70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','70000000-0000-4000-8000-000000000112',1,'Venda interestadual','85365090','6102',1,'UN',200,200);

select set_config('request.jwt.claim.sub','70000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claims','{"sub":"70000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;

do $smoke$
declare v_nova jsonb; v_antiga jsonb; v_estorno_interno uuid; v_estorno_externo uuid; v_exc jsonb;
begin
  v_nova:=f.fn_nfe_ciclo_contexto('70000000-0000-4000-8000-000000000111');
  v_antiga:=f.fn_nfe_ciclo_contexto('70000000-0000-4000-8000-000000000112');
  if (v_nova#>>'{cancelamento,pode_cancelar}')::boolean is not true then raise exception 'Nota dentro de 24h nao liberou cancelamento'; end if;
  if (v_antiga#>>'{cancelamento,deve_estornar}')::boolean is not true then raise exception 'Nota fora de 24h nao direcionou ao estorno'; end if;
  if not exists(select 1 from f.fn_nfe_lacunas() where serie=2 and numero_inicial=2 and numero_final=2) then raise exception 'Lacuna da serie nao detectada'; end if;
  perform f.fn_nfe_inutilizacao_validar(2,2,2,'Lacuna nao utilizada em homologacao');
  v_estorno_interno:=f.fn_estorno_criar('70000000-0000-4000-8000-000000000111','1202','Estorno da venda interna fora do prazo');
  v_estorno_externo:=f.fn_estorno_criar('70000000-0000-4000-8000-000000000112','2202','Estorno da venda externa fora do prazo');
  if (select cfop_proposto from f.operacao_fiscal where id=v_estorno_interno) <> '1202' then raise exception 'CFOP do estorno interno nao foi derivado'; end if;
  if (select cfop_proposto from f.operacao_fiscal where id=v_estorno_externo) <> '2202' then raise exception 'CFOP do estorno externo nao foi derivado'; end if;
  perform f.fn_empresa_certificado_validade_atualizar('70000000-0000-4000-8000-000000000020',current_date+40);
  v_exc:=f.fn_nfe_excecoes_mensais(current_date);
  if v_exc is null or not (v_exc?'itens') then raise exception 'Painel mensal nao retornou estrutura'; end if;
  begin
    update f.documento_fiscal_evento set status='ALTERADO' where false;
    raise exception 'Authenticated manteve permissao de alterar evento';
  exception when insufficient_privilege then null; end;
end;
$smoke$;

reset role;
insert into f.documento_fiscal_evento(documento_fiscal_id,tenant_id,empresa_id,tipo,status)
values('70000000-0000-4000-8000-000000000111','70000000-0000-4000-8000-000000000010','70000000-0000-4000-8000-000000000020','CONSULTA','OK');
do $append$
begin
  begin
    update f.documento_fiscal_evento set status='MUTADO' where documento_fiscal_id='70000000-0000-4000-8000-000000000111';
    raise exception 'Trigger append-only aceitou update';
  exception when object_not_in_prerequisite_state then null; end;
end;
$append$;

select 'Ciclo de vida: janela 24h, dois CFOPs de estorno, lacuna, painel, certificado e append-only passaram.' resultado;
rollback;
