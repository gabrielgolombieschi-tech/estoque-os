import fs from "node:fs";
import { execFileSync } from "node:child_process";
const fontes = {
  mpw:"https://static.weg.net/medias/downloadcenter/h1b/h43/WEG-disjuntores-motores-linha-mpw-50009822-catalogo-portugues-br-dc.pdf",
  msw:"https://static.weg.net/medias/downloadcenter/h57/h5f/WEG-MSW-brochure-50161813-pt.pdf",
  cwb:"https://static.weg.net/medias/downloadcenter/hb6/h0a/WEG-contatores-CWB-50042424-pt.pdf",
  agw:"https://static.weg.net/medias/downloadcenter/h34/hef/WEG-disjuntor-em-caixa-moldada-agw-50051732-catalogo-portugues-br-dc.pdf",
  integradas:"https://static.weg.net/medias/downloadcenter/h24/h69/WEG-MDW-MDWH-QDW-SPW-RDW-DWP-50023623-en.pdf",
  cbw:"https://static.weg.net/medias/downloadcenter/h2b/hf5/WEG-CBW3-brocure-50157289-pt.pdf",
  mpw_de:"https://static.weg.net/medias/downloadcenter/he2/hf7/WEG-MPW-brochure-50161040-de.pdf",
  mini:"https://static.weg.net/medias/downloadcenter/hed/hd6/WEG-minicontatores-50009832-pt.pdf",
  rw:"https://static.weg.net/medias/downloadcenter/hcd/ha1/WEG-thermal-overload-relays-RW-50070227-en.pdf",
  fusiveis:"https://static.weg.net/medias/downloadcenter/h0a/h63/WEG-fusiveis-ar-e-gl-gg-50009817-catalogo-portugues-br-dc.pdf",
  cwbc:"https://static.weg.net/medias/downloadcenter/hda/hd6/WEG-CWBC-50101202-es.pdf",
  fsw:"https://static.weg.net/medias/downloadcenter/hb9/h69/WEG-chaves-seccionadoras-50022911-catalogo-portugues-br-dc.pdf",
  cwbs:"https://static.weg.net/medias/downloadcenter/hf5/h85/WEG-motoren-schalten-und-schutzen-german-market-only-50030773-de.pdf",
  dwp:"https://static.weg.net/medias/downloadcenter/h0a/h64/WEG-solucoes-integradas-para-instalacoes-eletricas-50009824-pt.pdf",
};
const pasta="backups/fontes-lote-007", bin="backups/fontes-lotes-003-004/poppler/poppler-26.07.0/Library/bin";
fs.mkdirSync(pasta,{recursive:true});
for(const [nome,url] of Object.entries(fontes)) {
  try {
    const path=`${pasta}/${nome}.pdf`;
    if(!fs.existsSync(path)) {
      const r=await fetch(url,{signal:AbortSignal.timeout(45000)});
      if(!r.ok) throw new Error(`HTTP ${r.status}`);
      const bytes=Buffer.from(await r.arrayBuffer());
      if(bytes.subarray(0,5).toString()!=="%PDF-") throw new Error("Resposta não é PDF");
      fs.writeFileSync(path,bytes,{flag:"wx"});
      fs.writeFileSync(`${pasta}/${nome}.fonte.json`,JSON.stringify({url,consultado_em:new Date().toISOString()},null,2),{flag:"wx"});
    }
    if(!fs.existsSync(`${pasta}/${nome}.txt`)) execFileSync(`${bin}/pdftotext.exe`,["-layout",path,`${pasta}/${nome}.txt`],{stdio:"ignore"});
    console.log(`${nome}: PDF preservado e texto extraído`);
  } catch(e) {console.log(`${nome}: ${e.message}`);}
}
