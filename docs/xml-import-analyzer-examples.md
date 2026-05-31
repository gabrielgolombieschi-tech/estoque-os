# Exemplos do motor local de analise XML/NF-e

Estes exemplos documentam entradas e saidas esperadas de `analyzeXmlImport`. O motor e puro: recebe dados ja carregados pela tela/API, nao chama Supabase, nao faz `fetch`, nao aplica sugestoes e nao altera o fluxo atual de importacao.

Os trechos abaixo sao resumidos para mostrar o contrato principal.

## 1. NF com fornecedor, campos obrigatorios e itens OK

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    chave: "35260000000000000000550010000012341000012345",
    numero: "1234",
    serie: "1",
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    valorTotal: 100,
    itens: [{ codigo: "00010", descricao: "Filtro oleo", quantidade: 2, valorUnit: 50 }],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [{ id: 15, codigo_interno: "10", nome: "Filtro oleo" }],
  pedidosCandidatos: [],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "OK",
  findings: [],
  warnings: [],
  fornecedorSuggestion: { status: "IDENTIFICADO", fornecedorId: 7 },
  itemSuggestions: [{ codigoOriginal: "00010", codigoNormalizado: "10", status: "CADASTRADO" }],
}
```

## 2. NF com fornecedor nao cadastrado

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor Novo",
    cnpjEmitente: "99888777000166",
    itens: [{ codigo: "A1", descricao: "Produto A", quantidade: 1, valorUnit: 10 }],
  },
  fornecedor: null,
  itensCadastradosPorCodigo: [{ id: 1, codigo_interno: "A1", nome: "Produto A" }],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "BLOQUEADO",
  findings: [{ code: "FORNECEDOR_NAO_ENCONTRADO", severity: "error" }],
  fornecedorSuggestion: { status: "NAO_ENCONTRADO", cnpj: "99888777000166" },
}
```

## 3. Item nao cadastrado com autocadastro permitido

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    itens: [{ codigo: "00020", descricao: "Correia", quantidade: 1, valorUnit: 30 }],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [],
  finalidadeSelecionada: "consumo",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
  parametros: {
    finalidadesExigemItemCadastrado: ["materia_prima"],
    finalidadesPermitemAutocadastro: ["consumo"],
  },
});
```

Saida resumida esperada:

```ts
{
  status: "ATENCAO",
  findings: [],
  suggestions: [{ code: "SUGERIR_CADASTRO_ITEM", severity: "info" }],
  warnings: [{ code: "XML_UNIDADE_NAO_EXTRAIDA", severity: "warning" }],
  itemSuggestions: [{ codigoNormalizado: "20", status: "NAO_CADASTRADO", severity: "info" }],
}
```

## 4. Item nao cadastrado com finalidade exigindo cadastro

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    itens: [{ codigo: "00030", descricao: "Rolamento", quantidade: 1, valorUnit: 80 }],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "BLOQUEADO",
  findings: [{ code: "ITEM_NAO_CADASTRADO", severity: "error" }],
  suggestions: [{ code: "SUGERIR_CADASTRO_ITEM", severity: "info" }],
  itemSuggestions: [{ codigoNormalizado: "30", status: "NAO_CADASTRADO", severity: "error" }],
}
```

## 5. Pedido provavel com itens batendo

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    valorTotal: 200,
    itens: [{ codigo: "0010", descricao: "Filtro oleo", quantidade: 4, valorUnit: 50 }],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [{ id: 15, codigo_interno: "10", nome: "Filtro oleo" }],
  pedidosCandidatos: [{
    id: "pedido-1",
    codigo: "PC-001",
    status: "ENVIADO",
    fornecedor_id: 7,
    solicitante_usuario_id: "usuario-2",
    total_pendente: 200,
    itens: [{ id: "pitem-1", item_id: 15, item_codigo: "10", item_nome: "Filtro oleo", quantidade: 4, quantidade_recebida: 0, valor_unitario: 50 }],
  }],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "OK",
  pedidoSuggestion: {
    pedidoId: "pedido-1",
    codigo: "PC-001",
    score: 100,
    itemMatches: [{ nfItemIndex: 0, pedidoItemId: "pitem-1", quantityStatus: "OK" }],
  },
  suggestions: [
    { code: "PEDIDO_CANDIDATO_PROVAVEL", severity: "info" },
    { code: "SUGERIR_SOLICITANTE_DO_PEDIDO", severity: "info" },
  ],
}
```

## 6. Divergencia de quantidade parcial

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    valorTotal: 200,
    itens: [{ codigo: "10", descricao: "Filtro oleo", quantidade: 4, valorUnit: 50 }],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [{ id: 15, codigo_interno: "10", nome: "Filtro oleo" }],
  pedidosCandidatos: [{
    id: "pedido-1",
    codigo: "PC-001",
    status: "ENVIADO",
    fornecedor_id: 7,
    total_pendente: 500,
    itens: [{ id: "pitem-1", item_id: 15, item_codigo: "10", item_nome: "Filtro oleo", quantidade: 10, quantidade_recebida: 0, valor_unitario: 50 }],
  }],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "ATENCAO",
  pedidoSuggestion: {
    pedidoId: "pedido-1",
    itemMatches: [{ nfItemIndex: 0, quantityStatus: "PARCIAL", quantidadeNf: 4, saldoPedido: 10 }],
  },
  warnings: [
    { code: "QUANTIDADE_PARCIAL_PEDIDO", severity: "warning" },
    { code: "DIVERGENCIA_TOTAL_PEDIDO_NF", severity: "warning" },
  ],
}
```

## 7. Possivel vinculo a dois pedidos

Entrada:

```ts
analyzeXmlImport({
  nfe: {
    emitente: "Fornecedor A",
    cnpjEmitente: "11222333000144",
    itens: [
      { codigo: "10", descricao: "Filtro oleo", quantidade: 2, valorUnit: 50 },
      { codigo: "20", descricao: "Correia", quantidade: 1, valorUnit: 80 },
    ],
  },
  fornecedor: { id: 7, nome: "Fornecedor A", cnpj: "11222333000144" },
  itensCadastradosPorCodigo: [
    { id: 15, codigo_interno: "10", nome: "Filtro oleo" },
    { id: 16, codigo_interno: "20", nome: "Correia" },
  ],
  pedidosCandidatos: [
    {
      id: "pedido-1",
      codigo: "PC-001",
      status: "ENVIADO",
      fornecedor_id: 7,
      solicitante_usuario_id: "usuario-2",
      itens: [{ id: "pitem-1", item_id: 15, item_codigo: "10", item_nome: "Filtro oleo", quantidade: 2, quantidade_recebida: 0, valor_unitario: 50 }],
    },
    {
      id: "pedido-2",
      codigo: "PC-002",
      status: "ENVIADO",
      fornecedor_id: 7,
      solicitante_usuario_id: "usuario-3",
      itens: [{ id: "pitem-2", item_id: 16, item_codigo: "20", item_nome: "Correia", quantidade: 1, quantidade_recebida: 0, valor_unitario: 80 }],
    },
  ],
  finalidadeSelecionada: "materia_prima",
  motivoSelecionadoId: "motivo-1",
  solicitanteUsuarioId: "usuario-1",
});
```

Saida resumida esperada:

```ts
{
  status: "ATENCAO",
  warnings: [{ code: "NF_POSSIVEL_MULTIPLOS_PEDIDOS", severity: "warning" }],
  pedidoSuggestion: {
    pedidoId: "pedido-1",
    score: 58,
  },
}
```
