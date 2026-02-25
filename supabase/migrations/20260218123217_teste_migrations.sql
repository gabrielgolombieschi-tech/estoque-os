create sequence "public"."_teste_migrations_id_seq";
create table "public"."_teste_migrations" (
    "id" bigint not null default nextval('public._teste_migrations_id_seq'::regclass),
    "created_at" timestamp with time zone not null default now()
      );
alter sequence "public"."_teste_migrations_id_seq" owned by "public"."_teste_migrations"."id";
CREATE UNIQUE INDEX _teste_migrations_pkey ON public._teste_migrations USING btree (id);
alter table "public"."_teste_migrations" add constraint "_teste_migrations_pkey" PRIMARY KEY using index "_teste_migrations_pkey";
grant delete on table "public"."_teste_migrations" to "anon";
grant insert on table "public"."_teste_migrations" to "anon";
grant references on table "public"."_teste_migrations" to "anon";
grant select on table "public"."_teste_migrations" to "anon";
grant trigger on table "public"."_teste_migrations" to "anon";
grant truncate on table "public"."_teste_migrations" to "anon";
grant update on table "public"."_teste_migrations" to "anon";
grant delete on table "public"."_teste_migrations" to "authenticated";
grant insert on table "public"."_teste_migrations" to "authenticated";
grant references on table "public"."_teste_migrations" to "authenticated";
grant select on table "public"."_teste_migrations" to "authenticated";
grant trigger on table "public"."_teste_migrations" to "authenticated";
grant truncate on table "public"."_teste_migrations" to "authenticated";
grant update on table "public"."_teste_migrations" to "authenticated";
grant delete on table "public"."_teste_migrations" to "postgres";
grant insert on table "public"."_teste_migrations" to "postgres";
grant references on table "public"."_teste_migrations" to "postgres";
grant select on table "public"."_teste_migrations" to "postgres";
grant trigger on table "public"."_teste_migrations" to "postgres";
grant truncate on table "public"."_teste_migrations" to "postgres";
grant update on table "public"."_teste_migrations" to "postgres";
grant delete on table "public"."_teste_migrations" to "service_role";
grant insert on table "public"."_teste_migrations" to "service_role";
grant references on table "public"."_teste_migrations" to "service_role";
grant select on table "public"."_teste_migrations" to "service_role";
grant trigger on table "public"."_teste_migrations" to "service_role";
grant truncate on table "public"."_teste_migrations" to "service_role";
grant update on table "public"."_teste_migrations" to "service_role";
