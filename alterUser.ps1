# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Define o caminho do arquivo CSV
$CsvFilePath = "C:\caminho\para\o\seu\arquivo\usuarios.csv" # Altere o caminho conforme necessário

# Verifica se o arquivo CSV existe
if (-not (Test-Path $CsvFilePath)) {
    Write-Host "Erro: O arquivo '$CsvFilePath' não foi encontrado." -ForegroundColor Red
    return
}

# Importa os dados do arquivo CSV
$UserData = Import-Csv -Path $CsvFilePath

foreach ($User in $UserData) {
    if (-not $User.Account) {
        Write-Host "--- AVISO: Linha do CSV ignorada. O campo 'Account' está vazio. ---" -ForegroundColor Yellow
        continue
    }

    $UserAccount = $User.Account
    $FullName = $User.FullName.Trim()

    Write-Host "--- Processando o usuário: $UserAccount ---" -ForegroundColor Cyan

    try {
        # Obtém o usuário do AD e suas propriedades, incluindo o textEncodedORAddress.
        $AdUser = Get-ADUser -Filter "sAMAccountName -eq '$UserAccount'" -Properties GivenName, Surname, DisplayName, textEncodedORAddress -ErrorAction Stop

        if ($FullName -and $FullName.Split(" ").Count -ge 2) {
            # 1. Decomposição do nome
            $NameParts = $FullName.Split(" ")
            $NewGivenName = $NameParts[0]
            $NewSurname = ($NameParts | Select-Object -Skip 1) -join " "
            $NewDisplayName = $FullName
            
            # 2. Monta o CN com o DisplayName + Account
            $NewCN = "$NewDisplayName $UserAccount"

            # 3. Reconstroi o textEncodedORAddress.
            if ($AdUser.textEncodedORAddress) {
                # Extrai o restante do endereço (a parte após o primeiro '/')
                $RestOfAddress = ($AdUser.textEncodedORAddress -split '/', 2)[1]
                $NewTextEncodedORAddress = "CN=$NewDisplayName/$RestOfAddress"
            } else {
                Write-Host "  -> Aviso: O atributo 'textEncodedORAddress' está vazio para este usuário. Ele não será atualizado." -ForegroundColor Yellow
                $NewTextEncodedORAddress = $null
            }

            Write-Host "  -> Aplicando valores:" -ForegroundColor Green
            Write-Host "    GivenName: $NewGivenName" -ForegroundColor Green
            Write-Host "    Surname: $NewSurname" -ForegroundColor Green
            Write-Host "    DisplayName: $NewDisplayName" -ForegroundColor Green
            Write-Host "    CN: $NewCN" -ForegroundColor Green
            Write-Host "    TextEncodedORAddress: $NewTextEncodedORAddress" -ForegroundColor Green

            # 4. Renomeia o objeto no AD (CN) e atualiza os demais atributos.
            Rename-ADObject -Identity $AdUser.DistinguishedName -NewName $NewCN -WhatIf
            
            # Atualiza os outros atributos.
            if ($NewTextEncodedORAddress) {
                Set-ADUser -Identity $AdUser.DistinguishedName `
                           -GivenName $NewGivenName `
                           -Surname $NewSurname `
                           -DisplayName $NewDisplayName `
                           -Replace @{textEncodedORAddress=$NewTextEncodedORAddress} `
                           -WhatIf
            } else {
                Set-ADUser -Identity $AdUser.DistinguishedName `
                           -GivenName $NewGivenName `
                           -Surname $NewSurname `
                           -DisplayName $NewDisplayName `
                           -WhatIf
            }
            
            Write-Host "  -> Alteração para '$UserAccount' concluída com sucesso (simulado)." -ForegroundColor Green
        } else {
            Write-Host "  -> Erro: O nome completo '$FullName' está vazio ou não é válido." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  --- ERRO CRÍTICO ao processar '$UserAccount' ---" -ForegroundColor Red
        Write-Host "  Mensagem de erro completa:" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        Write-Host "---------------------------------------------------------" -ForegroundColor Red
    }
}
Write-Host "--- Processo de alteração em massa concluído. ---" -ForegroundColor Yellow
