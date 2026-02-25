revoke delete on table "public"."_teste_migrations" from "anon";
revoke insert on table "public"."_teste_migrations" from "anon";
revoke references on table "public"."_teste_migrations" from "anon";
revoke select on table "public"."_teste_migrations" from "anon";
revoke trigger on table "public"."_teste_migrations" from "anon";
revoke truncate on table "public"."_teste_migrations" from "anon";
revoke update on table "public"."_teste_migrations" from "anon";
revoke delete on table "public"."_teste_migrations" from "authenticated";
revoke insert on table "public"."_teste_migrations" from "authenticated";
revoke references on table "public"."_teste_migrations" from "authenticated";
revoke select on table "public"."_teste_migrations" from "authenticated";
revoke trigger on table "public"."_teste_migrations" from "authenticated";
revoke truncate on table "public"."_teste_migrations" from "authenticated";
revoke update on table "public"."_teste_migrations" from "authenticated";
revoke delete on table "public"."_teste_migrations" from "service_role";
revoke insert on table "public"."_teste_migrations" from "service_role";
revoke references on table "public"."_teste_migrations" from "service_role";
revoke select on table "public"."_teste_migrations" from "service_role";
revoke trigger on table "public"."_teste_migrations" from "service_role";
revoke truncate on table "public"."_teste_migrations" from "service_role";
revoke update on table "public"."_teste_migrations" from "service_role";
alter table "public"."itens" drop constraint "itens_tipo_check";
alter table "public"."ordens_servico" drop constraint "ordens_servico_status_check";
alter table "public"."_teste_migrations" drop constraint "_teste_migrations_pkey";
drop index if exists "public"."_teste_migrations_pkey";
drop table "public"."_teste_migrations";
drop sequence if exists "public"."_teste_migrations_id_seq";
alter table "public"."itens" add constraint "itens_tipo_check" CHECK (((tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying, 'despesa'::character varying])::text[]))) not valid;
alter table "public"."itens" validate constraint "itens_tipo_check";
alter table "public"."ordens_servico" add constraint "ordens_servico_status_check" CHECK (((status)::text = ANY ((ARRAY['aberta'::character varying, 'em_andamento'::character varying, 'concluida'::character varying, 'cancelada'::character varying])::text[]))) not valid;
alter table "public"."ordens_servico" validate constraint "ordens_servico_status_check";
create or replace view "r"."r_orcamento_catalogo_busca" as  SELECT 'ITEM'::text AS origem,
    i.tenant_id,
    i.empresa_id,
    (i.id)::text AS ref_id,
    i.id AS item_id,
    NULL::uuid AS conjunto_id,
    upper(TRIM(BOTH FROM i.codigo_interno)) AS codigo,
    upper(TRIM(BOTH FROM i.nome)) AS nome,
    upper(TRIM(BOTH FROM COALESCE(i.unidade_medida, 'UN'::character varying))) AS unidade,
        CASE
            WHEN (lower((i.tipo)::text) = 'produto'::text) THEN 'PRODUTO'::text
            WHEN (lower((i.tipo)::text) = 'servico'::text) THEN 'SERVICO'::text
            ELSE upper((i.tipo)::text)
        END AS tipo,
    (i.preco_unitario)::numeric(15,2) AS preco_sugerido
   FROM public.itens i
  WHERE ((i.ativo = true) AND ((i.tipo)::text = ANY ((ARRAY['produto'::character varying, 'servico'::character varying])::text[])))
UNION ALL
 SELECT 'CONJUNTO'::text AS origem,
    c.tenant_id,
    c.empresa_id,
    (c.id)::text AS ref_id,
    NULL::integer AS item_id,
    c.id AS conjunto_id,
    c.codigo,
    c.nome,
    'CJ'::text AS unidade,
    'CONJUNTO'::text AS tipo,
        CASE
            WHEN (c.precificacao = 'PRECO_FIXO'::text) THEN c.preco_fixo
            ELSE (COALESCE(sum((ci.quantidade * i.preco_unitario)), (0)::numeric))::numeric(15,2)
        END AS preco_sugerido
   FROM ((c.conjunto c
     LEFT JOIN c.conjunto_item ci ON (((ci.conjunto_id = c.id) AND (ci.deleted_at IS NULL))))
     LEFT JOIN public.itens i ON (((i.id = ci.item_id) AND (i.tenant_id = c.tenant_id) AND (i.empresa_id = c.empresa_id) AND (i.ativo = true))))
  WHERE ((c.deleted_at IS NULL) AND (c.ativo = true))
  GROUP BY c.id;
