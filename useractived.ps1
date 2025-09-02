# -------------------- FUNÇÃO DE GERAÇÃO DE SENHA --------------------

function Generate-RandomPassword {
    param (
        [int]$Length = 8
    )

    # Define os conjuntos de caracteres permitidos
    $letras = 'abcdefghijklmnopqrstuvwxyz'
    $LETRAS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $numeros = '0123456789'
    
    # Define os caracteres especiais permitidos (excluindo os proibidos)
    $caracteresEspeciais = '!@#$%&*()_-+=[]{};:<>?'

    # Combina todos os conjuntos de caracteres
    $todosCaracteres = ($letras + $LETRAS + $numeros + $caracteresEspeciais).ToCharArray()

    # Garante que a senha tenha pelo menos um de cada tipo de caractere
    $senhaArray = @(
        $letras | Get-Random
        $LETRAS | Get-Random
        $numeros | Get-Random
        $caracteresEspeciais | Get-Random
    )

    # Preenche o restante da senha com caracteres aleatórios
    while ($senhaArray.Count -lt $Length) {
        $senhaArray += $todosCaracteres | Get-Random
    }

    # Embaralha o array para garantir a aleatoriedade e junta os caracteres
    $senha = ($senhaArray | Get-Random -Count $senhaArray.Count) -join ''

    return $senha
}

# -------------------- FIM DA FUNÇÃO --------------------

# --- Variáveis do Script (ajuste-as conforme sua necessidade) ---
$Usuario = "NomeDoUsuario" # Substitua pelo nome de login (sAMAccountName) do usuário
$OUDestino = "OU=NovaOU,DC=dominio,DC=com" # Substitua pelo caminho completo da OU de destino
$SenhaTemporaria = Generate-RandomPassword -Length 8 # Chama a função para gerar a senha

# Exibe a senha gerada (REMOVER EM AMBIENTE DE PRODUÇÃO POR QUESTÃO DE SEGURANÇA)
Write-Host "A senha temporária gerada para o usuário '$Usuario' é: $SenhaTemporaria" -ForegroundColor Yellow

# -------------------- PROCESSO DE ATIVAÇÃO --------------------

# Resetar a senha
try {
    $NovaSenha = ConvertTo-SecureString -String $SenhaTemporaria -AsPlainText -Force
    
    Set-ADAccountPassword -Identity $Usuario -NewPassword $NovaSenha -PassThru
    Set-ADUser -Identity $Usuario -ChangePasswordAtLogon $true
    
    Write-Host "Senha do usuário '$Usuario' foi resetada com sucesso." -ForegroundColor Green
    
} catch {
    Write-Host "Erro ao resetar a senha do usuário '$Usuario': $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ----------------------------------------------------

# Validar e ativar o usuário
try {
    $ADUser = Get-ADUser -Identity $Usuario -Properties Enabled
    
    if ($ADUser.Enabled -eq $true) {
        Write-Host "A conta de usuário '$Usuario' já está ativa." -ForegroundColor Yellow
    } else {
        Enable-ADAccount -Identity $Usuario
        Write-Host "A conta de usuário '$Usuario' foi ativada com sucesso." -ForegroundColor Green
    }
    
} catch {
    Write-Host "Erro ao verificar ou ativar a conta do usuário '$Usuario': $($_.Exception.Message)" -ForegroundColor Red
    exit
}

# ----------------------------------------------------

# Mover o usuário para a nova OU
try {
    Move-ADObject -Identity $Usuario -TargetPath $OUDestino
    Write-Host "O usuário '$Usuario' foi movido com sucesso para a OU '$OUDestino'." -ForegroundColor Green
    
} catch {
    Write-Host "Erro ao mover o usuário '$Usuario' para a OU de destino: $($_.Exception.Message)" -ForegroundColor Red
    exit
}
