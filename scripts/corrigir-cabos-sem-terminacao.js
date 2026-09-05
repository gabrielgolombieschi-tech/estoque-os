/* eslint-disable @typescript-eslint/no-require-imports */
/*
 * Normaliza cabos elétricos vendidos sem conector, plugue, terminal ou adaptador.
 *
 * Escopo revisado: cabos unipolares, multipolares de potência e cabos de
 * controle/sinal sem terminação. Sem --apply, apenas diagnostica. A descrição
 * fiscal da NF-e não é alterada.
 */
const fs = require("fs");
const { createClient } = require("@supabase/supabase-js");

const TENANT_ID = "3ced7cfa-efbb-4f0f-addc-2028f60d1ca7";
const EMPRESA_ID = "f0e74f49-a127-46b4-901b-f7b37e43c690";
const GRUPO_CABOS_ELETRICOS = 138;
const GRUPO_CABOS_SINAL_COMANDO = 165;
const APPLY = process.argv.includes("--apply");

const propostas = new Map();
const revisados = new Map();
const pendencias = new Map();

function propor(id, codigo, nome, grupoId) {
  if (revisados.has(id)) throw new Error(`Item ${id} repetido no roteiro.`);
  propostas.set(id, { codigo, nome, grupoId });
  revisados.set(id, codigo);
}

function pendente(id, codigo, motivo) {
  if (revisados.has(id)) throw new Error(`Item ${id} repetido no roteiro.`);
  pendencias.set(id, { codigo, motivo });
  revisados.set(id, codigo);
}

const cores = {
  AM: "AMARELO",
  AZ: "AZUL",
  "AZ CL": "AZUL CLARO",
  "AZ ESC": "AZUL ESCURO",
  "AZ/ESC": "AZUL ESCURO",
  BC: "BRANCO",
  CZ: "CINZA",
  LJ: "LARANJA",
  LR: "LARANJA",
  MR: "MARROM",
  PT: "PRETO",
  "V/A": "VERDE/AMARELO",
  VD: "VERDE",
  "VD/AM": "VERDE/AMARELO",
  VM: "VERMELHO",
};

// Cabos flexíveis unipolares 450/750V sem família confirmada na origem.
for (const [id, codigo, secao, cor] of [
  [550, "3829", "16", "PT"],
  [652, "8900026465", "2,5", "VD"],
  [1342, "8900026465-DUP1342", "2,5", "VD"],
  [1956, "3774", "0,5", "LR"],
  [1957, "3773", "0,5", "MR"],
  [1975, "3863", "4", "PT"],
  [1976, "21259", "4", "VM"],
  [1977, "21219", "1,5", "VM"],
  [1978, "21235", "1,5", "BC"],
  [1979, "21256", "4", "BC"],
  [2007, "3587", "0,5", "AZ ESC"],
  [2008, "24405", "0,5", "VD/AM"],
  [2161, "3869", "4", "VM"],
  [2162, "3861", "4", "BC"],
  [2163, "21246", "1", "BC"],
  [2635, "3830", "16", "VD"],
  [2636, "3827", "16", "AZ CL"],
  [2637, "3798", "1", "PT"],
  [2787, "27232", "0,5", "LR"],
  [2788, "27245", "1,5", "LR"],
  [2789, "21234", "1,5", "AZ"],
  [2872, "3794", "1", "BC"],
  [2873, "3777", "0,5", "VM"],
  [2982, "3771", "0,5", "BC"],
  [2983, "21266", "0,5", "AZ"],
  [2984, "3793", "1", "AZ ESC"],
  [2985, "27239", "1", "LR"],
  [2986, "3801", "1", "VM"],
  [2987, "3800", "1", "VD/AM"],
  [2988, "3842", "2,5", "PT"],
  [2989, "27247", "1,5", "AZ ESC"],
  [2990, "21225", "0,5", "AZ ESC"],
  [3526, "3775", "0,5", "PT"],
  [3527, "27243", "1,5", "VD/AM"],
  [3528, "21265", "2,5", "AZ"],
  [3529, "27251", "2,5", "CZ"],
  [3532, "3812", "1,5", "VM"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL UNIPOLAR 1X${secao}MM² 450/750V ISOLAÇÃO PVC SEM CAPA SEM BLINDAGEM ${cores[cor]}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// Cabos BWF identificados documentalmente como Corfio, RCM ou Cobrecom.
for (const [id, codigo, secao, cor] of [
  [579, "54028026583", "1", "VD"],
  [1533, "54028077483", "10", "PT"],
  [1941, "905", "1,5", "AZ ESC"],
  [2264, "54028001583", "0,5", "AM"],
  [2266, "54028003583", "0,5", "BC"],
  [2267, "54028005583", "0,5", "MR"],
  [2268, "54028275583", "0,5", "AZ/ESC"],
  [2269, "54028163583", "0,5", "LJ"],
  [2791, "54028045583", "2,5", "PT"],
  [3106, "54028048483", "2,5", "V/A"],
  [3107, "54028077583", "10", "PT"],
  [3274, "54028077483", "10", "PT"],
  [3275, "54028067089", "6", "PT"],
  [3276, "54028058089", "4", "PT"],
  [3530, "54028009583", "0,5", "VM"],
  [3531, "54028295583", "1,5", "CZ"],
  [3561, "54028027583", "1", "VM"],
  [3583, "54028069583", "6", "V/A"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL UNIPOLAR BWF 1X${secao}MM² 450/750V ISOLAÇÃO PVC SEM CAPA SEM BLINDAGEM ${cores[cor]}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// Cabos de potência HEPR Corfio/Cobrecom, 0,6/1kV, com cobertura PVC.
for (const [id, codigo, formacao, cor] of [
  [1135, "54034086583", "1X10", "BC"],
  [1137, "54034088583", "1X16", "BC"],
  [1138, "54034087583", "1X10", "VM"],
  [1143, "54034089583", "1X16", "VM"],
  [1461, "54034059583", "3X10", "PT"],
  [1530, "54034017583", "1X16", "PT"],
  [1532, "54034016583", "1X16", "AZ"],
  [2341, "54034016089", "1X16", "AZ"],
  [2342, "54034088089", "1X16", "BC"],
  [2343, "54034017089", "1X16", "PT"],
  [2344, "54034018089", "1X16", "VD"],
  [2345, "54034089089", "1X16", "VM"],
  [3241, "54034027583", "1X50", "VD"],
  [3242, "54034029583", "1X70", "PT"],
  [3303, "54034020089", "1X25", "PT"],
  [3304, "54034021089", "1X25", "VD"],
  [3581, "54034069583", "4X6", "PT"],
]) {
  const polaridade = formacao.startsWith("1X") ? "UNIPOLAR" : "MULTIPOLAR";
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL ${polaridade} ${formacao}MM² 0,6/1kV ISOLAÇÃO HEPR CAPA PVC SEM BLINDAGEM ${cores[cor]}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// Cabos de potência cuja origem confirma EPR, mas não uma família comercial.
for (const [id, codigo, secao, cor] of [
  [1422, "1418", "240", "PT"],
  [2629, "3666", "16", "PT"],
  [2630, "3682", "16", "BC"],
  [2631, "3688", "16", "VM"],
  [2632, "3696", "16", "VD"],
  [3301, "25682", "25", "PT"],
  [3302, "25683", "25", "VD"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL UNIPOLAR 1X${secao}MM² 0,6/1kV ISOLAÇÃO EPR CAPA PVC SEM BLINDAGEM ${cores[cor]}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// Cabos PP: PP é a família construtiva; isolação e capa são ambas de PVC.
for (const [id, codigo, formacao, cor] of [
  [1172, "4152", "4G2,5", null],
  [2296, "1302", "4X4", null],
  [2297, "228", "2X1,5", null],
  [3320, "54042014583", "3X1,5", "PT"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL MULTIPOLAR PP ${formacao}MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM${cor ? ` ${cores[cor]}` : ""}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// SIL FlexSil 750V e SilFlex PP 500V.
for (const [id, codigo, secao, cor] of [
  [3423, "243", "10", "AZ"],
  [3691, "3.012.002.1.23", "0,5", "PT"],
  [3692, "3.012.003.1.23", "0,5", "BC"],
  [3693, "3.012.004.1.23", "0,5", "AZ"],
  [3694, "3.012.005.1.23", "0,5", "VM"],
  [3695, "3.016.002.1.23", "1", "PT"],
  [3696, "3.016.003.1.23", "1", "BC"],
  [3697, "3.016.005.1.23", "1", "VM"],
  [3698, "3.017.004.1.23", "1,5", "AZ"],
  [3699, "3.016.017.1.23", "1", "LR"],
  [3700, "3.017.015.1.23", "1,5", "AZ ESC"],
  [3703, "3.021.002.1.23", "10", "PT"],
  [3704, "3.020.002.1.23", "6", "PT"],
  [3705, "3.019.002.1.23", "4", "PT"],
  [3710, "3.018.005.1.23", "2,5", "VM"],
  [3711, "3.018.014.1.23", "2,5", "VD/AM"],
  [3712, "3.018.002.1.23", "2,5", "PT"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL UNIPOLAR FLEXSIL 1X${secao}MM² 450/750V ISOLAÇÃO PVC SEM CAPA SEM BLINDAGEM ${cores[cor]}`,
    GRUPO_CABOS_ELETRICOS,
  );
}

for (const [id, codigo, formacao] of [
  [3701, "404.037.002.1.23", "4X2,5"],
  [3702, "404.036.002.1.23", "4X1,5"],
]) {
  propor(
    id,
    codigo,
    `CABO ELÉTRICO FLEXÍVEL MULTIPOLAR SILFLEX PP ${formacao}MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM PRETO`,
    GRUPO_CABOS_ELETRICOS,
  );
}

// HELUKABEL: cabo de potência HEPR e famílias JZ-500/PUR-JZ.
propor(3727, "18036192", "CABO ELÉTRICO FLEXÍVEL MULTIPOLAR 3X4MM² 0,6/1kV ISOLAÇÃO HEPR CAPA PVC SEM BLINDAGEM", GRUPO_CABOS_ELETRICOS);
for (const [id, codigo, formacao] of [
  [3728, "18037499", "5G0,5"],
  [3729, "18037506", "12G0,5"],
  [3730, "18037512", "21G0,5"],
  [3731, "18037513", "25G0,5"],
]) {
  propor(id, codigo, `CABO DE CONTROLE FLEXÍVEL JZ-500 ${formacao}MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM`, GRUPO_CABOS_SINAL_COMANDO);
}
for (const [id, codigo, formacao] of [
  [3732, "18043995", "5G0,5"],
  [3734, "18043996", "12G0,5"],
  [3735, "18043997", "20G0,5"],
  [3736, "18043998", "25G0,5"],
  [3737, "18043999", "35G0,5"],
  [3738, "18044000", "21G1"],
]) {
  propor(id, codigo, `CABO DE CONTROLE FLEXÍVEL PUR-JZ ${formacao}MM² 300/500V ISOLAÇÃO PVC CAPA PUR SEM BLINDAGEM`, GRUPO_CABOS_SINAL_COMANDO);
}

// LAPP: famílias e construções confirmadas em fichas oficiais.
for (const [id, codigo, formacao] of [
  [704, "27538", "25G0,5"],
  [705, "27536", "18G0,5"],
]) {
  propor(id, codigo, `CABO DE CONTROLE PARA MOVIMENTAÇÃO CONTÍNUA ÖLFLEX FD 855 P ${formacao}MM² 300/500V ISOLAÇÃO TPE CAPA PUR SEM BLINDAGEM`, GRUPO_CABOS_SINAL_COMANDO);
}
propor(3460, "FAB-030152", "CABO DE CONTROLE FLEXÍVEL YSLY-JZ 25G1,5MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM CINZA", GRUPO_CABOS_SINAL_COMANDO);
for (const [id, codigo, formacao] of [
  [3461, "1119225", "25G1"],
  [3462, "1119212", "12G1"],
]) {
  propor(id, codigo, `CABO DE CONTROLE FLEXÍVEL ÖLFLEX CLASSIC 110 ${formacao}MM² 300/500V ISOLAÇÃO PVC CAPA PVC SEM BLINDAGEM`, GRUPO_CABOS_SINAL_COMANDO);
}

// Tramar NTT 01, construção confirmada pelo fabricante.
propor(
  3323,
  "54033023839",
  "CABO ELÉTRICO FLEXÍVEL UNIPOLAR TRAMASIL SF REDUZIDO 1X10MM² 450/750V ISOLAÇÃO SILICONE PROTEÇÃO EXTERNA TRANÇADA DE FIBRA DE VIDRO IMPREGNADA COM VERNIZ SEM BLINDAGEM BRANCO 200°C",
  GRUPO_CABOS_ELETRICOS,
);

// Itens mantidos sem alteração: os atributos obrigatórios não estão confirmados.
for (const [id, codigo, motivo] of [
  [706, "546029007A", "Confirmar materiais da isolação e capa externa do Fieldbus e a construção BF+T."],
  [707, "511A61028A", "Confirmar materiais da isolação e capa externa do cabo manga."],
  [708, "512160028A", "Confirmar materiais da isolação e capa externa do cabo manga."],
  [709, "542704010A", "Confirmar materiais da isolação e capa externa e o significado completo de SCI."],
  [710, "511A99028A", "Confirmar materiais da isolação e capa externa do cabo manga."],
  [711, "512017028A", "Confirmar materiais da isolação e capa externa e o material da blindagem BT."],
  [712, "512018028A", "Confirmar materiais da isolação e capa externa e o material da blindagem BF."],
  [713, "542650010A", "Confirmar materiais da isolação e capa externa e o material da blindagem BT."],
  [714, "542A77010A", "Confirmar materiais da isolação e capa externa e ausência/presença de blindagem."],
  [715, "542069010A", "Confirmar materiais da isolação e capa externa e ausência/presença de blindagem."],
  [716, "542068010A", "Confirmar materiais da isolação e capa externa e ausência/presença de blindagem."],
  [717, "542066010A", "Confirmar materiais da isolação e capa externa e ausência/presença de blindagem."],
  [718, "544740010A", "Confirmar materiais da isolação e capa externa; NBR 7290 admite construções distintas."],
  [1176, "3525", "Confirmar isolação, capa externa e blindagem do cabo multipolar 4X6MM²."],
  [1415, "27462", "Confirmar a referência LAPP: código e formação informados são conflitantes com o catálogo oficial."],
  [2006, "3935", "Confirmar isolação, capa externa e blindagem do cabo de controle 5X6MM²."],
  [2531, "2961", "Confirmar classe de tensão, isolação, capa externa e blindagem."],
  [2543, "20859", "Confirmar classe de tensão e materiais da isolação, capa e malha."],
  [2893, "54037069319", "Confirmar no documento do fabricante os materiais da isolação, capa e blindagem BTC."],
  [3014, "1100140001", "Confirmar se a formação correta é 4X1,5MM² ou 4X15MM² e os materiais da construção."],
  [3016, "1110130002", "Confirmar se a formação correta é 6X1MM² ou 6X10MM², além de isolação, capa e blindagem."],
  [3017, "1100140002", "Confirmar se a formação correta é 4X2,5MM² ou 4X25MM² e os materiais da construção."],
  [3265, "54034018089-COPIA", "Confirmar código de origem, material e cor; o código-base pertence a outro item de 16MM²."],
  [3266, "54034018089-COPIA-COPIA", "Confirmar código de origem, material e cor; o código-base pertence a outro item de 16MM²."],
]) pendente(id, codigo, motivo);

if (revisados.size !== 143 || propostas.size !== 119 || pendencias.size !== 24) {
  throw new Error(`Roteiro incompleto: ${revisados.size} revisados, ${propostas.size} propostas e ${pendencias.size} pendências.`);
}

const env = {};
for (const line of fs.readFileSync(".env.local", "utf8").split(/\r?\n/)) {
  const i = line.indexOf("=");
  if (i <= 0) continue;
  env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^['"]|['"]$/g, "");
}

const supabase = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function main() {
  const ids = [...revisados.keys()];
  const { data: itens, error } = await supabase
    .from("itens")
    .select("id,codigo_interno,nome,grupo_id,fornecedor_id,unidade_medida,ativo")
    .eq("tenant_id", TENANT_ID)
    .eq("empresa_id", EMPRESA_ID)
    .in("id", ids)
    .order("id");
  if (error) throw error;
  if (itens.length !== revisados.size) {
    throw new Error(`Proteção de escopo: esperados ${revisados.size} itens, encontrados ${itens.length}.`);
  }

  for (const item of itens) {
    if (item.codigo_interno !== revisados.get(item.id)) {
      throw new Error(`Proteção de escopo: o item ${item.id} não corresponde ao código esperado.`);
    }
    // A unidade comercial atual é preservada: há cadastros legítimos em M, MT,
    // KM e UN e este roteiro trata somente nome técnico e grupo funcional.
  }

  const alteracoes = itens
    .filter((item) => propostas.has(item.id))
    .map((item) => {
      const proposta = propostas.get(item.id);
      return {
        id: item.id,
        codigo: item.codigo_interno,
        nomeAtual: item.nome,
        nomeProposto: proposta.nome,
        grupoIdAtual: item.grupo_id,
        grupoIdProposto: proposta.grupoId,
      };
    })
    .filter((item) => item.nomeAtual !== item.nomeProposto || item.grupoIdAtual !== item.grupoIdProposto);

  console.log(JSON.stringify({
    modo: APPLY ? "APLICAR" : "DIAGNOSTICO",
    escopo: "cabos sem conector, plugue, terminal ou adaptador nas pontas",
    totalRevisado: revisados.size,
    tecnicamenteCompletos: propostas.size,
    alteracoesNecessarias: alteracoes.length,
    semAlteracaoPorFaltaDeDados: pendencias.size,
    alteracoes,
    pendencias: [...pendencias].map(([id, value]) => ({ id, ...value })),
  }, null, 2));

  if (!APPLY) return;
  for (const item of alteracoes) {
    const { data, error: updateError } = await supabase
      .from("itens")
      .update({ nome: item.nomeProposto, grupo_id: item.grupoIdProposto, atualizado_em: new Date().toISOString() })
      .eq("tenant_id", TENANT_ID)
      .eq("empresa_id", EMPRESA_ID)
      .eq("id", item.id)
      .eq("codigo_interno", item.codigo)
      .eq("nome", item.nomeAtual)
      .select("id")
      .single();
    if (updateError || !data) throw new Error(`Item ${item.id}: ${updateError?.message ?? "não atualizado"}`);
  }
  console.log(JSON.stringify({ aplicado: true, itensAtualizados: alteracoes.length }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
