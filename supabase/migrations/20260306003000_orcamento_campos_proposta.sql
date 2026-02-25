-- Campos extras do documento de proposta comercial (impressao/PDF).
-- Mantem o historico do orcamento e permite refletir o padrao do documento (ORC2).

alter table m.orcamento
  add column if not exists prazo_entrega text,
  add column if not exists garantia text,
  add column if not exists validade_proposta text;

comment on column m.orcamento.prazo_entrega is 'Prazo de entrega (ex: ENTREGA IMEDIATA, A CONFIRMAR, 15 DIAS).';
comment on column m.orcamento.garantia is 'Texto livre de garantia (ex: 1 ano contra defeitos de fabricacao).';
comment on column m.orcamento.validade_proposta is 'Texto livre de validade da proposta (ex: 10 dias uteis).';

