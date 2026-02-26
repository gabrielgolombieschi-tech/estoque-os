begin;
-- Fix: PostgREST/Supabase upsert (`on_conflict`) reconhece UNIQUE CONSTRAINT de forma mais confiável.
-- O índice único parcial anterior pode causar erro 23505 (duplicate key) mesmo com `upsert`.
-- Como `documento_norm` é NULL quando `documento` é NULL, o UNIQUE sem WHERE continua permitindo múltiplos NULLs.

-- Re-limpa duplicidades por (tenant_id, empresa_id, documento_norm) mantendo o menor id.
with dup_groups as (
  select tenant_id, empresa_id, documento_norm, min(id) as keep_id
  from public.clientes
  where documento_norm is not null
  group by tenant_id, empresa_id, documento_norm
  having count(*) > 1
), victims as (
  select c.id
  from public.clientes c
  join dup_groups d
    on d.tenant_id = c.tenant_id
   and d.empresa_id = c.empresa_id
   and d.documento_norm = c.documento_norm
  where c.id <> d.keep_id
)
update public.clientes c
set documento = null,
    ativo = false,
    atualizado_em = now()
where c.id in (select id from victims);
-- Remove o índice único parcial antigo (se existir).
drop index if exists public.clientes_tenant_empresa_documento_norm_uidx;
-- Garante UNIQUE CONSTRAINT (para suportar upsert on_conflict).
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clientes_tenant_empresa_documento_norm_uk'
      and conrelid = 'public.clientes'::regclass
  ) then
    alter table public.clientes
      add constraint clientes_tenant_empresa_documento_norm_uk
      unique (tenant_id, empresa_id, documento_norm);
  end if;
end $$;
commit;
notify pgrst, 'reload schema';
