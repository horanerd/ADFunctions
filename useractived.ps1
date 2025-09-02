# Definir as variáveis
$Usuario = "NomeDoUsuario" # Substitua "NomeDoUsuario" pelo nome de login (sAMAccountName) do usuário
$SenhaTemporaria = "Senha@123!" # Defina uma senha temporária segura
$OUDestino = "OU=NovaOU,DC=dominio,DC=com" # Substitua pelo caminho completo da OU de destino

# Resetar a senha
try {
    # Cria a nova senha com as opções de segurança
    $NovaSenha = ConvertTo-SecureString -String $SenhaTemporaria -AsPlainText -Force
    
    # Reset a senha do usuário e força a mudança no próximo logon
    Set-ADAccountPassword -Identity $Usuario -NewPassword $NovaSenha -PassThru
    Set-ADUser -Identity $Usuario -ChangePasswordAtLogon $true
    
    Write-Host "Senha do usuário '$Usuario' foi resetada com sucesso." -ForegroundColor Green
    
} catch {
    Write-Host "Erro ao resetar a senha do usuário '$Usuario': $($_.Exception.Message)" -ForegroundColor Red
    exit # Encerra o script se o reset de senha falhar
}

# ----------------------------------------------------

# Validar e ativar o usuário
try {
    $ADUser = Get-ADUser -Identity $Usuario -Properties Enabled
    
    if ($ADUser.Enabled -eq $true) {
        Write-Host "A conta de usuário '$Usuario' já está ativa." -ForegroundColor Yellow
    } else {
        # Ativa a conta
        Enable-ADAccount -Identity $Usuario
        Write-Host "A conta de usuário '$Usuario' foi ativada com sucesso." -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erro ao verificar ou ativar a conta do usuário '$Usuario': $($_.Exception.Message)" -ForegroundColor Red
    exit # Encerra o script se a ativação falhar
}

# ----------------------------------------------------

# Mover o usuário para a nova OU
try {
    Move-ADObject -Identity $Usuario -TargetPath $OUDestino
    Write-Host "O usuário '$Usuario' foi movido com sucesso para a OU '$OUDestino'." -ForegroundColor Green
    
} catch {
    Write-Host "Erro ao mover o usuário '$Usuario' para a OU de destino: $($_.Exception.Message)" -ForegroundColor Red
    exit # Encerra o script se a movimentação falhar
}
