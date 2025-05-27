<#
.SYNOPSIS
    Consulta informações de usuários no Active Directory com validações específicas e apresenta resultados organizados.

.DESCRIPTION
    Este script opera em dois modos principais para consultar usuários no AD:
    1. Modo Arquivo (-FilePath): Processa pares de usuários definidos em um arquivo TXT
    2. Modo Lista (-UserLogonName): Processa uma lista manual de usuários fornecidos como parâmetro

    Para cada usuário, coleta e processa diversos atributos incluindo status da conta, departamento e informações de senha.

.PARAMETER FilePath
    Caminho para um arquivo TXT contendo pares de usuários (um par por linha, separados por vírgula).

.PARAMETER UserLogonName
    Array de identificadores de usuários para consulta (SamAccountName, UserPrincipalName, etc).

.PARAMETER SearchBase
    Opcional. Distinguished Name de uma OU para restringir as buscas no AD.

.EXAMPLE
    .\ADUserQuery.ps1 -FilePath "C:\usuarios.txt" -SearchBase "OU=Users,DC=empresa,DC=com"
    Processa os pares de usuários do arquivo, restringindo a busca à OU especificada.

.EXAMPLE
    .\ADUserQuery.ps1 -UserLogonName "user1", "user2@empresa.com", "S-1-5-21-..."
    Consulta informações para os três usuários especificados.

.NOTES
    Autor: [Seu Nome]
    Versão: 1.0
    Data: [Data]
#>

param (
    [Parameter(ParameterSetName = 'FileMode', Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$FilePath,

    [Parameter(ParameterSetName = 'ListMode', Mandatory = $true)]
    [string[]]$UserLogonName,

    [Parameter(ParameterSetName = 'FileMode')]
    [Parameter(ParameterSetName = 'ListMode')]
    [string]$SearchBase
)

# Verifica e importa o módulo ActiveDirectory
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Falha ao carregar o módulo ActiveDirectory: $_"
    exit 1
}

# Função auxiliar para converter pwdLastSet em data legível e calcular idade
function Convert-PwdLastSet {
    param (
        [object]$pwdLastSet
    )

    if ($null -eq $pwdLastSet -or $pwdLastSet -le 0) {
        if ($pwdLastSet -eq 0) {
            return @{
                Status = "Usuário deve alterar senha no próximo logon"
                Age    = $null
                Date   = $null
                Raw    = $pwdLastSet
            }
        } else {
            return @{
                Status = "Senha não definida para expirar ou config. especial (valor bruto: $pwdLastSet)"
                Age    = $null
                Date   = $null
                Raw    = $pwdLastSet
            }
        }
    }

    try {
        $date = [datetime]::FromFileTime($pwdLastSet)
        $age = [math]::Floor(([datetime]::Now - $date).TotalDays)
        
        return @{
            Status = "$age dia(s) atrás"
            Age    = $age
            Date   = $date.ToString("dd/MM/yyyy HH:mm:ss")
            Raw    = $pwdLastSet
        }
    } catch {
        return @{
            Status = "Erro na conversão de pwdLastSet: $_ (valor bruto: $pwdLastSet)"
            Age    = $null
            Date   = $null
            Raw    = $pwdLastSet
        }
    }
}

# Função auxiliar para processar informações do usuário
function Get-ProcessedUserInfo {
    param (
        [string]$UserIdentifier,
        [string]$SearchBase
    )

    $params = @{
        Identity = $UserIdentifier
        Properties = 'SamAccountName', 'DisplayName', 'Enabled', 'Department', 'pwdLastSet', 'UserPrincipalName', 'SID'
        ErrorAction = 'SilentlyContinue'
    }

    if ($SearchBase) {
        $params['SearchBase'] = $SearchBase
    }

    try {
        $adUser = Get-ADUser @params

        if (-not $adUser) {
            return [PSCustomObject]@{
                Found               = $false
                ErrorMessage       = "Usuário '$UserIdentifier' não encontrado"
                SamAccountName     = $null
                DisplayName       = $null
                AccountStatus     = $null
                DepartmentFull    = $null
                MainDepartment    = $null
                PwdLastSetInfo     = $null
                UserPrincipalName  = $null
                SID               = $null
            }
        }

        # Processa o departamento
        $deptFull = if ([string]::IsNullOrEmpty($adUser.Department)) { "Não especificado" } else { $adUser.Department.Trim() }
        $mainDept = if ($deptFull -eq "Não especificado") { $deptFull } else { ($deptFull -split '\s+')[0] }

        # Processa pwdLastSet
        $pwdInfo = Convert-PwdLastSet -pwdLastSet $adUser.pwdLastSet

        return [PSCustomObject]@{
            Found               = $true
            ErrorMessage       = $null
            SamAccountName     = $adUser.SamAccountName
            DisplayName       = $adUser.DisplayName
            AccountStatus     = if ($adUser.Enabled) { "Ativada" } else { "Desativada" }
            DepartmentFull    = $deptFull
            MainDepartment    = $mainDept
            PwdLastSetInfo    = $pwdInfo
            UserPrincipalName = $adUser.UserPrincipalName
            SID              = $adUser.SID
        }
    } catch {
        return [PSCustomObject]@{
            Found               = $false
            ErrorMessage       = "Erro ao buscar usuário '$UserIdentifier': $_"
            SamAccountName     = $null
            DisplayName       = $null
            AccountStatus     = $null
            DepartmentFull    = $null
            MainDepartment    = $null
            PwdLastSetInfo     = $null
            UserPrincipalName  = $null
            SID               = $null
        }
    }
}

# Variáveis globais para armazenar usuários processados e pwdLastSet já exibidos
$global:processedUsers = @{}
$global:shownPwdLastSet = @{}
$global:allFoundUsers = @{}

# Função para exibir informações do usuário
function Show-UserInfo {
    param (
        [PSCustomObject]$UserInfo,
        [bool]$ShowPwdLastSet = $true,
        [bool]$IsSecondUser = $false
    )

    if (-not $UserInfo.Found) {
        Write-Warning $UserInfo.ErrorMessage
        return
    }

    # Adiciona usuário à lista global de encontrados
    if (-not $global:allFoundUsers.ContainsKey($UserInfo.SamAccountName)) {
        $global:allFoundUsers[$UserInfo.SamAccountName] = $UserInfo
    }

    Write-Host "`nInformações do Usuário:" -ForegroundColor Cyan
    Write-Host "  SamAccountName: $($UserInfo.SamAccountName)"
    Write-Host "  DisplayName: $($UserInfo.DisplayName)"
    Write-Host "  Status da Conta: $($UserInfo.AccountStatus)"
    Write-Host "  Departamento Principal: $($UserInfo.MainDepartment)"
    Write-Host "  Departamento Completo: $($UserInfo.DepartmentFull)"

    if ($ShowPwdLastSet) {
        if ($IsSecondUser -and $global:shownPwdLastSet.ContainsKey($UserInfo.SamAccountName)) {
            Write-Warning "(Info PwdLastSet para $($UserInfo.SamAccountName) já exibida)"
        } else {
            $pwdInfo = $UserInfo.PwdLastSetInfo
            if ($pwdInfo.Date) {
                Write-Host "  Última alteração de senha: $($pwdInfo.Date) ($($pwdInfo.Status))"
            } else {
                Write-Host "  Última alteração de senha: $($pwdInfo.Status)"
            }
            
            if ($IsSecondUser) {
                $global:shownPwdLastSet[$UserInfo.SamAccountName] = $true
            }
        }
    }
}

# Modo Arquivo
if ($PSCmdlet.ParameterSetName -eq 'FileMode') {
    Write-Host "`nProcessando arquivo: $FilePath" -ForegroundColor Magenta
    $lines = Get-Content $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        Write-Host "`n=== Processando linha: '$trimmedLine' ===" -ForegroundColor Yellow

        $userInputs = $trimmedLine -split ',' | ForEach-Object { $_.Trim() }
        
        # Validação do formato da linha
        if ($userInputs.Count -ne 2 -or [string]::IsNullOrEmpty($userInputs[0]) -or [string]::IsNullOrEmpty($userInputs[1])) {
            Write-Warning "Formato inválido na linha: '$trimmedLine'. Esperado: 'usuario1, usuario2'. Esta linha será ignorada."
            continue
        }

        # Verifica se os usuários são idênticos
        if ($userInputs[0] -eq $userInputs[1]) {
            Write-Error "ENTRADA INCORRETA NA LINHA: '$trimmedLine'. Os dois identificadores de usuário são idênticos ('$($userInputs[0])'). Um usuário não pode ser comparado consigo mesmo. Este par será ignorado."
            continue
        }

        $user1 = $userInputs[0]
        $user2 = $userInputs[1]

        # Obtém informações dos usuários
        $userInfo1 = Get-ProcessedUserInfo -UserIdentifier $user1 -SearchBase $SearchBase
        $userInfo2 = Get-ProcessedUserInfo -UserIdentifier $user2 -SearchBase $SearchBase

        # Exibe informações básicas para ambos os usuários
        Write-Host "`nUsuário 1:" -ForegroundColor Green
        Show-UserInfo -UserInfo $userInfo1 -ShowPwdLastSet $false

        Write-Host "`nUsuário 2:" -ForegroundColor Green
        Show-UserInfo -UserInfo $userInfo2 -ShowPwdLastSet $true -IsSecondUser $true

        # Comparação de departamento principal
        if ($userInfo1.Found -and $userInfo2.Found) {
            if ($userInfo1.MainDepartment -eq $userInfo2.MainDepartment) {
                Write-Host "`nRESULTADO PARA O PAR: PERTENCEM ao MESMO departamento principal ('$($userInfo1.MainDepartment)')" -ForegroundColor Green
            } else {
                Write-Host "`nRESULTADO PARA O PAR: NÃO PERTENCEM ao mesmo departamento principal ('$($userInfo1.MainDepartment)' vs '$($userInfo2.MainDepartment)')" -ForegroundColor Red
            }
        } else {
            Write-Warning "Não foi possível comparar departamentos para este par (um ou ambos os usuários não foram encontrados)"
        }
    }
}

# Modo Lista
if ($PSCmdlet.ParameterSetName -eq 'ListMode') {
    Write-Host "`nProcessando lista de usuários: $($UserLogonName -join ', ')" -ForegroundColor Magenta

    foreach ($user in $UserLogonName) {
        Write-Host "`n=== Processando usuário: '$user' ===" -ForegroundColor Yellow
        $userInfo = Get-ProcessedUserInfo -UserIdentifier $user -SearchBase $SearchBase
        Show-UserInfo -UserInfo $userInfo -ShowPwdLastSet $true
    }
}

# Sumário Final
Write-Host "`n=== SUMÁRIO FINAL ===" -ForegroundColor Magenta

if ($global:allFoundUsers.Count -eq 0) {
    Write-Host "Nenhum usuário foi encontrado durante a execução do script." -ForegroundColor Yellow
} else {
    # Agrupa usuários por departamento principal
    $deptGroups = $global:allFoundUsers.Values | Group-Object -Property MainDepartment

    foreach ($group in $deptGroups) {
        $userList = $group.Group | ForEach-Object { "$($_.SamAccountName) ($($_.AccountStatus))" }
        $userListString = $userList -join ', '

        if ($group.Count -gt 1) {
            Write-Host "`nDepartamento Principal: '$($group.Name)': $userListString (Estes usuários compartilham o mesmo departamento principal entre si)" -ForegroundColor Cyan
        } else {
            Write-Host "`nDepartamento Principal: '$($group.Name)': $userListString (Este usuário é o único encontrado neste departamento principal na lista processada)" -ForegroundColor Cyan
        }
    }
}

Write-Host "`nProcessamento concluído.`n" -ForegroundColor Green
