begin;

alter table public.cargos
  add column if not exists item_servico_id integer references public.itens (id) on delete set null;

comment on column public.cargos.item_servico_id is
  'Item de catalogo (tipo servico) usado para faturar horas deste cargo ao gerar orcamento a partir de uma OS Fiado. Vinculo entre apontamentos_horas e cargos e feito por nome (colaboradores.cargo = cargos.nome), nao por FK, entao esta coluna e resolvida em fn_gerar_ou_atualizar_orcamento_de_os via join textual.';

notify pgrst, 'reload schema';

commit;
