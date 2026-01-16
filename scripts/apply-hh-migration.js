import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const supabaseUrl = 'https://ptybnreejbkqwwozvhzb.supabase.co';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseServiceKey) {
  console.error('SUPABASE_SERVICE_ROLE_KEY não definida');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

const migrationPath = join(__dirname, '../supabase/migrations/20260114_hh_servicos_cliente.sql');
const sql = readFileSync(migrationPath, 'utf8');

console.log('Executando migration...');

// Executar SQL via RPC
const { error } = await supabase.rpc('exec_sql', { sql_query: sql });

if (error) {
  console.error('Erro ao executar migration:', error);
  process.exit(1);
}

console.log('✅ Migration aplicada com sucesso!');
console.log('Tabela cliente_hh_servicos criada');
console.log('Flag habilita_servico_hh adicionada em empresas');
