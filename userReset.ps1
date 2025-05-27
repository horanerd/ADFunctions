<#
.SYNOPSIS
    Script avançado para reset de senhas no Active Directory com validações de regras de negócio.

.DESCRIPTION
    Este script implementa todas as regras de negócio originais:
    - Validação de pares de usuários em arquivo TXT
    - Verificação de departamentos
    - Controle de usuários já processados
    - Exibição segura de senhas temporárias

.NOTES
    Versão: 2.1
    Autor: Guilherme de Sousa
    Data: 27/05/2025
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(ParameterSetName = 'FileMode', Mandatory = $true)]
    [ValidateScript({ 
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "Arquivo não encontrado: $_"
        }
        $true
    })]
    [string]$FilePath,

    [Parameter(ParameterSetName = 'ListMode', Mandatory = $true)]
    [string[]]$UserLogonName,

    [Parameter(ParameterSetName = 'FileMode')]
    [Parameter(ParameterSetName = 'ListMode')]
    [string]$SearchBase,

    [Parameter(ParameterSetName = 'FileMode')]
    [Parameter(ParameterSetName = 'ListMode')]
    [switch]$ResetModeSwitch
)

#region Configurações Iniciais
$ScriptVersion = "2.1"
$ExecutionStart = Get-Date
$ScriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$LogFilePath = Join-Path -Path $ScriptDir -ChildPath "ADPasswordReset_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Configuração de cores
$HeaderColor = 'Magenta'
$SuccessColor = 'Green'
$WarningColor = 'Yellow'
$ErrorColor = 'Red'
$InfoColor = 'Cyan'
$PasswordColor = 'White'
$UserColor = 'Cyan'

# Controle de usuários processados
$global:ProcessedUsers = @{}
$passwordResetTable = @()
#endregion

#region Funções Auxiliares
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "ACTION", "VALIDATION")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] - $Message"
    Add-Content -Path $LogFilePath -Value $logEntry -ErrorAction SilentlyContinue
}

function Show-ConsoleHeader {
    Write-Host "`n==============================================" -ForegroundColor $HeaderColor
    Write-Host " SISTEMA DE RESET DE SENHAS - v$ScriptVersion " -ForegroundColor $HeaderColor
    Write-Host " Início: $($ExecutionStart.ToString('dd/MM/yyyy HH:mm:ss')) " -ForegroundColor $HeaderColor
    Write-Host " Modo: $($PSCmdlet.ParameterSetName) " -ForegroundColor $HeaderColor
    if ($ResetModeSwitch) {
        Write-Host " MODO DE RESET ATIVO " -ForegroundColor $ErrorColor -BackgroundColor DarkBlue
    }
    Write-Host "==============================================`n" -ForegroundColor $HeaderColor
}

function New-StrongPassword {
    param([int]$Length = 14)
    $lower = 'abcdefghijkmnpqrstuvwxyz'
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits = '23456789'
    $special = '!@#$%*-_=+'
    
    $password = @(
        (Get-Random -InputObject $upper.ToCharArray() -Count 1),
        (Get-Random -InputObject $lower.ToCharArray() -Count 1),
        (Get-Random -InputObject $digits.ToCharArray() -Count 1),
        (Get-Random -InputObject $special.ToCharArray() -Count 1)
    )
    
    $allChars = $lower + $upper + $digits + $special
    $password += Get-Random -InputObject $allChars.ToCharArray() -Count ($Length - 4)
    
    return -join ($password | Sort-Object { Get-Random })
}

function Get-ADUserEnhanced {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        
        [string]$SearchBase
    )
    
    $properties = @(
        'SamAccountName', 'DisplayName', 'Enabled', 'Department', 
        'UserPrincipalName', 'SID', 'LockedOut', 'PasswordNeverExpires',
        'PasswordExpired', 'CannotChangePassword', 'LastBadPasswordAttempt',
        'LastLogonDate', 'Created'
    )
    
    $params = @{
        Identity = $Identity
        Properties = $properties
        ErrorAction = 'SilentlyContinue'
    }
    
    if ($SearchBase) { $params.SearchBase = $SearchBase }
    
    $user = Get-ADUser @params
    if (-not $user -and $Identity -like '*@*') {
        $user = Get-ADUser -Filter "UserPrincipalName -eq '$Identity'" @params
    }
    
    return $user
}

function Show-UserPasswordResult {
    param(
        [string]$UserName,
        [string]$DisplayName,
        [string]$Password,
        [bool]$Success,
        [string]$Message
    )
    
    if ($Success) {
        Write-Host "`n[USUÁRIO: $UserName]" -ForegroundColor $UserColor
        Write-Host "Nome: $DisplayName" -ForegroundColor $InfoColor
        Write-Host "Senha Temporária: " -NoNewline
        Write-Host $Password -ForegroundColor $PasswordColor -BackgroundColor DarkGray
        Write-Host "Status: " -NoNewline
        Write-Host "SENHA ALTERADA COM SUCESSO" -ForegroundColor $SuccessColor
        Write-Host "Instruções: " -NoNewline
        Write-Host "O usuário deve alterar a senha no próximo logon`n" -ForegroundColor $InfoColor
        
        $passwordResetTable += [PSCustomObject]@{
            Usuario = $UserName
            Nome = $DisplayName
            SenhaTemporaria = $Password
            Status = "SUCESSO"
            DataHora = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        }
    } else {
        Write-Host "`n[USUÁRIO: $UserName]" -ForegroundColor $UserColor
        Write-Host "Nome: $DisplayName" -ForegroundColor $InfoColor
        Write-Host "Status: " -NoNewline
        Write-Host "FALHA NO RESET" -ForegroundColor $ErrorColor
        Write-Host "Erro: " -NoNewline
        Write-Host $Message`n -ForegroundColor $ErrorColor
        
        $passwordResetTable += [PSCustomObject]@{
            Usuario = $UserName
            Nome = $DisplayName
            SenhaTemporaria = "N/A"
            Status = "FALHA: $Message"
            DataHora = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
        }
    }
}

function Test-BusinessRules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserIdentifier,
        
        [Parameter(Mandatory = $false)]
        [Microsoft.ActiveDirectory.Management.ADUser]$ADUser,
        
        [Parameter(Mandatory = $false)]
        [bool]$IsSecondUser = $false
    )
    
    # Regra 1: Verificar se o usuário já foi processado nesta execução
    if ($global:ProcessedUsers.ContainsKey($UserIdentifier)) {
        Write-Log -Message "Usuário $UserIdentifier já foi processado nesta execução" -Level VALIDATION
        throw "Usuário já processado nesta execução. Evite duplicações."
    }
    
    # Regra 2: Verificar se o usuário existe no AD
    if (-not $ADUser) {
        Write-Log -Message "Usuário $UserIdentifier não encontrado no AD" -Level VALIDATION
        throw "Usuário não encontrado no Active Directory"
    }
    
    # Regra 3: Verificar se a conta está ativada
    if (-not $ADUser.Enabled) {
        Write-Log -Message "Conta do usuário $UserIdentifier está desativada" -Level VALIDATION
        throw "Conta desativada - não é possível realizar operações"
    }
    
    # Regra 4: Apenas para o segundo usuário no modo arquivo
    if ($IsSecondUser) {
        # Regra 4.1: Verificar se o usuário pode alterar a senha
        if ($ADUser.CannotChangePassword) {
            Write-Log -Message "Usuário $UserIdentifier não pode alterar senha (CannotChangePassword)" -Level VALIDATION
            throw "Configuração impede alteração de senha pelo usuário"
        }
        
        # Regra 4.2: Verificar se a senha nunca expira
        if ($ADUser.PasswordNeverExpires) {
            Write-Log -Message "Senha do usuário $UserIdentifier não expira (PasswordNeverExpires)" -Level VALIDATION
            throw "Configuração de senha nunca expira - ajuste necessário"
        }
    }
    
    return $true
}
#endregion

#region Função Principal de Reset
function Invoke-PasswordResetOperation {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserIdentifier,
        
        [Parameter(Mandatory = $false)]
        [int]$PasswordLength = 14,
        
        [switch]$ForceUnlock,
        
        [Parameter(Mandatory = $false)]
        [bool]$IsSecondUser = $false
    )
    
    process {
        try {
            # Obter informações do usuário
            $adUser = Get-ADUserEnhanced -Identity $UserIdentifier -SearchBase $SearchBase
            
            # Validar regras de negócio
            Test-BusinessRules -UserIdentifier $UserIdentifier -ADUser $adUser -IsSecondUser $IsSecondUser
            
            # Desbloquear conta se necessário
            if ($adUser.LockedOut -and $ForceUnlock) {
                if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Desbloquear conta")) {
                    Unlock-ADAccount -Identity $adUser.SamAccountName
                    Write-Log -Message "Conta desbloqueada: $($adUser.SamAccountName)" -Level ACTION
                }
            }
            
            # Gerar nova senha
            $newPasswordPlain = New-StrongPassword -Length $PasswordLength
            $securePassword = ConvertTo-SecureString $newPasswordPlain -AsPlainText -Force
            
            if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Resetar senha")) {
                # Executar o reset
                Set-ADAccountPassword -Identity $adUser -NewPassword $securePassword -Reset
                Set-ADUser -Identity $adUser -ChangePasswordAtLogon $true
                
                # Registrar como processado
                $global:ProcessedUsers[$UserIdentifier] = $true
                
                # Registrar sucesso
                Write-Log -Message "Senha resetada para $($adUser.SamAccountName)" -Level ACTION
                
                # Exibir resultado no console
                Show-UserPasswordResult -UserName $adUser.SamAccountName `
                                       -DisplayName $adUser.DisplayName `
                                       -Password $newPasswordPlain `
                                       -Success $true `
                                       -Message "Senha alterada com sucesso"
                
                return $true
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Log -Message "Falha no reset para $UserIdentifier: $errorMsg" -Level ERROR
            
            Show-UserPasswordResult -UserName $UserIdentifier `
                                   -DisplayName ($adUser?.DisplayName ?? "N/A") `
                                   -Password "N/A" `
                                   -Success $false `
                                   -Message $errorMsg
            
            return $false
        }
    }
}
#endregion

#region Execução Principal
Show-ConsoleHeader
Write-Log -Message "Início da execução do script" -Level INFO

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log -Message "Módulo ActiveDirectory carregado com sucesso" -Level INFO
}
catch {
    $errorMsg = "Falha ao carregar módulo ActiveDirectory: $_"
    Write-Host $errorMsg -ForegroundColor $ErrorColor
    Write-Log -Message $errorMsg -Level ERROR
    exit 1
}

if ($ResetModeSwitch) {
    Write-Host "`nATENÇÃO: MODO DE RESET DE SENHA ATIVADO`n" -ForegroundColor $ErrorColor -BackgroundColor DarkBlue
    Write-Log -Message "Modo de reset de senha ativado" -Level WARNING
}

# Modo de operação por arquivo
if ($PSCmdlet.ParameterSetName -eq 'FileMode') {
    Write-Host "Processando arquivo: $FilePath" -ForegroundColor $InfoColor
    Write-Log -Message "Iniciando processamento do arquivo $FilePath" -Level INFO
    
    $lines = Get-Content $FilePath | Where-Object { $_.Trim() -ne '' }
    $processedPairs = 0
    $validPairs = 0
    
    foreach ($line in $lines) {
        $processedPairs++
        $pair = $line.Split(',') | ForEach-Object { $_.Trim() }
        
        # Validação básica do par
        if ($pair.Count -ne 2 -or $pair[0] -eq $pair[1] -or -not $pair[0] -or -not $pair[1]) {
            $warningMsg = "Linha inválida: '$line'. Formato esperado: 'usuario1, usuario2'"
            Write-Host $warningMsg -ForegroundColor $WarningColor
            Write-Log -Message $warningMsg -Level WARNING
            continue
        }
        
        Write-Host "`nProcessando par $processedPairs : $($pair[0]) e $($pair[1])" -ForegroundColor $InfoColor
        
        # Obter informações dos usuários
        $user1 = Get-ADUserEnhanced -Identity $pair[0] -SearchBase $SearchBase
        $user2 = Get-ADUserEnhanced -Identity $pair[1] -SearchBase $SearchBase
        
        # Validar regras de negócio para o par
        try {
            # Validar usuário 1 (apenas verificação básica)
            Test-BusinessRules -UserIdentifier $pair[0] -ADUser $user1 -IsSecondUser $false
            
            # Validar usuário 2 (verificação completa)
            Test-BusinessRules -UserIdentifier $pair[1] -ADUser $user2 -IsSecondUser $true
            
            # Verificar departamento (regra de negócio adicional)
            $deptUser1 = if ($user1.Department) { $user1.Department.Split()[0] } else { $null }
            $deptUser2 = if ($user2.Department) { $user2.Department.Split()[0] } else { $null }
            
            if (-not $deptUser1 -or -not $deptUser2 -or $deptUser1 -ne $deptUser2) {
                throw "Departamentos não coincidem ou não especificados ($deptUser1 vs $deptUser2)"
            }
            
            $validPairs++
            
            # Se todas as validações passaram e o modo reset está ativo
            if ($ResetModeSwitch) {
                Write-Host "Departamentos coincidem ($deptUser1) - realizando reset para $($user2.SamAccountName)" -ForegroundColor $SuccessColor
                Invoke-PasswordResetOperation -UserIdentifier $user2.SamAccountName -PasswordLength 14 -ForceUnlock -IsSecondUser $true
            }
            else {
                Write-Host "Validações passaram (Departamento: $deptUser1) - Modo Reset não está ativo" -ForegroundColor $InfoColor
            }
        }
        catch {
            Write-Host "Falha na validação: $($_.Exception.Message)" -ForegroundColor $ErrorColor
            Write-Log -Message "Falha na validação para par $($pair[0]),$($pair[1]): $($_.Exception.Message)" -Level VALIDATION
        }
    }
    
    Write-Host "`nResumo do processamento:" -ForegroundColor $HeaderColor
    Write-Host " - Total de pares processados: $processedPairs" -ForegroundColor $InfoColor
    Write-Host " - Total de pares válidos: $validPairs" -ForegroundColor $SuccessColor
    Write-Host " - Total de pares inválidos: $($processedPairs - $validPairs)" -ForegroundColor $($validPairs -eq $processedPairs ? 'Success' : 'Warning')
}

# Modo de operação por lista
elseif ($PSCmdlet.ParameterSetName -eq 'ListMode') {
    Write-Host "Processando lista de usuários: $($UserLogonName -join ', ')" -ForegroundColor $InfoColor
    Write-Log -Message "Iniciando processamento da lista de usuários" -Level INFO
    
    foreach ($user in $UserLogonName) {
        if ($ResetModeSwitch) {
            Write-Host "`nProcessando usuário: $user" -ForegroundColor $InfoColor
            Invoke-PasswordResetOperation -UserIdentifier $user -PasswordLength 14 -ForceUnlock
        }
        else {
            $userInfo = Get-ADUserEnhanced -Identity $user -SearchBase $SearchBase
            if ($userInfo) {
                Write-Host "`nInformações do usuário $user" -ForegroundColor $InfoColor
                Write-Host "Nome: $($userInfo.DisplayName)"
                Write-Host "Status: $($userInfo.Enabled ? 'Ativo' : 'Inativo')"
                Write-Host "Departamento: $($userInfo.Department ?? 'Não especificado')"
            }
            else {
                Write-Host "Usuário $user não encontrado" -ForegroundColor $ErrorColor
            }
        }
    }
}

# Exibir resumo final
if ($ResetModeSwitch -and $passwordResetTable.Count -gt 0) {
    Write-Host "`n`n==============================================" -ForegroundColor $HeaderColor
    Write-Host " RESUMO DE SENHAS RESETADAS " -ForegroundColor $HeaderColor
    Write-Host "==============================================" -ForegroundColor $HeaderColor
    
    $passwordResetTable | Format-Table -AutoSize -Property @(
        @{Label="Usuário"; Expression={$_.Usuario}; Alignment="Left"},
        @{Label="Nome"; Expression={$_.Nome}; Alignment="Left"},
        @{Label="Senha Temporária"; Expression={$_.SenhaTemporaria}; Alignment="Left"},
        @{Label="Status"; Expression={$_.Status}; Alignment="Left"},
        @{Label="Data/Hora"; Expression={$_.DataHora}; Alignment="Left"}
    )
    
    Write-Host "`nATENÇÃO: Estas senhas são temporárias e devem ser comunicadas aos usuários com segurança." -ForegroundColor $WarningColor
    Write-Host "Os usuários serão obrigados a alterar a senha no próximo logon.`n" -ForegroundColor $InfoColor
}

$executionTime = (Get-Date) - $ExecutionStart
Write-Host "`nTempo total de execução: $($executionTime.TotalSeconds.ToString('N2')) segundos" -ForegroundColor $InfoColor
Write-Log -Message "Script concluído em $($executionTime.TotalSeconds.ToString('N2')) segundos" -Level INFO
#endregion
