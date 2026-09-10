-- Observacao no cadastro da PORTOBELLO: divergencia no cadastro deles sobre nos.
--
-- Gabriel em 09/09/2026, montando a NF-e da OS 288. A Portobello tem a Segau cadastrada
-- como "ELETRICA SEGAU LTDA - ME", em Rio Negrinho e com CNPJ em branco. A nota sai de
-- Joinville, CNPJ 13.671.448/0001-89, CRT 3 (regime normal, nao ME).
--
-- Nao muda nada na emissao — o emitente vem do nosso proprio cadastro fiscal. Fica
-- registrado porque e a explicacao pronta se o recebimento deles recusar a nota por
-- divergencia de fornecedor, e porque o Gabriel vai tratar com a compradora.

update public.clientes
   set observacoes = trim(both e'\n' from
         coalesce(nullif(btrim(observacoes), '') || e'\n\n', '')
         || '[09/09/2026] Cadastro deles sobre nos esta divergente: consta "ELETRICA SEGAU LTDA - ME", '
         || 'em Rio Negrinho e com CNPJ em branco. O correto e ELETRICA SEGAU LTDA, Joinville/SC, '
         || 'CNPJ 13.671.448/0001-89, IE 257686835, CRT 3 (regime normal, nao ME). '
         || 'A ser corrigido com a compradora; nao afeta a emissao das nossas notas.'),
       atualizado_em = now()
 where id = 1
   and documento = '83475913000272'
   and coalesce(observacoes, '') not like '%Cadastro deles sobre nos esta divergente%';
