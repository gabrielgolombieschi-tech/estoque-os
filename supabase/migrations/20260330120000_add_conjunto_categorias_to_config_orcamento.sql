alter table a.config_orcamento
  add column if not exists conjunto_categorias text[] not null
  default array['PAINEIS AUTOPORTANTE', 'PAINEIS DE COMANDO']::text[];

update a.config_orcamento
set conjunto_categorias = array['PAINEIS AUTOPORTANTE', 'PAINEIS DE COMANDO']::text[]
where conjunto_categorias is null
   or cardinality(conjunto_categorias) = 0;
