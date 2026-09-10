-- Peso do FAB-OS319-01, para a nota com transportadora nao parar de novo.
--
-- A NF-e exige pesoL e pesoB em cada volume quando a modalidade do frete sai do 9, e a
-- tela de faturar a OS sugere esses numeros de public.itens. O kit da OS 319 estava sem
-- peso cadastrado — todas as notas anteriores dele foram sem frete, entao ninguem tinha
-- precisado. Medido pelo Gabriel em 10/09/2026: 19 kg liquido, 19,5 kg bruto com a
-- embalagem.
--
-- As dimensoes que ele passou junto (800 x 600 x 450 mm, altura x largura x
-- profundidade) nao entram aqui: nao ha coluna para elas e o grupo vol da NF-e nao tem
-- campo de dimensao — so quantidade, especie, marca, numeracao e os dois pesos.

do $peso$
declare
  v_item_id integer;
  v_liquido numeric;
  v_bruto numeric;
begin
  select i.id into v_item_id from public.itens i where i.codigo_interno = 'FAB-OS319-01';
  if not found then
    raise notice 'FAB-OS319-01 nao existe neste banco; nada a fazer.';
    return;
  end if;

  update public.itens i
     set peso_liquido = 19.000,
         peso_bruto = 19.500
   where i.id = v_item_id;

  select peso_liquido, peso_bruto into v_liquido, v_bruto from public.itens where id = v_item_id;
  if v_liquido is distinct from 19.000 or v_bruto is distinct from 19.500 then
    raise exception 'O peso do FAB-OS319-01 nao ficou gravado: liquido %, bruto %.', v_liquido, v_bruto;
  end if;
  if v_bruto < v_liquido then
    raise exception 'Peso bruto (%) menor que o liquido (%).', v_bruto, v_liquido;
  end if;
  raise notice 'FAB-OS319-01 com peso liquido % kg e bruto % kg.', v_liquido, v_bruto;
end
$peso$;
