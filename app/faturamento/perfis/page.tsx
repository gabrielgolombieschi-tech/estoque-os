import PerfisFiscaisClient from "./PerfisFiscaisClient";

type PageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const OV_PATH = /^\/comercial\/vendas\/(?:[1-9]\d*|[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i;
const PROFILE_KEY = /^[A-Za-z0-9][A-Za-z0-9_-]{0,119}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function first(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : value;
}

function safeOvReturn(value: string | undefined) {
  if (!value || value.length > 180 || value.includes("\\") || !OV_PATH.test(value)) {
    return "/faturamento/nfe";
  }
  return value;
}

function safeProfileKey(value: string | undefined) {
  if (!value || !PROFILE_KEY.test(value)) return null;
  return value;
}

function safeUuid(value: string | undefined) {
  return value && UUID.test(value) ? value : null;
}

export default async function PerfisFiscaisPage({ searchParams }: PageProps) {
  const params = await searchParams;
  const retorno = safeOvReturn(first(params.retorno));
  const perfilInicial = safeProfileKey(first(params.perfil));
  const solicitacaoInicial = safeUuid(first(params.solicitacao));

  return (
    <PerfisFiscaisClient
      retorno={retorno}
      perfilInicial={perfilInicial}
      solicitacaoInicial={solicitacaoInicial}
    />
  );
}
