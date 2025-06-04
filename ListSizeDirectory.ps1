Get-ChildItem -Directory |
  Select-Object Name, @{Name="TamanhoTotal"; Expression={
    $caminhoPasta = $_.FullName
    $tamanhoBytes = 0 # Inicializa com zero
    try {
        $arquivosNaPasta = Get-ChildItem -Path $caminhoPasta -Recurse -File -ErrorAction SilentlyContinue
        if ($null -ne $arquivosNaPasta) {
            $tamanhoBytes = ($arquivosNaPasta | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        }
    }
    catch {
        # Em caso de erro ao acessar a pasta, o tamanhoBytes permanecerá 0 ou o último valor válido.
        # Você pode adicionar uma mensagem de erro específica aqui se desejar.
    }

    # Formata o tamanho para ser legível
    if ($null -ne $tamanhoBytes) {
        if ($tamanhoBytes -ge 1TB) {
            "{0:N2} TB" -f ($tamanhoBytes / 1TB)
        } elseif ($tamanhoBytes -ge 1GB) {
            "{0:N2} GB" -f ($tamanhoBytes / 1GB)
        } elseif ($tamanhoBytes -ge 1MB) {
            "{0:N2} MB" -f ($tamanhoBytes / 1MB)
        } elseif ($tamanhoBytes -ge 1KB) {
            "{0:N2} KB" -f ($tamanhoBytes / 1KB)
        } else {
            "$tamanhoBytes Bytes"
        }
    } else {
        "N/A" # Caso $tamanhoBytes seja nulo por algum motivo
    }
  }} | Format-Table -AutoSize
