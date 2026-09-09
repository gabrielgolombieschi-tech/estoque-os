-- Completa o perfil do Convenio 52/91 com os campos que a selecao exige.
--
-- Gabriel, 09/09/2026. O perfil criado em 20260909180000 nunca era escolhido: a
-- consulta de f.fn_os_nfe_conferir_homologacao filtra por "ufs_destino is not null and
-- destino = any(ufs_destino)" e por "origem_mercadoria = origem do item", e o insert
-- de la nao copiou esses dois campos nem o crt do perfil modelo. Com eles nulos o
-- perfil ficava fora do resultado e a conferencia caia no generico de CST 00 — foi o
-- que aconteceu na primeira tentativa de reemitir a ARCELORMITTAL.

update f.perfil_operacao alvo
   set ufs_destino = modelo_perfil.ufs_destino,
       origem_mercadoria = modelo_perfil.origem_mercadoria,
       crt = modelo_perfil.crt
  from f.perfil_operacao modelo_perfil
 where alvo.codigo = 'SEG-IND-SC-5101-O0-CST20-CONV5291'
   and modelo_perfil.codigo = 'SEG-IND-SC-5101-O0-CST00-17'
   and modelo_perfil.tenant_id = alvo.tenant_id
   and modelo_perfil.empresa_id = alvo.empresa_id
   and (alvo.ufs_destino is null or alvo.origem_mercadoria is null);
