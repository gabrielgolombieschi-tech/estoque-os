alter table a.config_orcamento
  add column if not exists margem_mao_obra_padrao_percent numeric not null default 30;

comment on column a.config_orcamento.margem_mao_obra_padrao_percent is
  'Margem de lucro padrao (%) aplicada sobre o custo de mao de obra (apontamentos por cargo) ao gerar orcamento a partir de uma OS Fiado. Independente de margem_lucro_padrao_percent, que continua valendo so para materiais.';
