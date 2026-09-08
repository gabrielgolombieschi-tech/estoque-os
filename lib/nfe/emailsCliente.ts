// E-mails de entrega da NF-e (XML + DANFE) a partir do cadastro do cliente.
//
// Regra: o "e-mail financeiro" vem primeiro, depois o principal — mas nunca um
// endereco no dominio do e-mail fiscal da propria empresa emitente. Na PBG S/A o
// financeiro veio gravado como CONTATO@SEGAU.COM.BR e a tela oferecia a Segau
// como destinataria da nota da Portobello.

export type ContatoNfe = {
  cliente?: { email?: string | null; email_financeiro?: string | null } | null;
  empresa_fiscal?: { email_fisco?: string | null } | null;
};

export type EmailCadastro = { rotulo: "financeiro" | "principal"; email: string; proprio: boolean };

const EMAIL = /^\S+@\S+\.\S+$/;

export function dominioDoEmail(email: string | null | undefined): string {
  const v = (email ?? "").trim().toLowerCase();
  const at = v.lastIndexOf("@");
  return at > 0 ? v.slice(at + 1) : "";
}

export function emailsDoCadastro(ctx: ContatoNfe | null | undefined): EmailCadastro[] {
  const proprioDominio = dominioDoEmail(ctx?.empresa_fiscal?.email_fisco);
  const lista: EmailCadastro[] = [];
  const candidatos: Array<[EmailCadastro["rotulo"], string | null | undefined]> = [
    ["financeiro", ctx?.cliente?.email_financeiro],
    ["principal", ctx?.cliente?.email],
  ];
  for (const [rotulo, valor] of candidatos) {
    const email = (valor ?? "").trim().toLowerCase();
    if (!EMAIL.test(email) || lista.some((c) => c.email === email)) continue;
    lista.push({ rotulo, email, proprio: Boolean(proprioDominio) && dominioDoEmail(email) === proprioDominio });
  }
  return lista;
}

export function emailPadraoCliente(ctx: ContatoNfe | null | undefined): string {
  return emailsDoCadastro(ctx).find((c) => !c.proprio)?.email ?? "";
}

export function separarEmails(texto: string): string[] {
  return texto.split(/[,;\n]/).map((v) => v.trim()).filter(Boolean);
}
