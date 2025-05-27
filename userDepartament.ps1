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
    Autor: Guilherme De Sousa do Nascimento
    Versão: 1.0
    Data: 27/05/2025
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
    Write-Error "Erro ao importar o módulo ActiveDirectory: $_"
    exit 1
}

function Convert-PwdLastSet {
    param ([object]$pwdLastSet)
    if ($null -eq $pwdLastSet -or $pwdLastSet -le 0) {
        return "Senha indefinida ou usuário deve alterá-la ao logar"
    }
    try {
        $date = [datetime]::FromFileTime($pwdLastSet)
        $age = [math]::Floor((Get-Date - $date).TotalDays)
        return "$($date.ToString('dd/MM/yyyy')) ($age dias atrás)"
    } catch {
        return "Erro ao converter pwdLastSet"
    }
}

function Get-UserInfo {
    param (
        [string[]]$Users
    )

    $filterScript = { $_ }
    $props = 'SamAccountName','DisplayName','Enabled','Department','pwdLastSet','UserPrincipalName','SID','LockedOut'

    $result = @()
    foreach ($user in $Users) {
        $params = @{ Identity = $user; Properties = $props; ErrorAction = 'SilentlyContinue' }
        if ($SearchBase) { $params.SearchBase = $SearchBase }

        $u = Get-ADUser @params
        if ($u) {
            $dept = if ($u.Department) { $u.Department.Trim() } else { 'Não especificado' }
            $mainDept = ($dept -split '\s+')[0]
            $pwdLastSet = Convert-PwdLastSet -pwdLastSet $u.pwdLastSet

            $result += [PSCustomObject]@{
                Usuario   = $u.SamAccountName
                Nome      = $u.DisplayName
                Ativo     = if ($u.Enabled) { 'Sim' } else { 'Não' }
                Bloqueado = if ($u.LockedOut) { 'Sim' } else { 'Não' }
                DeptMain  = $mainDept
                DeptFull  = $dept
                SenhaUltAlteracao = $pwdLastSet
            }
        } else {
            $result += [PSCustomObject]@{
                Usuario   = $user
                Nome      = 'Não encontrado'
                Ativo     = 'N/D'
                Bloqueado = 'N/D'
                DeptMain  = 'N/D'
                DeptFull  = 'N/D'
                SenhaUltAlteracao = 'N/D'
            }
        }
    }
    return $result
}

function Show-Table {
    param ([array]$UserInfos)
    $UserInfos | Sort-Object DeptMain, Usuario | Format-Table -AutoSize
}

if ($PSCmdlet.ParameterSetName -eq 'FileMode') {
    $lines = Get-Content $FilePath | Where-Object { $_.Trim() -ne '' }
    foreach ($line in $lines) {
        $pair = $line.Split(',') | ForEach-Object { $_.Trim() }
        if ($pair.Count -ne 2 -or $pair[0] -eq $pair[1]) {
            Write-Warning "Linha inválida: '$line'"
            continue
        }
        Write-Host "\nComparando: $($pair[0]) x $($pair[1])" -ForegroundColor Yellow
        $infos = Get-UserInfo -Users $pair
        Show-Table -UserInfos $infos
        if ($infos[0].DeptMain -eq $infos[1].DeptMain) {
            Write-Host "Mesma unidade: $($infos[0].DeptMain)" -ForegroundColor Green
        } else {
            Write-Host "Departamentos diferentes: $($infos[0].DeptMain) vs $($infos[1].DeptMain)" -ForegroundColor Red
        }
    }
} elseif ($PSCmdlet.ParameterSetName -eq 'ListMode') {
    $infos = Get-UserInfo -Users $UserLogonName
    Show-Table -UserInfos $infos
} else {
    Write-Error "Modo de execução não reconhecido."
} 

Write-Host "\nProcessamento finalizado." -ForegroundColor Cyan
