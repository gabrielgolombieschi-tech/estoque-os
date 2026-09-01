"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { getSupabaseBrowser } from "@/lib/auth/supabase";
import { useTenantEmpresa } from "@/lib/auth/hooks";
import { applyTenantEmpresa } from "@/lib/db/scopes";

type Cliente = { id: number; nome: string; ativo: boolean };
type Unidade = { id: number; cliente_id: number; nome: string; codigo: string | null; documento: string | null; cidade: string | null; uf: string | null; contato_nome: string | null; contato_email: string | null; ativo: boolean };
const empty = { clienteId: "", nome: "", codigo: "", documento: "", cidade: "", uf: "", contatoNome: "", contatoEmail: "", ativo: true };

export default function ClienteUnidadesPage() {
  const te = useTenantEmpresa();
  const supabase = useMemo(() => getSupabaseBrowser(), []);
  const tenantId = te.tenantId; const empresaId = te.empresaId;
  const [clientes, setClientes] = useState<Cliente[]>([]); const [rows, setRows] = useState<Unidade[]>([]);
  const [form, setForm] = useState(empty); const [editingId, setEditingId] = useState<number | null>(null);
  const [loading, setLoading] = useState(true); const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null); const [ok, setOk] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!tenantId || !empresaId) return; setLoading(true); setError(null);
    const [clientsRes, unitsRes] = await Promise.all([
      applyTenantEmpresa(supabase.from("clientes").select("id,nome,ativo"), tenantId, empresaId).order("nome"),
      applyTenantEmpresa(supabase.from("cliente_unidades").select("id,cliente_id,nome,codigo,documento,cidade,uf,contato_nome,contato_email,ativo"), tenantId, empresaId).order("nome"),
    ]);
    if (clientsRes.error) setError(clientsRes.error.message); else setClientes((clientsRes.data ?? []) as Cliente[]);
    if (unitsRes.error) setError(unitsRes.error.message); else setRows((unitsRes.data ?? []) as Unidade[]);
    setLoading(false);
  }, [empresaId, supabase, tenantId]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  async function save(event: FormEvent) {
    event.preventDefault(); if (!tenantId || !empresaId || !form.clienteId || !form.nome.trim()) { setError("Cliente e nome são obrigatórios."); return; }
    setBusy(true); setError(null); setOk(null);
    const payload = { tenant_id: tenantId, empresa_id: empresaId, cliente_id: Number(form.clienteId), nome: form.nome.trim(), codigo: form.codigo.trim() || null, documento: form.documento.trim() || null, cidade: form.cidade.trim() || null, uf: form.uf.trim().toUpperCase() || null, contato_nome: form.contatoNome.trim() || null, contato_email: form.contatoEmail.trim().toLowerCase() || null, ativo: form.ativo, updated_at: new Date().toISOString() };
    const response = editingId ? await applyTenantEmpresa(supabase.from("cliente_unidades").update(payload).eq("id", editingId), tenantId, empresaId) : await supabase.from("cliente_unidades").insert(payload);
    if (response.error) setError(response.error.message); else { setOk(editingId ? "Unidade atualizada." : "Unidade criada."); setEditingId(null); setForm(empty); await load(); }
    setBusy(false);
  }
  function edit(row: Unidade) { setEditingId(row.id); setForm({ clienteId:String(row.cliente_id),nome:row.nome,codigo:row.codigo??"",documento:row.documento??"",cidade:row.cidade??"",uf:row.uf??"",contatoNome:row.contato_nome??"",contatoEmail:row.contato_email??"",ativo:row.ativo }); }
  const cls = "w-full rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-sm outline-none focus:border-zinc-600";
  return <div className="space-y-4"><div className="flex flex-wrap items-end justify-between gap-3"><div><h1 className="text-2xl font-semibold">Unidades dos clientes</h1><p className="mt-1 text-sm text-zinc-400">Fábricas ou locais operacionais dentro do mesmo CNPJ.</p></div><Link href="/clientes" className="rounded-md border border-zinc-700 bg-zinc-900 px-3 py-2 hover:bg-zinc-800">Clientes</Link></div>
    {error && <div className="rounded-md border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">{error}</div>}{ok && <div className="rounded-md border border-emerald-500/30 bg-emerald-500/10 p-3 text-sm text-emerald-200">{ok}</div>}
    <div className="grid gap-4 xl:grid-cols-[420px_minmax(0,1fr)]"><form onSubmit={save} className="rounded-xl border border-zinc-800 bg-zinc-950 p-4"><div className="flex items-center justify-between"><h2 className="font-medium">{editingId ? `Editar unidade #${editingId}` : "Nova unidade"}</h2>{editingId && <button type="button" className="text-sm text-zinc-400" onClick={() => {setEditingId(null);setForm(empty);}}>Cancelar edição</button>}</div><div className="mt-4 grid gap-3 md:grid-cols-2"><label className="text-xs text-zinc-400 md:col-span-2">Cliente<select className={`${cls} mt-1`} value={form.clienteId} onChange={(e)=>setForm((p)=>({...p,clienteId:e.target.value}))}><option value="">Selecione</option>{clientes.filter((c)=>c.ativo).map((c)=><option key={c.id} value={c.id}>{c.nome}</option>)}</select></label><label className="text-xs text-zinc-400 md:col-span-2">Nome<input className={`${cls} mt-1`} value={form.nome} onChange={(e)=>setForm((p)=>({...p,nome:e.target.value}))}/></label><label className="text-xs text-zinc-400">Código<input className={`${cls} mt-1`} value={form.codigo} onChange={(e)=>setForm((p)=>({...p,codigo:e.target.value}))}/></label><label className="text-xs text-zinc-400">Documento interno<input className={`${cls} mt-1`} value={form.documento} onChange={(e)=>setForm((p)=>({...p,documento:e.target.value}))}/></label><label className="text-xs text-zinc-400">Cidade<input className={`${cls} mt-1`} value={form.cidade} onChange={(e)=>setForm((p)=>({...p,cidade:e.target.value}))}/></label><label className="text-xs text-zinc-400">UF<input maxLength={2} className={`${cls} mt-1`} value={form.uf} onChange={(e)=>setForm((p)=>({...p,uf:e.target.value}))}/></label><label className="text-xs text-zinc-400">Contato<input className={`${cls} mt-1`} value={form.contatoNome} onChange={(e)=>setForm((p)=>({...p,contatoNome:e.target.value}))}/></label><label className="text-xs text-zinc-400">E-mail<input type="email" className={`${cls} mt-1`} value={form.contatoEmail} onChange={(e)=>setForm((p)=>({...p,contatoEmail:e.target.value}))}/></label><label className="flex items-center gap-2 text-sm md:col-span-2"><input type="checkbox" checked={form.ativo} onChange={(e)=>setForm((p)=>({...p,ativo:e.target.checked}))}/> Ativa</label></div><button className="mt-4 rounded-md bg-zinc-100 px-4 py-2 font-medium text-zinc-900 disabled:opacity-50" disabled={busy}>{busy?"Salvando...":"Salvar"}</button></form>
      <div className="overflow-x-auto rounded-xl border border-zinc-800 bg-zinc-950"><table className="w-full min-w-[800px] text-sm"><thead className="bg-zinc-900/70 text-xs uppercase text-zinc-500"><tr><th className="px-4 py-3 text-left">Cliente</th><th className="px-4 py-3 text-left">Unidade</th><th className="px-4 py-3 text-left">Local</th><th className="px-4 py-3 text-left">Contato</th><th className="px-4 py-3 text-left">Status</th><th /></tr></thead><tbody className="divide-y divide-zinc-800">{rows.map((row)=><tr key={row.id}><td className="px-4 py-3">{clientes.find((c)=>c.id===row.cliente_id)?.nome??row.cliente_id}</td><td className="px-4 py-3"><div className="font-medium">{row.nome}</div><div className="text-xs text-zinc-500">{row.codigo??"—"}</div></td><td className="px-4 py-3">{[row.cidade,row.uf].filter(Boolean).join("/")||"—"}</td><td className="px-4 py-3"><div>{row.contato_nome??"—"}</div><div className="text-xs text-zinc-500">{row.contato_email??""}</div></td><td className="px-4 py-3">{row.ativo?"Ativa":"Inativa"}</td><td className="px-4 py-3 text-right"><button className="rounded-md border border-zinc-700 px-3 py-1 hover:bg-zinc-900" onClick={()=>edit(row)}>Editar</button></td></tr>)}{!loading&&rows.length===0&&<tr><td colSpan={6} className="px-4 py-10 text-center text-zinc-500">Nenhuma unidade cadastrada.</td></tr>}</tbody></table>{loading&&<div className="p-4 text-zinc-500">Carregando...</div>}</div></div>
  </div>;
}
