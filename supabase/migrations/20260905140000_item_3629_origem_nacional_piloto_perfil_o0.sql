-- Piloto do perfil de origem nacional (05/09/2026, autorizado pelo responsavel).
--
-- O item 3629 (PLC CQM1HCPU61) foi confirmado como origem 2 hoje, mas a
-- maioria dos itens revendidos e nacional (origem 0) e o perfil
-- SEG-VENDA-TERCEIROS-SC-5102-O0-CST00 ainda nao tem evidencia posterior a
-- revisao. Para liberar esse perfil com a mesma OV 344, o item passa a origem 0
-- durante o piloto; a nota real resultante sera cancelada em seguida.
-- Depois do piloto, o cadastro deve voltar a origem 2 (decisao do responsavel).

update public.fiscal_itens
set origem = 0, atualizado_em = now()
where item_id = 3629
  and tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'
  and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'
  and coalesce(origem, 0) <> 0;
