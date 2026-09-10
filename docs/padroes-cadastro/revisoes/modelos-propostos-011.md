# Modelos propostos — lote 011 Siemens

APLICAÇÃO PARCIAL SOB D-047. Dos 50 candidatos, 28 claros foram aplicados e verificados e 22 ficaram retidos sem alteração. Somente as regras do subconjunto claro foram incorporadas ao padrão 1.35.0. Trata-se de conferência técnica sob autorização condicional, não aprovação humana individual dos 50. As demais regras abaixo permanecem propostas.

50 IDs com grupo, sem repetição dos eventos aprovados. Tenant `3ced7cfa-efbb-4f0f-addc-2028f60d1ca7`; empresa `f0e74f49-a127-46b4-901b-f7b37e43c690`. Só nome e descrição complementar; nenhum campo comercial/técnico adicional será alterado.

## Regras propostas

- Diferenciais residuais: família, polos totais, corrente nominal, sensibilidade, tipo, tensão Un, frequência da variante e ação instantânea/retardada. Não somar neutro novamente; não chamar corrente condicional de curto de Icn, nem atribuir proteção de sobrecorrente integrada. Conferir condições de proteção a montante e circuito de teste.
- Bornes: função passagem/PE, seção nominal versus seção máxima por tipo de condutor, conexões/níveis, tecnologia, material/cor e valores operacionais confirmados. PE não vira PEN pelo título genérico. UL94 V0 não identifica polímero. Limites invertidos não são corrigidos silenciosamente. Passo, largura e seção são grandezas distintas.
- Tampas/pentes: função final/intermediária/transversal, compatibilidade, dimensões/passo e quantidade de polos. Foto ilustrativa não altera polos. Cores conflitantes ficam pendentes; corrente de alimentação do pente não é multiplicada pelos polos.
- Conexões de partida: união elétrica/mecânica, disjuntor e contator compatíveis, tamanho, polos e tipo de terminal. Kit reversor com intertravamento é diferente de ligação de dois contatores em série. CA/CC da bobina compatível não é alimentação do acessório; embalagem não altera fator.
- Atuadores: separados das chaves, princípio, formato/lado, ajuste, comprimento, material e famílias exatas. 67mm e 77mm não são intercambiáveis. Campo genérico de capa não prova cabo em atuador RFID; não acrescentar OSSD ao atuador passivo.
- Fontes: entrada e saída separadas, fases, faixas nominais versus admissíveis, seleção automática entre faixas versus faixa contínua, frequência, potência/corrente contínua e redução por temperatura. Não elevar potência ao ajustar tensão. Corrente de curto não é corrente nominal.
- UPS CC: módulo versus conjunto, entrada CC, saída normal/em bateria, pico com duração, isolamento e interfaces da variante. Autonomia depende de bateria/carga; não presumir bateria fornecida ou comunicação de outra versão.
- Interface: relé encaixável versus saída semicondutora fixa; reversível versus NA, transistor versus triac; entrada versus tensão/corrente da carga, AC-15/DC-13 e conexão. Corrente térmica não é carga universal. Não substituir produto por sucessor nem inativá-lo automaticamente.
- Relés monitores: funções da variante, faixa de rede do resumo versus medição/alimentação da tabela, frequência, contatos e conexão. Não confundir faixa monitorada com limiar ajustável nem monitor comum com relé de segurança.
- RJ45: Ethernet 10/100 versus Gigabit, contatos de conexão ao cabo versus portas, FastConnect, fios/AWG, saída angular, material e IP. Embalagem de 50 unidades exige conferência comercial separada; não alterar unidade/fator na revisão textual.
- Duplicidade: códigos equivalentes após normalização geram alerta, não fusão/exclusão. Preservar cada ID e seus movimentos. Nesta proposta, 2641/2642/2643 têm pares fora do lote 2698/2699/2700.

## Ressalvas e evidências

Fontes oficiais exatas em `backups/fontes-lote-011/`, com PDF, texto, páginas renderizadas e metadados. Hash/páginas/URL em cada item do manifesto. Conferência textual de todas as páginas usadas e visual de tabelas críticas conforme skill PDF. Não há PDF de entrega.

Conflitos expressos: 944/1616 (condutor encordoado); 1618 (cor e seção histórica); 957 (geração de contator); 1619 (faixa de corrente incompleta). Demais atributos não confirmados discriminados por ID. Uma redação aprovada não converte atributo ausente em certificado.

Fora do lote: 242/1583/1585/1586/1588 por ficha indisponível; consultar `pesquisa-adiada-011.json`. Retomar apenas com nova evidência/decisão, sem repeti-los automaticamente como nunca avaliados.

Manifesto congelado: `588f94f2467f6f9871276cb46677686cf52c6284dbd131e701b0432552417219`. Aplicação 011 bloqueada antes de conectar, inclusive com aprovação de outro lote. Após aprovação, registrar decisão própria e ativar critérios apenas no escopo aprovado.
