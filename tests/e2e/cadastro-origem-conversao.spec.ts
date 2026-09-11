import {test,expect} from '@playwright/test';

// Somente leituras reais da tela. Pesquisa e confirmação são interceptadas:
// não chama IA, não cadastra produto, não grava fiscal ou estoque de teste.
for(const permitido of [true,false])test(`cadastro assistido: origem e unidade redundante (permissão fiscal ${permitido})`,async({page},testInfo)=>{
  const erros:string[]=[];page.on('pageerror',e=>erros.push(e.message));
  await page.route('**/api/itens/agente-cadastro/sugerir',route=>route.fulfill({json:{
    cotacao_token:'fixture-sem-gravacao',pode_editar_fiscal:permitido,fontes:[],
    sugestao:{codigo:'VFCA12PD10M',descricao_padronizada:'CABO PARA SENSOR M12 4 PINOS',unidade_medida:'UN',unidade_compra:'UN',fator_conversao_estoque:1,grupo_id:46,grupo_nome:'Cabos',confianca:'alta',pesquisa_preco:{preco_final_brl:595.30}},
    fiscal_sugerido:{origem:0,ncm:'85444200',aliq_icms:4},
  }}));
  const envios:Record<string,unknown>[]=[];
  await page.route('**/api/itens/agente-cadastro/confirmar',async route=>{
    envios.push(route.request().postDataJSON());
    await route.fulfill({status:422,json:{error:'Teste: envio conferido, nenhum item gravado.'}});
  });
  await page.goto('/itens');
  await page.getByRole('button',{name:'Novo',exact:true}).click();
  const modal=page.getByRole('dialog',{name:'Cadastro de item assistido por IA'});
  const fornecedor=modal.getByRole('combobox',{name:'Fornecedor *',exact:true});
  await expect.poll(()=>fornecedor.locator('option').count()).toBeGreaterThan(1);
  const id=await fornecedor.locator('option').nth(1).getAttribute('value');
  await fornecedor.selectOption(id!);
  await modal.getByRole('textbox',{name:/^Código do produto/}).fill('VFCA12PD10M');
  await modal.getByRole('button',{name:'Gerar sugestão com IA'}).click();
  const origem=modal.getByRole('combobox',{name:'Origem',exact:true});
  if(permitido){
    await expect(origem).toBeEnabled();await expect(origem.locator('option')).toHaveCount(9);
    await origem.selectOption('2');
    await modal.getByLabel('NCM',{exact:true}).fill('85444200');
    await expect(origem).toHaveValue('2');
  }else await expect(origem).toBeDisabled();
  await origem.scrollIntoViewIfNeeded();
  await page.screenshot({path:testInfo.outputPath('origem.png')});
  await modal.getByRole('button',{name:'Confirmar cadastro',exact:true}).click();
  await expect.poll(()=>envios.length).toBe(1);
  const sugestao=envios[0].sugestao as Record<string,unknown>;
  expect(sugestao.unidade_compra).toBeNull();expect(sugestao.fator_conversao_estoque).toBe(1);
  expect(envios[0].preco_unitario_confirmado).toBe(595.30);
  if(permitido)expect((envios[0].fiscal_sugerido as Record<string,unknown>).origem).toBe(2);
  else expect(envios[0].fiscal_sugerido).toBeNull();
  await expect(modal.getByRole('alert')).toHaveText('Teste: envio conferido, nenhum item gravado.');
  expect(erros).toEqual([]);
});
