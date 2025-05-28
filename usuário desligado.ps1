# Script para processar o desligamento de um usuário no Active Directory

# --- Configurações ---
# Define o nome do domínio
$DomainDN = "DC=horanerd,DC=com,DC=br"
# Define o nome da OU de destino para usuários desligados
$TargetOuName = "Desligados"
# Define o caminho completo (Distinguished Name) da OU de destino
$TargetOuDN = "OU=$TargetOuName,$DomainDN"

# --- Início do Script ---

# Solicita o nome de usuário (sAMAccountName)
$UserName = Read-Host "Digite o nome de usuário (sAMAccountName) a ser processado"

# Verifica se o nome de usuário foi fornecido
if ([string]::IsNullOrWhiteSpace($UserName)) {
    Write-Host "Nome de usuário não fornecido. Saindo do script." -ForegroundColor Red
    exit
}

try {
    # Tenta obter o usuário
    Write-Host "Procurando usuário '$UserName'..."
    $User = Get-ADUser -Identity $UserName -Properties MemberOf, DistinguishedName
    if (-not $User) {
        Write-Host "Usuário '$UserName' não encontrado no domínio '$DomainDN'." -ForegroundColor Red
        exit
    }
    Write-Host "Usuário '$($User.Name)' encontrado ($($User.DistinguishedName))." -ForegroundColor Cyan



 

    # 2. Mover o usuário para a OU "Desligados"
    # Verifica se a OU de destino existe
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetOuDN'" -ErrorAction SilentlyContinue)) {
        Write-Host "A OU de destino '$TargetOuName' não foi encontrada em '$DomainDN'." -ForegroundColor Red
        Write-Host "Crie a OU primeiro ou verifique o nome e caminho no script."
        # Você pode adicionar a criação da OU aqui se desejar, como no script anterior.
        # Ex: New-ADOrganizationalUnit -Name $TargetOuName -Path $DomainDN -ProtectedFromAccidentalDeletion $true
        exit
    }

    Write-Host "Movendo usuário para a OU '$TargetOuName'..."
    try {
        Move-ADObject -Identity $User.DistinguishedName -TargetPath $TargetOuDN
        Write-Host "Usuário movido com sucesso para '$TargetOuDN'." -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO ao mover o usuário: $($_.Exception.Message)" -ForegroundColor Red
        # Se o erro for sobre o objeto estar protegido contra exclusão acidental,
        # isso se aplica à OU de origem, não ao usuário sendo movido.
        # No entanto, se a OU de destino não existir, o erro será capturado aqui.
        exit
    }

    # 3. Desativar a conta do usuário
    Write-Host "Desativando a conta do usuário..."
    try {
        Disable-ADAccount -Identity $User.SamAccountName
        Write-Host "Conta do usuário '$($User.Name)' desativada com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO ao desativar a conta do usuário: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }

    Write-Host "Processo de desligamento para o usuário '$($User.Name)' concluído." -ForegroundColor Blue
}
catch {
    Write-Host "Ocorreu um erro geral no script: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host "Detalhe do erro interno: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
}