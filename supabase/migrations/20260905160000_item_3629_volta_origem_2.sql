-- Fim do piloto do perfil de origem nacional (05/09/2026). O item 3629 volta
-- ao cadastro confirmado pelo responsavel: origem 2 (estrangeira, adquirida no
-- mercado interno). O perfil SEG-VENDA-TERCEIROS-SC-5102-O0-CST00 permanece
-- liberado para os itens nacionais.

update public.fiscal_itens
set origem = 2, atualizado_em = now()
where item_id = 3629
  and tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  and coalesce(origem, 0) <> 2;
