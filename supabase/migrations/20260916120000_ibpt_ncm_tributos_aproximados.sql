-- Tabela IBPT por NCM ("De Olho no Imposto") para o valor aproximado dos tributos da
-- NF-e (Lei 12.741/2012): frase no infCpl e vTotTrib, so com indFinal = 1, somando
-- federal (nacional ou importados, pela origem) + estadual. Decisao do Gabriel,
-- 16/09/2026.
--
-- Ate hoje a NF-e nao tinha tabela nenhuma: a frase somava ICMS + IPI da propria nota.
-- A tabela nasce VAZIA de proposito — as aliquotas vem so do arquivo oficial do IBPT
-- (CSV por UF, gerado com o CNPJ e o token da empresa), carregado por
-- scripts/ibpt-importar.mjs. Sem a linha vigente de um NCM, a nota sai sem a frase e
-- sem o vTotTrib (supabase/functions/_shared/fiscal/ibpt.ts).
--
-- Guarda todas as versoes: a nota confere a vigencia na data da emissao, e uma
-- versao nova convive com a anterior ate o fim da vigencia dela.

create table if not exists f.ibpt_ncm (
  uf text not null,
  codigo text not null,
  ex text not null default '',
  descricao text,
  nacional_federal_pct numeric(7,2) not null,
  importados_federal_pct numeric(7,2) not null,
  estadual_pct numeric(7,2) not null,
  municipal_pct numeric(7,2) not null default 0,
  vigencia_inicio date not null,
  vigencia_fim date not null,
  versao text not null,
  chave text,
  fonte text not null default 'IBPT',
  arquivo text,
  importado_em timestamptz not null default now(),
  constraint ibpt_ncm_pk primary key (uf, codigo, ex, versao),
  constraint ibpt_ncm_uf_ck check (uf ~ '^[A-Z]{2}$'),
  constraint ibpt_ncm_codigo_ck check (codigo ~ '^[0-9]{8}$'),
  constraint ibpt_ncm_pct_ck check (
    nacional_federal_pct between 0 and 100
    and importados_federal_pct between 0 and 100
    and estadual_pct between 0 and 100
    and municipal_pct between 0 and 100
  ),
  constraint ibpt_ncm_vigencia_ck check (vigencia_fim >= vigencia_inicio)
);

create index if not exists ibpt_ncm_busca_idx on f.ibpt_ncm (uf, codigo, vigencia_inicio desc);

comment on table f.ibpt_ncm is
  'Tabela IBPT (De Olho no Imposto) por UF x NCM x versao, so do tipo 0 (NCM). Fonte do valor aproximado dos tributos da NF-e (Lei 12.741/2012) com indFinal = 1. Carregada do CSV oficial por scripts/ibpt-importar.mjs; nunca aliquota estimada.';
comment on column f.ibpt_ncm.nacional_federal_pct is 'Coluna nacionalfederal do CSV: origens 0, 3, 4, 5 e 8.';
comment on column f.ibpt_ncm.importados_federal_pct is 'Coluna importadosfederal do CSV: origens 1, 2, 6 e 7 (estrangeiras na Tabela A).';
comment on column f.ibpt_ncm.municipal_pct is 'Coluna municipal do CSV. Nao entra na NF-e de produto.';

alter table f.ibpt_ncm enable row level security;

drop policy if exists ibpt_ncm_leitura on f.ibpt_ncm;
-- Dado publico do IBPT, sem tenant: qualquer usuario autenticado le (a conferencia da
-- tela mostra os NCMs sem tabela). Escrita so pelo service_role.
create policy ibpt_ncm_leitura on f.ibpt_ncm for select to authenticated using (true);

revoke all on f.ibpt_ncm from anon, authenticated;
grant select on f.ibpt_ncm to authenticated;
grant all on f.ibpt_ncm to service_role;
