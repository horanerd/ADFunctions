# --- Script PowerShell para Deletar Pastas em um Caminho de Rede ---
# Deleta subpastas de um caminho de rede base. As subpastas a serem deletadas
# são listadas em um arquivo .txt. A exclusão só ocorre se a pasta não contiver
# arquivos com 1 KB (1024 bytes) ou mais.

# ==============================================================================
# --- CONFIGURAÇÃO OBRIGATÓRIA ---
#
# 1. Edite esta linha para apontar para a pasta principal na rede onde as
#    subpastas a serem deletadas estão localizadas.
#    Exemplos:
#    $caminhoBaseRede = "\\SERVIDOR\Compartilhamento\Backups"
#    $caminhoBaseRede = "\\192.168.1.50\Docs\ProjetosAntigos"
#
$caminhoBaseRede = "\\SEU_SERVIDOR\SUA_PASTA_COMPARTILHADA\PASTA_RAIZ"

# 2. Nome do arquivo que contém a lista de nomes de pastas.
$arquivoLista = ".\pastas_a_deletar.txt"
#
# ==============================================================================
# MODO DE TESTE: Para testar sem deletar, adicione -WhatIf ao final
# da linha `Remove-Item` no final do script.
# ==============================================================================


# --- Validações Iniciais ---
if ($caminhoBaseRede -eq "\\SEU_SERVIDOR\SUA_PASTA_COMPARTILHADA\PASTA_RAIZ") {
    Write-Error "ERRO: Você não configurou a variável `$caminhoBaseRede`. Edite o script antes de executar."
    Read-Host "Pressione Enter para sair."
    exit
}
if (-not (Test-Path $arquivoLista)) {
    Write-Error "ERRO: Arquivo de lista '$arquivoLista' não encontrado."
    Read-Host "Pressione Enter para sair."
    exit
}

Write-Host "--- Iniciando verificação de pastas na rede ---" -ForegroundColor Yellow
Write-Host "Caminho Base: $caminhoBaseRede"

# --- Processamento da Lista ---
Get-Content $arquivoLista | ForEach-Object {
    $nomePasta = $_.Trim()

    if ([string]::IsNullOrWhiteSpace($nomePasta)) {
        return # Pula linhas em branco
    }

    # Junta o caminho base da rede com o nome da pasta lido do arquivo
    $caminhoCompleto = Join-Path -Path $caminhoBaseRede -ChildPath $nomePasta

    if (-not (Test-Path $caminhoCompleto -PathType Container)) {
        Write-Warning "AVISO: Caminho não encontrado ou não é uma pasta: '$caminhoCompleto'"
        return
    }

    # --- Lógica de Verificação de Conteúdo ---
    $contemArquivosEmKB = $false
    $arquivos = Get-ChildItem -Path $caminhoCompleto -Recurse -File -ErrorAction SilentlyContinue

    foreach ($arquivo in $arquivos) {
        if ($arquivo.Length -ge 1024) {
            $contemArquivosEmKB = $true
            break # Encontrou um arquivo, não precisa mais verificar
        }
    }

    # --- Decisão de Exclusão ---
    if ($contemArquivosEmKB) {
        Write-Host "❌ NÃO EXCLUIR: '$caminhoCompleto' contém arquivos com 1 KB ou mais." -ForegroundColor Red
    } else {
        Write-Host "✅ EXCLUIR: '$caminhoCompleto' está vazia ou contém apenas arquivos menores que 1 KB." -ForegroundColor Green
        
        try {
            # === COMANDO DE EXCLUSÃO ===
            # Para testar, adicione -WhatIf -> Remove-Item ... -Force -WhatIf
            Remove-Item -Path $caminhoCompleto -Recurse -Force
            
            Write-Host "   -> Pasta '$caminhoCompleto' foi excluída com sucesso."
        } catch {
            Write-Error "   -> Falha ao excluir a pasta '$caminhoCompleto'. Verifique suas permissões. Erro: $_"
        }
    }
}

Write-Host "--- Script finalizado ---" -ForegroundColor Yellow
