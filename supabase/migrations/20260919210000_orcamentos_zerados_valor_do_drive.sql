-- Orcamentos zerados recebem o valor da proposta que esta no Drive.
--
-- Em 19/09/2026 havia 64 orcamentos com total R$ 0,00: a proposta foi escrita a
-- mao no documento do Drive (pasta 2026/<mes>/SEG-XXX-026 ...) e o orcamento
-- ficou sem itens ou com itens a zero. A pedido do Gabriel, cada um recebe um
-- item 9999 (ITEM GENERICO ORCAMENTO, descricao livre) com a descricao igual ao
-- titulo e o valor do total da proposta, na maior revisao da pasta. Os itens que
-- ja existiam (a zero) ficam como estavam.
--
-- O preco do item sai do total dividido pelo acrescimo da condicao de pagamento,
-- para o total do orcamento bater com a proposta. Antes, uma atualizacao do
-- orcamento acerta o acrescimo com a condicao atual (m.trg_orcamento_biu faz
-- isso em qualquer alteracao; em 12 deles o valor gravado estava velho).
--
-- Fechados com valor fechado R$ 0,00 (fechados quando o total era zero) passam a
-- ter o valor fechado igual ao total, que e o orcado da OS de cada um.
--
-- Ficaram de fora (19), sem valor confiavel no Drive:
--   061, 062, 071, 074  numeracao do Drive um numero atras; a pasta do mesmo
--                       cliente e titulo nao tem proposta com valor
--   078                 so preco por maquina (R$ 920 / R$ 1.530), sem total
--   134                 tabela inconsistente (6 x 24.600 = 147.600; linha 246.000;
--                       TOTAL 306.600)
--   156                 so a tabela de homem-hora
--   261                 duplicata da SEG-260 (JAMEC Painel Esteira, R$ 5.724,76)
--   266                 pasta so com o escopo da WEG (virou a SEG-355)
--   271, 296, 298, 318, 337, 363, 407, 411  documento de proposta sem valor
--   288, 294            testes
--
-- Fonte de cada valor: arquivo e revisao usados (conferidos em 19/09/2026).

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local role postgres;

do $orcamentos_zerados$
declare
  v_linha record;
  v_orc m.orcamento%rowtype;
  v_item_id integer;
  v_unitario numeric(15,4);
  v_feitos integer := 0;
begin
  select id into v_item_id
    from public.itens
   where codigo_interno = '9999'
     and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
     and ativo;

  if v_item_id is null then
    raise notice 'Item 9999 ausente (banco local); nada a fazer.';
    return;
  end if;

  for v_linha in
    select * from (values
      ('SEG-075-026', 349489.32::numeric), -- SEG-075-026.docx, rev 00 (4 x 87.372,33)
      ('SEG-076-026', 193459.45),  -- SEG-076-026.docx, rev 00
      ('SEG-162-026', 93386.10),   -- ...Painel Red Zone em Ponte Rolante REV.2.docx, rev 02 (34 paineis)
      ('SEG-164-026', 120330.00),  -- ...Portobello- troca de chaves de seguranca.docx, rev 00
      ('SEG-204-026', 62507.38),   -- SEG-204-026.pdf, rev 00
      ('SEG-205-026', 18920.00),   -- SEG-205-026 - 665673 - Laudo e ART ... Placa Valvula.docx, rev 00
      ('SEG-224-026', 177.24),     -- SEG-224-026 - CHAVE DE SEGURANCA PIZZATO.pdf (proposta 4891)
      ('SEG-240-026', 9100.00),    -- SEG-240-026 - Weg Tintas -Carrinho assistida.pdf, rev 00
      ('SEG-247-026', 4350.00),    -- SEG-247-026 -WEG - Portas Misturadores.pdf, rev 00
      ('SEG-249-026', 576405.00),  -- SEG-249-026 -FOCUS SUL - NR12 INJETORAS REV01.pdf, rev 01
      ('SEG-254-026', 234542.61),  -- SEG-254-026-1- Incepa SMS - Elevador de canecos.docx
      ('SEG-262-026', 14938.92),   -- Drive SEG-261-026.docx (Weg - Extrutura para erguer extrusora), rev 00
      ('SEG-268-026', 7255.49),    -- SEG-268-026 - Incepa - Protecoes linha tapete.pdf, rev 00
      ('SEG-273-026', 12400.00),   -- SEG-273-026 (Google Doc), rev 00
      ('SEG-278-026', 679324.00),  -- SEG-278-026 (Google Doc), rev 00
      ('SEG-297-026', 98983.96),   -- SEG-297-026-1.pdf, rev 01
      ('SEG-304-026', 9132.00),    -- SEG-304-026 (Google Doc), rev 00, soma de 5 itens
      ('SEG-321-026', 18300.00),   -- SEG-321-026 (Google Doc), rev 00
      ('SEG-322-026', 35200.00),   -- SEG-322-026 (Google Doc), rev 00
      ('SEG-336-026', 1450000.00), -- SEG-336-026 rev02 (Google Doc) = rev03.pdf, rev 03, soma de 5 itens
      ('SEG-340-026', 1403442.00), -- SEG-340-026 (Google Doc), rev 00, TOTAL GERAL
      ('SEG-341-026', 11752.34),   -- SEG-341-026.docx, rev 00
      ('SEG-342-026', 189431.00),  -- SEG-342-026 (Google Doc), rev 00
      ('SEG-343-026', 42835.00),   -- SEG-343-026-1 (Google Doc), rev 01
      ('SEG-344-026', 55458.00),   -- SEG-344-026 (Google Doc), rev 00
      ('SEG-346-026', 168365.00),  -- SEG-346-026 (Google Doc), rev 00
      ('SEG-347-026', 61378.20),   -- SEG-347-026-1 (Google Doc), rev 01
      ('SEG-352-026', 6760.00),    -- SEG-352-026 (Google Doc), rev 00, TOTAL
      ('SEG-353-026', 98453.32),   -- SEG-353-026.docx, rev 00
      ('SEG-354-026', 870.00),     -- SEG-354-026.docx, rev 00
      ('SEG-355-026', 5235987.87), -- SEG-355-026.docx, rev 00
      ('SEG-356-026', 37800.00),   -- SEG-356-026 (Google Doc), rev 00
      ('SEG-361-026', 23432.89),   -- SEG-361-026.docx, rev 00
      ('SEG-368-026', 14335.00),   -- SEG-368-026 (Google Doc), rev 00
      ('SEG-370-026', 8200.00),    -- SEG-370-026 (Google Doc), rev 00
      ('SEG-375-026', 79876.87),   -- SEG-375-026 (Google Doc), rev 00
      ('SEG-378-026', 69640.00),   -- SEG-378-026 (Google Doc), rev 00
      ('SEG-380-026', 99409.30),   -- SEG-380-026 (Google Doc), rev 00, soma de 2 itens
      ('SEG-395-026', 56162.34),   -- SEG-395-026 (Google Doc), rev 00
      ('SEG-405-026', 12960.00),   -- SEG-405-026 (Google Doc), rev 00
      ('SEG-406-026', 14193.00),   -- SEG-406-026 (Google Doc), rev 01
      ('SEG-421-026', 56428.23),   -- SEG-421-026 (Google Doc), rev 00, TOTAL
      ('SEG-424-026', 27396.92),   -- SEG-424-026 (Google Doc), rev 00
      ('SEG-433-026', 592680.00),  -- SEG-433-026 (Google Doc), rev 01, soma de 5 itens
      ('SEG-434-026', 4692.98)     -- SEG-434-026 (Google Doc), rev 00
    ) as t(codigo, valor)
  loop
    select * into v_orc
      from m.orcamento
     where codigo = v_linha.codigo
       and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
       and deleted_at is null;

    if v_orc.id is null then
      raise exception 'Orcamento % nao encontrado.', v_linha.codigo;
    end if;

    if coalesce(v_orc.total_liquido, 0) <> 0 then
      raise notice '% ja tem total %; ignorado.', v_linha.codigo, v_orc.total_liquido;
      continue;
    end if;

    if coalesce(v_orc.desconto_global_percent, 0) <> 0 or coalesce(v_orc.valor_frete, 0) <> 0 then
      raise exception '% tem desconto global ou frete; conferir antes.', v_linha.codigo;
    end if;

    -- Acerta o acrescimo com a condicao de pagamento atual (m.trg_orcamento_biu).
    update m.orcamento set updated_at = now() where id = v_orc.id
    returning * into v_orc;

    v_unitario := round(v_linha.valor / (1 + coalesce(v_orc.acrescimo_cond_pag_percent, 0) / 100), 4);

    insert into m.orcamento_item (orcamento_id, item_id, quantidade, valor_unitario, desconto_item_percent, observacoes)
    values (v_orc.id, v_item_id, 1, v_unitario, 0, v_orc.titulo);

    select * into v_orc from m.orcamento where id = v_orc.id;
    if v_orc.total_liquido <> v_linha.valor then
      raise exception '% ficou com total % (esperado %).', v_linha.codigo, v_orc.total_liquido, v_linha.valor;
    end if;

    if v_orc.status = 'FECHADO' and coalesce(v_orc.valor_fechado, 0) = 0 then
      update m.orcamento set valor_fechado = v_linha.valor where id = v_orc.id;
    end if;

    v_feitos := v_feitos + 1;
  end loop;

  if v_feitos <> 45 then
    raise exception 'Preenchidos % orcamentos (esperado 45).', v_feitos;
  end if;
end;
$orcamentos_zerados$;

commit;
