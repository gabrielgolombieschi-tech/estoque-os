-- Cidade do cliente volta a ser o nome do municipio, nao o codigo IBGE.
--
-- Achado na auditoria da NF-e 2/35 (homologacao, OS 287, 10/09/2026): o enderDest saiu
-- com <cMun>4206504</cMun><xMun>4206504</xMun>, enquanto o emitente da mesma nota traz
-- <xMun>Joinville</xMun>. xMun e o NOME do municipio (E10) e cMun e o codigo (E09) — o
-- codigo no lugar do nome nao impede a autorizacao, porque a SEFAZ valida o cMun, mas
-- imprime "4206504" como cidade do destinatario no DANFE que vai ao cliente. O payload
-- so repete o cadastro: nfe-payload.ts manda municipio_destinatario = clientes.cidade.
--
-- E legado ja reconhecido: a 20260901141000 criou fn_clientes_ibge_legado_codigo_cidade
-- para isso, mas ela exige uf preenchida e ibge_sugerido casando, e tres dos quatro
-- clientes nessa situacao nao passam por um desses filtros. Aqui a resolucao vem do
-- proprio codigo que esta no campo, que e unico nacionalmente.
--
-- Quatro clientes, todos com codigo valido em public.municipios_ibge:
--   43  WEG TINTAS -> Guaramirim   105 H. CARLOS SCHNEIDER -> Araquari
--   107 UNIPLAST   -> Joinville    314 INOXSUL             -> Joinville
--
-- O codigo_ibge_municipio nulo (107 e 314) recebe o mesmo codigo que ja estava no campo
-- cidade: e o mesmo fato, e sem ele a emissao para esses clientes nem comeca. A uf nao e
-- tocada — o 314 esta sem uf e isso continua sendo pendencia de cadastro.

update public.clientes c
   set cidade = mi.nome,
       codigo_ibge_municipio = coalesce(c.codigo_ibge_municipio, mi.codigo_ibge),
       atualizado_em = now()
  from public.municipios_ibge mi
 where mi.codigo_ibge = btrim(c.cidade)
   and btrim(coalesce(c.cidade, '')) ~ '^[0-9]{7}$';

do $conferir$
declare
  v_restantes integer;
  v_weg text;
begin
  select count(*)::integer into v_restantes
  from public.clientes
  where btrim(coalesce(cidade, '')) ~ '^[0-9]{7}$';

  if v_restantes > 0 then
    raise notice 'Ainda ha % cliente(s) com cidade numerica sem codigo em municipios_ibge; conferir a mao.', v_restantes;
  end if;

  select cidade into v_weg from public.clientes where id = 43;
  if v_weg is null then
    raise notice 'Cliente 43 nao existe neste banco; nada a conferir.';
    return;
  end if;
  if v_weg <> 'Guaramirim' then
    raise exception 'Cliente 43 (WEG TINTAS) ficou com cidade=%; esperado Guaramirim.', v_weg;
  end if;
  raise notice 'Cidade dos clientes normalizada; WEG TINTAS em Guaramirim.';
end
$conferir$;
