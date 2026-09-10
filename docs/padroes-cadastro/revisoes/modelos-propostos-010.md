# Modelos propostos — lote 010 Siemens

APROVADO por “pode alterar” em 10/09/2026. Incorporado ao padrão 1.34.0/D-046. Aprovação vinculada à assinatura em aprovacao-010.json; aplicação conferida em eventos-010-cinquenta-itens.json. Nome histórico do arquivo preservado. Aprovação do lote 010 não autoriza os seguintes.

50 IDs agrupados: 47 SIRIUS ACT e três chaves SIRIUS 3SE. Escopo tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`, empresa `f0e74f49-a127-46b4-901b-f7b37e43c690`. Só nome e descrição; preservados códigos, grupos, unidades/conversões e demais campos.

## Regras aprovadas

- Separar cabeçote avulso, módulo LED/contato, suporte, caixa vazia e conjunto completo. Iluminável não significa LED fornecido; posições de seletor não determinam NA/NF. Confirmar lista de componentes da referência, não aparência.
- Pulsadores: família, classe de montagem, cor, geometria, momentâneo/retentivo, material do atuador versus aro, contatos e LED quando incluídos. Linha metálica pode ter atuador plástico; não chamar todo o botão de metal.
- Emergência: cogumelo preto de comando não vira parada de emergência. Confirmar função, travamento/destravamento, contatos e placa incluídos. 967 retentivo com giro e 3566 momentâneo são diferentes. 2139 inclui dois blocos 1NF, não apenas cabeçote.
- Seletores: posições, ângulos, retorno ao centro ou retenção, cor, manopla e montagem. 2137 tem 1NA+1NF e suporte, mas zero LED. Cabeçotes ilumináveis não têm alimentação definida sem módulo.
- Sinaleiros/LED: alimentação, tipo CA/CC, frequência em CA e cor da referência exata. Ui/isolação não é alimentação. ID 1695 confirma 24VCA/CC, não 220VCA/CC; ID 1689 é 230VCA, não CC. Não inferir tensão da família ou do código sem ficha.
- Contatos: número/tipo e conexão, categorias e tensão associadas à corrente. Corrente térmica 10A não significa AC-15 10A em qualquer tensão. IP do corpo/terminal diferente do frontal. ID 215 mantém 1NF do resumo e catálogo, mas divergência da tabela que lista NA continua PARCIAL; exigir placa/diagrama antes de dimensionar.
- Suportes: três posições não são três contatos incluídos; ficha admite seis módulos conforme montagem. Compatibilidade com linha metálica não torna suporte inteiramente metálico. Pedido mínimo de cinco peças não altera multiplicador.
- Caixas: vazias versus equipadas, postos, classe/furo de montagem, material/cor, dimensões com ordem dos eixos e entradas. Não presumir prensa-cabos incluídos; IP depende da vedação e instalação correta.
- Acessórios: identificar função real, material, cor, dimensões e compatibilidade. Capas de silicone deste lote são IP66/IP67, sem estender a IP69K. Placa prateada pode ser plástica; sem inscrição não significa texto já impresso. Dimensão da etiqueta não é dimensão do porta-etiqueta. 1690 comporta cinco cadeados, sem presumir fornecimento; 1693 bloqueia cogumelo acionado.
- Segurança RFID: codificação, alcance operacional versus assegurado, OSSD/OUT e limites específicos; não trocar modelo por alternativa comercial citada. No 1627, diagrama confirma duas OSSD e saída OUT; não copiar corrente de linha genérica para OSSD.
- Magnético reed: contatos, ímã/avaliação necessários, cabo/material/seção e alcances. Limites de tensão, corrente e potência devem coexistir: 100V, 250mA e 3W não autorizam 250mA em 100V. PL/SIL dependem da instalação/avaliação, não apenas do cadastro.
- Trava mecânica: bloqueio por mola versus energização, bobina, liberações, conjuntos de contatos separados e entradas/conexão. Força segundo ISO14119 separada de valor genérico: ID 3567 usa 2000N ISO14119, mantendo 2600N como outra definição na descrição. Atuador não incluído.

## Evidências e retomada

Fichas oficiais exatas em `backups/fontes-lote-010/`, com textos, páginas renderizadas e hashes no manifesto. Todas as páginas técnicas usadas foram lidas em texto; tabelas relevantes de cada tipo e divergências conferidas visualmente conforme skill PDF. Não há PDF de entrega.

Manifesto original congelado preservado. Aprovação específica registrada; somente nome/descrição autorizados, com comparação concorrente, backup e releitura antes de emitir eventos. Ressalva do ID 215 e demais limites permanecem. Não declarar sensores/CLPs/painéis 100% concluídos com um lote parcial por marca.
