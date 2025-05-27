# Script otimizado para performance e legibilidade com módulo de reset de senha
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')] # Habilita -WhatIf e -Confirm para todo o script
param (
    [Parameter(ParameterSetName = 'FileMode', Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$FilePath,

    [Parameter(ParameterSetName = 'ListMode', Mandatory = $true)]
    [string[]]$UserLogonName,

    [Parameter(ParameterSetName = 'FileMode')]
    [Parameter(ParameterSetName = 'ListMode')]
    [string]$SearchBase,

    [Parameter(ParameterSetName = 'FileMode')]
    [Parameter(ParameterSetName = 'ListMode')]
    [switch]$ResetModeSwitch # Novo switch para ativar o modo de reset de senha
)

# --- Configuração Inicial e Funções de Log/Senha ---
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$LogFilePath = Join-Path -Path $ScriptDir -ChildPath "UserManagement_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$resetUsersThisRun = @{} # HashTable para rastrear usuários já processados para reset nesta execução

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [string]$FilePathParam, # Renomeado para evitar conflito de escopo
        [ValidateSet("INFO", "WARNING", "ERROR", "ACTION")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] - $Message"
    try {
        Add-Content -Path $FilePathParam -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Host "ERRO CRÍTICO: Não foi possível escrever no arquivo de log '$FilePathParam'. Detalhes: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Log -Message "Script iniciado. Modo de Execução: $($PSCmdlet.ParameterSetName). Modo Reset Ativo: $($ResetModeSwitch.IsPresent)." -FilePathParam $LogFilePath

# Verifica e importa o módulo ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log -Message "Módulo ActiveDirectory importado com sucesso." -FilePathParam $LogFilePath
} catch {
    $errorMsg = "Erro ao importar o módulo ActiveDirectory: $($_.Exception.Message)"
    Write-Error $errorMsg
    Write-Log -Message $errorMsg -FilePathParam $LogFilePath -Level ERROR
    exit 1
}

function New-StrongPassword {
    param(
        [int]$Length = 14 # Aumentado para maior segurança padrão
    )
    $lower = 'abcdefghijklmnopqrstuvwxyz'
    $upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $digits = '0123456789'
    $special = '!@#$%*-+=' # Conjunto de especiais comumente aceitos e menos problemáticos
    
    $passwordChars = @()
    $passwordChars += Get-Random -InputObject $lower.ToCharArray()
    $passwordChars += Get-Random -InputObject $upper.ToCharArray()
    $passwordChars += Get-Random -InputObject $digits.ToCharArray()
    $passwordChars += Get-Random -InputObject $special.ToCharArray()

    $allChars = $lower + $upper + $digits + $special
    $remainingLength = $Length - $passwordChars.Count
    if ($remainingLength -gt 0) {
        1..$remainingLength | ForEach-Object { $passwordChars += Get-Random -InputObject $allChars.ToCharArray() }
    }
    
    return -join ($passwordChars | Get-Random -Count $passwordChars.Count)
}

function Convert-PwdLastSet {
    param ([object]$pwdLastSet)
    if ($null -eq $pwdLastSet -or $pwdLastSet -le 0) {
        return "Senha indefinida ou usuário deve alterá-la ao logar"
    }
    try {
        $date = [datetime]::FromFileTime($pwdLastSet)
        $age = [math]::Floor((Get-Date - $date).TotalDays)
        return "$($date.ToString('dd/MM/yyyy HH:mm')) ($age dias atrás)"
    } catch {
        Write-Log -Message "Erro ao converter pwdLastSet: $($_.Exception.Message)" -FilePathParam $LogFilePath -Level WARNING
        return "Erro ao converter pwdLastSet"
    }
}

function Get-UserInfo {
    param (
        [string[]]$Users
    )

    $props = 'SamAccountName','DisplayName','Enabled','Department','pwdLastSet','UserPrincipalName','SID','LockedOut'
    $result = @()

    foreach ($userIdentifier in $Users) {
        $params = @{ Properties = $props; ErrorAction = 'SilentlyContinue' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }

        # Tenta identificar por SamAccountName, depois UserPrincipalName se não encontrar
        $u = Get-ADUser -Identity $userIdentifier @params
        if (-not $u -and $userIdentifier -like '*@*') { # Se parece UPN e falhou, tenta filtrar por UPN
             $u = Get-ADUser -Filter "UserPrincipalName -eq '$userIdentifier'" @params
        }
        
        if ($u) {
            $dept = if ($u.Department) { $u.Department.Trim() } else { 'Não especificado' }
            $mainDept = ($dept -split '\s+')[0]
            $pwdLastSetConverted = Convert-PwdLastSet -pwdLastSet $u.pwdLastSet

            $result += [PSCustomObject]@{
                Usuario           = $u.SamAccountName
                Nome              = $u.DisplayName
                Ativo             = if ($u.Enabled) { 'Sim' } else { 'Não' }
                Bloqueado         = if ($u.LockedOut) { 'Sim' } else { 'Não' }
                DeptMain          = $mainDept
                DeptFull          = $dept
                SenhaUltAlteracao = $pwdLastSetConverted
                UserPrincipalName = $u.UserPrincipalName
                SID               = $u.SID.Value
            }
        } else {
            Write-Log -Message "Usuário '$userIdentifier' não encontrado no Active Directory." -FilePathParam $LogFilePath -Level WARNING
            $result += [PSCustomObject]@{
                Usuario           = $userIdentifier # Mantém o identificador original
                Nome              = 'Não encontrado'
                Ativo             = 'N/D'
                Bloqueado         = 'N/D'
                DeptMain          = 'N/D'
                DeptFull          = 'N/D'
                SenhaUltAlteracao = 'N/D'
                UserPrincipalName = 'N/D'
                SID               = 'N/D'
            }
        }
    }
    return $result
}

function Invoke-UserPasswordReset {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserSamAccountName,

        [Parameter(Mandatory = $true)]
        [string]$LocalLogFilePath, # Parâmetro para o caminho do log

        [Parameter(Mandatory = $false)]
        [int]$GeneratedPasswordLength = 14
    )

    process {
        Write-Log -Message "Tentativa de reset de senha para o usuário '$UserSamAccountName'." -FilePathParam $LocalLogFilePath -Level INFO
        
        $adUser = Get-ADUser -Identity $UserSamAccountName -Properties 'LockedOut', 'Enabled' -ErrorAction SilentlyContinue
        
        if (-not $adUser) {
            Write-Log -Message "Usuário '$UserSamAccountName' não encontrado no AD para reset de senha." -FilePathParam $LocalLogFilePath -Level ERROR
            Write-Warning "Usuário '$UserSamAccountName' não encontrado no AD."
            return $false 
        }

        if (-not $adUser.Enabled) {
            $msg = "Usuário '$UserSamAccountName' está DESABILITADO. Reset de senha não será realizado em conta desabilitada."
            Write-Log -Message $msg -FilePathParam $LocalLogFilePath -Level WARNING
            Write-Warning $msg
            return $false
        }

        if ($adUser.LockedOut) {
            Write-Log -Message "Usuário '$UserSamAccountName' está bloqueado. Tentando desbloquear..." -FilePathParam $LocalLogFilePath -Level INFO
            if ($PSCmdlet.ShouldProcess("Usuário: $UserSamAccountName (Bloqueado)", "Desbloquear Conta")) {
                try {
                    Unlock-ADAccount -Identity $adUser -ErrorAction Stop
                    Write-Log -Message "Conta do usuário '$UserSamAccountName' desbloqueada." -FilePathParam $LocalLogFilePath -Level ACTION
                } catch {
                    Write-Log -Message "Falha ao desbloquear conta '$UserSamAccountName': $($_.Exception.Message)" -FilePathParam $LocalLogFilePath -Level ERROR
                }
            } else {
                 Write-Log -Message "Desbloqueio da conta '$UserSamAccountName' cancelado (WhatIf/Confirm)." -FilePathParam $LocalLogFilePath -Level INFO
            }
        }

        $plainPassword = New-StrongPassword -Length $GeneratedPasswordLength
        $secureNewPassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

        try {
            if ($PSCmdlet.ShouldProcess("Usuário: $UserSamAccountName", "Resetar Senha (Nova senha gerada: $plainPassword)")) {
                Set-ADAccountPassword -Identity $adUser -NewPassword $secureNewPassword -Reset -ErrorAction Stop
                $successMsg = "Senha para '$UserSamAccountName' resetada. Nova senha (temporária): $plainPassword. O usuário deverá alterá-la no próximo logon."
                Write-Log -Message $successMsg -FilePathParam $LocalLogFilePath -Level ACTION
                Write-Host $successMsg -ForegroundColor Green
                return $true 
            } else {
                Write-Log -Message "Reset de senha para '$UserSamAccountName' cancelado (WhatIf/Confirm)." -FilePathParam $LocalLogFilePath -Level INFO
                return $false 
            }
        } catch {
            $errorDetail = $_.Exception.Message
            if ($_.Exception.InnerException) { $errorDetail += " | InnerException: $($_.Exception.InnerException.Message)"}
            Write-Log -Message "Falha ao resetar a senha para '$UserSamAccountName': $errorDetail" -FilePathParam $LocalLogFilePath -Level ERROR
            Write-Error "Falha ao resetar a senha para '$UserSamAccountName': $errorDetail"
            return $false
        }
    }
}

function Show-Table {
    param ([array]$UserInfos)
    if ($UserInfos -and $UserInfos.Count -gt 0) {
        $UserInfos | Sort-Object DeptMain, Usuario | Format-Table -AutoSize
    } else {
        Write-Host "Nenhuma informação de usuário para exibir." -ForegroundColor Yellow
    }
}

# --- Lógica Principal ---

if ($ResetModeSwitch.IsPresent) {
    Write-Host "`nAVISO: MODO DE RESET DE SENHA ESTÁ ATIVO!`n" -ForegroundColor Yellow
    Write-Log -Message "MODO RESET DE SENHA ATIVO." -FilePathParam $LogFilePath -Level WARNING
    # A confirmação global com ShouldProcess é tratada pelo [CmdletBinding()] no topo.
    # Se -Confirm não for passado, $ConfirmPreference é 'High', então para ações de alto impacto, ele perguntará.
    # Se -WhatIf for passado, ele mostrará o que faria.
    # Para uma confirmação extra manual, descomente abaixo:
    # if (-not $WhatIfPreference) { # Não perguntar se for -WhatIf
    #    $confirmReset = Read-Host "Você tem certeza que deseja prosseguir com o reset de senhas? (S/N)"
    #    if ($confirmReset -ne 'S') {
    #        Write-Warning "Operação de reset cancelada pelo usuário."
    #        Write-Log -Message "Operação de reset cancelada pelo usuário na confirmação inicial." -FilePathParam $LogFilePath -Level INFO
    #        exit
    #    }
    # }
}


if ($PSCmdlet.ParameterSetName -eq 'FileMode') {
    Write-Log -Message "Iniciando processamento em FileMode. Arquivo: $FilePath" -FilePathParam $LogFilePath
    $lines = Get-Content $FilePath | Where-Object { $_.Trim() -ne '' }
    
    foreach ($line in $lines) {
        $pair = $line.Split(',') | ForEach-Object { $_.Trim() }
        if ($pair.Count -ne 2 -or $pair[0] -eq $pair[1] -or -not $pair[0] -or -not $pair[1]) {
            $invalidLineMsg = "Linha inválida ou incompleta: '$line'. Pulando."
            Write-Warning $invalidLineMsg
            Write-Log -Message $invalidLineMsg -FilePathParam $LogFilePath -Level WARNING
            continue
        }

        Write-Host "`nComparando: $($pair[0]) vs $($pair[1])" -ForegroundColor Yellow
        Write-Log -Message "Processando par: $($pair[0]) vs $($pair[1])" -FilePathParam $LogFilePath
        $infos = Get-UserInfo -Users $pair
        Show-Table -UserInfos $infos

        if ($infos.Count -ne 2 -or $infos[0].Nome -eq 'Não encontrado' -or $infos[1].Nome -eq 'Não encontrado') {
            $userNotFoundMsg = "Um ou ambos os usuários do par ('$($pair[0])', '$($pair[1])') não foram encontrados ou informações insuficientes. Nenhuma ação de reset."
            Write-Warning $userNotFoundMsg
            Write-Log -Message $userNotFoundMsg -FilePathParam $LogFilePath -Level WARNING
            continue
        }

        $user1Dept = $infos[0].DeptMain
        $user2Dept = $infos[1].DeptMain
        $userToResetSam = $infos[1].Usuario # Usuário 2 é o alvo

        if ($user1Dept -eq $user2Dept -and $user1Dept -ne 'N/D') {
            $sameDeptMsg = "Mesma unidade: $user1Dept"
            Write-Host $sameDeptMsg -ForegroundColor Green
            Write-Log -Message "$sameDeptMsg para o par ($($pair[0]) vs $($pair[1]))." -FilePathParam $LogFilePath

            if ($ResetModeSwitch.IsPresent) {
                Write-Log -Message "Modo Reset: Usuário alvo para reset é '$userToResetSam' (Usuário 2 do par)." -FilePathParam $LogFilePath
                
                if ($resetUsersThisRun.ContainsKey($userToResetSam)) {
                    $manualAttentionMsg = "ATENÇÃO MANUAL: Usuário '$userToResetSam' já teve a senha processada para reset nesta execução. Múltiplas solicitações para o mesmo usuário no arquivo devem ser avaliadas manualmente. Nenhuma ação de reset adicional para este usuário nesta linha."
                    Write-Warning $manualAttentionMsg
                    Write-Log -Message $manualAttentionMsg -FilePathParam $LogFilePath -Level WARNING
                } else {
                    # Adiciona à lista de processados ANTES de tentar o reset.
                    # Isso evita múltiplas tentativas mesmo se a primeira falhar ou for cancelada pelo -Confirm/-WhatIf.
                    $resetUsersThisRun[$userToResetSam] = $true 
                    Invoke-UserPasswordReset -UserSamAccountName $userToResetSam -LocalLogFilePath $LogFilePath
                }
            }
        } else {
            $diffDeptMsg = "Departamentos diferentes: $($user1Dept) vs $($user2Dept)"
            Write-Host $diffDeptMsg -ForegroundColor Red
            Write-Log -Message "$diffDeptMsg para o par ($($pair[0]) vs $($pair[1])). Nenhuma ação de reset." -FilePathParam $LogFilePath
            if ($ResetModeSwitch.IsPresent) {
                Write-Log -Message "Modo Reset: Reset não aplicável para '$userToResetSam' devido a departamentos diferentes no par." -FilePathParam $LogFilePath -Level INFO
            }
        }
    }

} elseif ($PSCmdlet.ParameterSetName -eq 'ListMode') {
    Write-Log -Message "Iniciando processamento em ListMode." -FilePathParam $LogFilePath
    $allUserInfos = Get-UserInfo -Users $UserLogonName
    Show-Table -UserInfos $allUserInfos

    if ($ResetModeSwitch.IsPresent) {
        Write-Log -Message "Modo Reset ativo para ListMode. Processando usuários da lista." -FilePathParam $LogFilePath
        foreach ($userInfo in $allUserInfos) {
            if ($userInfo.Nome -eq 'Não encontrado') {
                Write-Log -Message "Usuário '$($userInfo.Usuario)' (da lista) não encontrado. Reset ignorado." -FilePathParam $LogFilePath -Level WARNING
                continue
            }
            
            $currentUserSam = $userInfo.Usuario
            if ($resetUsersThisRun.ContainsKey($currentUserSam)) {
                $manualAttentionMsgList = "ATENÇÃO MANUAL: Usuário '$currentUserSam' (da lista) já teve a senha processada para reset nesta execução. Múltiplas solicitações devem ser avaliadas manualmente. Nenhuma ação de reset adicional."
                Write-Warning $manualAttentionMsgList
                Write-Log -Message $manualAttentionMsgList -FilePathParam $LogFilePath -Level WARNING
            } else {
                $resetUsersThisRun[$currentUserSam] = $true
                Invoke-UserPasswordReset -UserSamAccountName $currentUserSam -LocalLogFilePath $LogFilePath
            }
        }
    }
} else {
    $unrecognizedModeMsg = "Modo de execução não reconhecido."
    Write-Error $unrecognizedModeMsg
    Write-Log -Message $unrecognizedModeMsg -FilePathParam $LogFilePath -Level ERROR
}

Write-Host "`nProcessamento finalizado." -ForegroundColor Cyan
Write-Log -Message "Processamento finalizado." -FilePathParam $LogFilePath
