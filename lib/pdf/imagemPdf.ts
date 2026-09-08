// Carregamento e medicao de imagem para os PDFs, sem depender do DOM.
//
// Os geradores de PDF rodavam so no navegador e usavam FileReader (para virar
// data URL) e `new Image()` (para medir). Agora os mesmos geradores precisam
// rodar tambem no servidor, para o aplicativo baixar o arquivo pronto.
//
// Medir pelos bytes, e nao pelo decodificador de imagem do navegador, e o que
// garante que o PDF sai igual nos dois lados: o mesmo arquivo produz o mesmo
// par largura/altura em qualquer ambiente.

/** Como o chamador busca a imagem. O navegador faz fetch; o servidor le do disco. */
export type CarregadorDeImagem = (caminho: string) => Promise<string | null>;

function bytesDaDataUrl(dataUrl: string): Uint8Array | null {
  const virgula = dataUrl.indexOf(",");
  if (virgula < 0) return null;
  const base64 = dataUrl.slice(virgula + 1);
  try {
    const binario = atob(base64);
    const bytes = new Uint8Array(binario.length);
    for (let i = 0; i < binario.length; i += 1) bytes[i] = binario.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

function tamanhoPng(bytes: Uint8Array): { width: number; height: number } | null {
  // Assinatura PNG (8 bytes) + comprimento do chunk (4) + "IHDR" (4);
  // largura e altura vem logo em seguida, big-endian.
  if (bytes.length < 24) return null;
  const assinatura = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  for (let i = 0; i < assinatura.length; i += 1) {
    if (bytes[i] !== assinatura[i]) return null;
  }
  const visao = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: visao.getUint32(16), height: visao.getUint32(20) };
}

function tamanhoJpeg(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  const visao = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  let i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] !== 0xff) {
      i += 1;
      continue;
    }
    const marcador = bytes[i + 1];

    // SOFn carrega as dimensoes, menos os marcadores de tabela/reinicio
    // (0xC4, 0xC8, 0xCC) que caem na mesma faixa.
    const ehSof =
      marcador >= 0xc0 &&
      marcador <= 0xcf &&
      marcador !== 0xc4 &&
      marcador !== 0xc8 &&
      marcador !== 0xcc;

    if (ehSof) {
      return { height: visao.getUint16(i + 5), width: visao.getUint16(i + 7) };
    }

    const tamanhoSegmento = visao.getUint16(i + 2);
    if (tamanhoSegmento < 2) return null;
    i += 2 + tamanhoSegmento;
  }
  return null;
}

/** Largura e altura lidas dos proprios bytes — mesmo resultado no navegador e no servidor. */
export function tamanhoNaturalDaImagem(dataUrl: string | null): { width: number; height: number } | null {
  if (!dataUrl) return null;
  const bytes = bytesDaDataUrl(dataUrl);
  if (!bytes) return null;

  const tamanho = tamanhoPng(bytes) ?? tamanhoJpeg(bytes);
  if (!tamanho) return null;
  if (!Number.isFinite(tamanho.width) || !Number.isFinite(tamanho.height)) return null;
  if (tamanho.width <= 0 || tamanho.height <= 0) return null;
  return tamanho;
}

/** Carregador do navegador: busca a imagem servida em /public e devolve data URL. */
export const carregarImagemNoNavegador: CarregadorDeImagem = async (caminho) => {
  try {
    const res = await fetch(caminho);
    if (!res.ok) return null;
    const buffer = await res.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binario = "";
    for (let i = 0; i < bytes.length; i += 1) binario += String.fromCharCode(bytes[i]);
    const tipo = res.headers.get("content-type") || "image/png";
    return `data:${tipo};base64,${btoa(binario)}`;
  } catch {
    return null;
  }
};
