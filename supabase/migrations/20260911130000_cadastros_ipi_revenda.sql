-- Cadastros fiscais alinhados a regra do IPI na revenda.
--
-- Decisao do Gabriel em 11/09/2026, depois da NF-e 2/50 ter saido com IPI numa
-- revenda. Sao tres itens, e cada um por um motivo diferente.
--
-- 1. CHAVE SEG ACIONAM. CORDA (item 2308, NCM 8536.50.90) — importada pela Segau.
--    Estava com origem 2 (adquirida no mercado interno), que contradizia o IPI que
--    a nota destaca. Vai para origem 1 e ganha a equiparacao a industrial: o CNPJ da
--    Segau consta como adquirente na DI/DUIMP (DUIMP Prana/Pizzato), e o art. 9o, I e
--    IX do RIPI equipara o importador ao industrial na saida. Com isso o IPI de 9,75%
--    passa a ter lastro, e a revenda segue em CFOP 5102 — a equiparacao autoriza o
--    destaque, nao muda o CFOP (Resposta a Consulta SP 22712/2020).
--
-- 2. SOFT-STARTER 85A (item 3819, NCM 9032.89.11, origem 0) — nacional, comprado da
--    WEG. Perde o CST e a aliquota de IPI. A TIPI tributa o NCM em 9,75%, mas isso e
--    o que a WEG paga como fabricante; a Segau, revendendo, nao e contribuinte do IPI.
--    Foi este cadastro que produziu os R$ 470,05 da 2/50.
--
-- 3. CONTATOR 3P AC-3 38A (item 760, NCM 8536.49.00, origem 2) — comprado da Siemens
--    Brasil. Mesma situacao: sem equiparacao, sem IPI na saida.
--
-- Os quatro produtos FAB-* nao entram aqui: saem em CFOP 5101, fabricacao propria, e
-- o IPI deles e devido.

do $cadastros$
declare
  v_chave integer;
  v_soft integer;
  v_contator integer;
  v_conferencia record;
begin
  select i.id into v_chave from public.itens i where i.codigo_interno = '20973';
  select i.id into v_soft from public.itens i where i.codigo_interno = '10874630';
  select i.id into v_contator from public.itens i where i.codigo_interno = '3RT20281AN20';

  -- 1. A chave passa a declarar a importacao que de fato houve.
  if v_chave is not null then
    update public.fiscal_itens
       set origem = 1,
           equiparado_industrial = true,
           atualizado_em = now()
     where item_id = v_chave;
  else
    raise notice 'Item 20973 (chave de seguranca) nao encontrado.';
  end if;

  -- 2 e 3. Revenda sem equiparacao nao destaca IPI: o grupo sai do cadastro.
  update public.fiscal_itens
     set cst_ipi = null,
         aliq_ipi = null,
         atualizado_em = now()
   where item_id in (v_soft, v_contator)
     and item_id is not null;

  for v_conferencia in
    select i.codigo_interno, fi.origem, fi.cst_ipi, fi.aliq_ipi, fi.equiparado_industrial
    from public.fiscal_itens fi
    join public.itens i on i.id = fi.item_id
    where fi.item_id in (v_chave, v_soft, v_contator)
  loop
    raise notice 'item % -> origem %, CST IPI %, aliquota %, equiparado %',
      v_conferencia.codigo_interno, v_conferencia.origem,
      coalesce(v_conferencia.cst_ipi, '(sem)'),
      coalesce(v_conferencia.aliq_ipi::text, '(sem)'),
      v_conferencia.equiparado_industrial;
  end loop;

  -- Confere so os tres itens tocados aqui. A mesma checagem no cadastro inteiro
  -- acusaria os ~600 produtos que estao com origem 1 copiada da nota do fornecedor —
  -- o fornecedor importou, nao a Segau, e para ela a origem na saida e 2. Aqueles
  -- serao tratados num levantamento proprio, com a contadora; ate la a trava do
  -- montador recusa a emissao deles, que e o comportamento desejado.
  if exists (
    select 1 from public.fiscal_itens
    where item_id in (v_chave, v_soft, v_contator)
      and ((origem = 1 and equiparado_industrial is not true)
        or (origem is distinct from 1 and equiparado_industrial is true))
  ) then
    raise exception 'Ha item com origem e equiparacao em desacordo; a emissao vai recusar.';
  end if;
end
$cadastros$;
