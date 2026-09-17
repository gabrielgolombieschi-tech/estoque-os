-- Manutencao vai a 17%: os perfis de venda em SC precisam dizer isso.
--
-- Desde 10/09/2026 (contabilidade, OS 319) a aliquota interna acompanha a destinacao:
-- 12% quando a mercadoria segue em operacao tributada (revenda, insumo, consignacao) e
-- 17% quando para no adquirente (uso e consumo, ativo imobilizado E manutencao — manter o
-- proprio parque nao e industrializar nem revender). O montador ja recusa "manutencao a 12%"
-- (conflitoDestinacaoAliquota), mas os perfis de 12% ainda listavam MANUTENCAO nas
-- destinacoes e os de 17% nao: a conferencia da OV 363 (WEG Tintas, cilindro, 17/09/2026)
-- escolheu o perfil de 12% para "manutencao" e a emissao parou em "destinacao manutencao
-- exige aliquota interna de 17%, e a nota esta com 12%".
--
-- Aqui so a lista de destinacoes muda; CST, aliquota, cBenef e IBS/CBS dos perfis ficam
-- como estao. O perfil de automacao (SC820006, 12% pelo NCM) continua valendo para
-- manutencao: ali o beneficio e do produto, nao da destinacao.

update f.perfil_operacao
   set destinacoes_mercadoria = array['REVENDA', 'INSUMO', 'CONSIGNADO']::text[]
 where codigo in ('SEG-VENDA-TERCEIROS-SC-5102-O0-CST00', 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00')
   and aliquota_icms = 12
   and 'MANUTENCAO' = any(destinacoes_mercadoria);

update f.perfil_operacao
   set destinacoes_mercadoria = array['USO_CONSUMO', 'ATIVO_IMOBILIZADO', 'MANUTENCAO']::text[]
 where codigo in ('SEG-VENDA-TERCEIROS-SC-5102-O0-CST00-17', 'SEG-VENDA-TERCEIROS-SC-5102-O2-CST00-17')
   and aliquota_icms = 17
   and not ('MANUTENCAO' = any(destinacoes_mercadoria));
