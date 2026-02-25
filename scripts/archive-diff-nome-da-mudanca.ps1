$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$migrationsDir = Join-Path $repoRoot "supabase\\migrations"
$archiveDir = Join-Path $repoRoot "supabase\\migrations_archived_local"

if (!(Test-Path $migrationsDir)) {
  throw "Pasta de migrations nao encontrada: $migrationsDir"
}

if (!(Test-Path $archiveDir)) {
  New-Item -ItemType Directory -Path $archiveDir | Out-Null
}

$targets = Get-ChildItem -Path $migrationsDir -File -Filter "*_nome_da_mudanca.sql" | Where-Object {
  $content = Get-Content -Path $_.FullName -Raw
  $content -match 'alter table "public"\."fornecedores" alter column "cnpj_norm" set default'
}

if (!$targets -or $targets.Count -eq 0) {
  Write-Output "Nenhum *_nome_da_mudanca.sql com SQL invalido detectado."
  exit 0
}

foreach ($file in $targets) {
  $dest = Join-Path $archiveDir $file.Name
  Move-Item -Path $file.FullName -Destination $dest -Force
  Write-Output "Arquivado: $($file.Name)"
}

Write-Output "Concluido. Total arquivado: $($targets.Count)"
