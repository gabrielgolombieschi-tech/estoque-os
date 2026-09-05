# Testes de browser (Playwright)

Dirigem a aplicação num Chromium de verdade: login, navegação e interação com a tela,
contra o `npm run dev` local.

## Rodar

```bash
npm run test:e2e            # headless
npm run test:e2e:headed     # abre o navegador na tela
npm run test:e2e:ui         # modo interativo, passo a passo
npm run test:e2e:report     # abre o último relatório HTML
```

O `playwright.config.ts` sobe o `npm run dev` sozinho; se já houver um servidor na 3000,
ele reaproveita.

## Credenciais

Ficam em `.env.e2e.local`, na raiz (fora do git — o `.gitignore` cobre `.env*`):

```
E2E_EMAIL=...
E2E_PASSWORD=...
E2E_BASE_URL=http://localhost:3000
```

O `auth.setup.ts` loga uma vez e grava a sessão em `.auth/user.json`; os demais testes
já começam autenticados, sem repetir o login.

## Qual banco

O teste fala com o mesmo Supabase que o `.env.local` aponta. **Não há sandbox**: o que
o teste escrever, escreve pra valer. Por isso todo teste que cria dado deve desfazer o
que criou no final — veja a etapa de limpeza em `os-adicionar-item.spec.ts`.

## Escrevendo um teste novo

Duas armadilhas desta aplicação, ambas já resolvidas no teste existente:

- **A tabela chega vazia e é preenchida por fetch.** Ler o estado inicial logo após o
  `goto` pega a tela ainda em "Carregando...". Espere duas leituras iguais antes de
  considerar o estado inicial válido (`carimbosEstaveis`).
- **A 1ª coluna da tabela de itens é o ID do item de catálogo, não o da linha.** Ela se
  repete quando o mesmo item entra duas vezes. Para identificar uma linha específica,
  use a coluna "Data", que tem hora e segundo.

Outros detalhes: `/os` cai em `?vista=cliente` (cards, sem tabela) — use `?vista=lista`;
e o modal "Localizar item" tem um botão "Buscar" homônimo ao da página por baixo, então
escope os seletores ao modal.

## Arquivos `_*.spec.ts`

São andaimes descartáveis (diagnóstico, limpeza pontual de dados que um teste deixou
para trás). O `testIgnore` do config mantém todos fora da suíte. Pode apagar.

## Saída

- `.saida/passos/` — capturas de cada etapa, numeradas
- `.saida/` — capturas, traces e contexto das falhas
- `.relatorio/` — relatório HTML

Nada disso é versionado.
