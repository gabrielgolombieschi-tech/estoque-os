import assert from 'node:assert/strict';
import {validarEscopo} from './controle-revisoes.mjs';

export const pares049 = [
  {usar:2698,reserva:2641,referencia:'3ZY12121BA00'},
  {usar:2699,reserva:2642,referencia:'3ZY12122DA00'},
  {usar:2700,reserva:2643,referencia:'3ZY12122BA00'},
];
export const pendentes049 = [769,957,1580,1581,1584,1587,2535];
export const ids049 = [...pares049.flatMap(p=>[p.usar,p.reserva]),...pendentes049].sort((a,b)=>a-b);
export function depois049(item) {
  validarEscopo(item);
  assert.ok(pares049.some(p=>p.reserva===item.id),'ID não autorizado');
  return {nome:`RESERVA-${item.id}`,codigo_interno:`RESERVA-${item.id}`};
}
export function conferir049(antes,depois,alterado=false) {
  validarEscopo(antes);validarEscopo(depois);
  const esperado=alterado?{...antes,...depois049(antes)}:antes;
  // Coluna GENERATED ALWAYS no banco: reserva não tem zeros iniciais.
  if(alterado&&Object.hasOwn(antes,'codigo_interno_sem_zeros'))esperado.codigo_interno_sem_zeros=esperado.codigo_interno;
  const limpar=i=>Object.fromEntries(Object.entries(i).filter(([c])=>!alterado||!['updated_at','atualizado_em'].includes(c)));
  assert.deepEqual(limpar(depois),limpar(esperado),'Campo não autorizado alterado');
}
