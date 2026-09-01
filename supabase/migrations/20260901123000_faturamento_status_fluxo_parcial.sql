begin;

alter table public.ordens_servico
  drop constraint chk_ordens_servico_status_fluxo;

alter table public.ordens_servico
  add constraint chk_ordens_servico_status_fluxo
  check (
    status_fluxo is null
    or status_fluxo in (
      'em_andamento',
      'concluida',
      'faturada',
      'parcialmente_faturada',
      'em_andamento_garantia',
      'concluida_garantia',
      'cancelada'
    )
  );

commit;
