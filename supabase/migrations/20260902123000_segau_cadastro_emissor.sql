begin;

-- Dados oficiais da ELETRICA SEGAU LTDA (CNPJ 13.671.448/0001-89).
-- Razao social, nome fantasia, CNAE, contato e endereco: Cartao CNPJ emitido
-- em 09/02/2026. IE e CRT: documento fiscal da empresa confirmado pelo usuario.
update c.empresa
set razao_social = 'ELETRICA SEGAU LTDA',
    nome_fantasia = 'SEGAU',
    email = 'contato@segau.com.br',
    telefone = '4734735171',
    updated_at = now()
where tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and cnpj = '13671448000189'
  and deleted_at is null;

insert into c.empresa_fiscal (
  empresa_id,
  ie_isento,
  inscricao_estadual,
  cnae_principal,
  regime_tributario,
  crt,
  serie_nfe,
  created_at,
  updated_at
)
select
  e.id,
  false,
  '257686835',
  '4321500',
  'Regime Normal',
  3,
  2,
  now(),
  now()
from c.empresa e
where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and e.cnpj = '13671448000189'
  and e.deleted_at is null
on conflict (empresa_id) where deleted_at is null
do update set
  ie_isento = excluded.ie_isento,
  inscricao_estadual = excluded.inscricao_estadual,
  cnae_principal = excluded.cnae_principal,
  regime_tributario = excluded.regime_tributario,
  crt = excluded.crt,
  serie_nfe = coalesce(c.empresa_fiscal.serie_nfe, excluded.serie_nfe),
  updated_at = now();

insert into c.empresa_endereco (
  empresa_id,
  tipo,
  cep,
  logradouro,
  numero,
  complemento,
  bairro,
  cidade,
  uf,
  codigo_municipio_ibge,
  pais,
  created_at,
  updated_at
)
select
  e.id,
  'FISCAL',
  '89219600',
  'Rua Dona Francisca',
  '8300',
  'Cond. Perini Business Park, Bloco 1, Modulo B, Box Singapura',
  'Zona Industrial Norte',
  'Joinville',
  'SC',
  '4209102',
  'BR',
  now(),
  now()
from c.empresa e
where e.tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
  and e.cnpj = '13671448000189'
  and e.deleted_at is null
on conflict (empresa_id, tipo) where deleted_at is null
do update set
  cep = excluded.cep,
  logradouro = excluded.logradouro,
  numero = excluded.numero,
  complemento = excluded.complemento,
  bairro = excluded.bairro,
  cidade = excluded.cidade,
  uf = excluded.uf,
  codigo_municipio_ibge = excluded.codigo_municipio_ibge,
  pais = excluded.pais,
  updated_at = now();

commit;
