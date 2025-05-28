# Caminho onde a pasta "Arquivos" será criada
$caminhoPasta = "C:\Arquivos"

# Verificar se a pasta "Arquivos" já existe, caso não, cria a pasta
if (-not (Test-Path -Path $caminhoPasta)) {
    New-Item -Path $caminhoPasta -ItemType Directory
    Write-Host "Pasta 'Arquivos' criada com sucesso."
} else {
    Write-Host "A pasta 'Arquivos' já existe."
}

# Diretórios dentro da pasta "Arquivos"
$diretorios = @("Financeiro", "RH")

# Criar os diretórios "Financeiro" e "RH" dentro de "Arquivos"
foreach ($diretorio in $diretorios) {
    $caminhoDiretorio = "$caminhoPasta\$diretorio"
    
    if (-not (Test-Path -Path $caminhoDiretorio)) {
        New-Item -Path $caminhoDiretorio -ItemType Directory
        Write-Host "Diretório '$diretorio' criado com sucesso dentro de 'Arquivos'."
    } else {
        Write-Host "Diretório '$diretorio' já existe dentro de 'Arquivos'."
    }
}
