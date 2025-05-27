<#
.SYNOPSIS
    Busca e exibe informações de um ou mais usuários específicos no Active Directory
    e valida se pertencem ao mesmo departamento.

.DESCRIPTION
    Este script consulta o Active Directory para encontrar um ou mais usuários específicos
    fornecendo seus nomes de logon. Exibe o SamAccountName, nome de exibição,
    departamento de cada usuário e, ao final, informa se todos os usuários encontrados
    compartilham o mesmo departamento.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 26/05/2025
    Requerimentos:
        - Módulo Active Directory para PowerShell (RSAT-AD-PowerShell).
        - Permissões para ler objetos de usuário no AD.

.PARAMETER UserLogonName
    Um ou mais nomes de logon de usuário a serem pesquisados. Separe múltiplos nomes
    por vírgula. Pode ser o SamAccountName, UserPrincipalName, DN, GUID ou SID.
    Obrigatório.

.PARAMETER SearchBase
    Opcional. DN da OU para restringir a pesquisa para todos os usuários fornecidos.

.EXAMPLE
    .\Get-ADUsersInfoAndCompareDept.ps1 -UserLogonName "josedasilva"
    (Busca 'josedasilva'. Validação de departamento não aplicável para um único usuário.)

.EXAMPLE
    .\Get-ADUsersInfoAndCompareDept.ps1 -UserLogonName "josedasilva", "anapereira"
    (Busca 'josedasilva' e 'anapereira' e valida se são do mesmo departamento.)

.EXAMPLE
    .\Get-ADUsersInfoAndCompareDept.ps1 -UserLogonName "j.doe", "m.smith", "r.jones" -SearchBase "OU=EscritorioSP,DC=empresa,DC=com"
    (Busca os três usuários na OU EscritorioSP e valida seus departamentos.)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Um ou mais nomes de logon de usuário (SamAccountName, UPN, DN, GUID ou SID). Separe múltiplos nomes por vírgula se fornecer diretamente na linha de comando.")]
    [string[]]$UserLogonName,

    [Parameter(Mandatory = $false, HelpMessage = "Opcional. DN da OU para restringir a pesquisa para todos os usuários fornecidos.")]
    [string]$SearchBase
)

# Importar o módulo do Active Directory se não estiver carregado
if (-not (Get-Module ActiveDirectory)) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "Módulo ActiveDirectory importado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Error "Falha ao importar o módulo ActiveDirectory. Certifique-se de que as Ferramentas de Administração de Servidor Remoto (RSAT) para AD DS estão instaladas."
        exit 1
    }
}

$foundUsersInfo = @() # Array para armazenar informações dos usuários encontrados

# Loop para processar cada nome de logon fornecido
foreach ($logonNameInput in $UserLogonName) {
    Write-Host "`n--------------------------------------------------"
    Write-Host "Processando solicitação para: '$logonNameInput'" -ForegroundColor Yellow

    $getUserParams = @{
        Identity   = $logonNameInput
        Properties = 'DisplayName', 'Department', 'SamAccountName'
    }

    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        $getUserParams.SearchBase = $SearchBase
        Write-Host "Pesquisando '$logonNameInput' na OU: $SearchBase..." -ForegroundColor Cyan
    } else {
        Write-Host "Pesquisando '$logonNameInput'..." -ForegroundColor Cyan
    }
    
    try {
        $adUser = Get-ADUser @getUserParams
        
        if ($adUser) {
            $department = $adUser.Department
            if ([string]::IsNullOrWhiteSpace($department)) {
                $department = "Não especificado" # Padroniza departamento vazio
            }

            Write-Host "`n--- Informações do Usuário Encontrado ---" -ForegroundColor Green
            Write-Host "Entrada Fornecida             : $logonNameInput"
            Write-Host "Nome de Logon (SamAccountName): $($adUser.SamAccountName)"
            Write-Host "Nome de Exibição (DisplayName): $($adUser.DisplayName)"
            Write-Host "Departamento                  : $department"
            Write-Host "DN (DistinguishedName)      : $($adUser.DistinguishedName)"

            # Adiciona informações do usuário encontrado à lista para posterior comparação
            $foundUsersInfo += [PSCustomObject]@{
                SamAccountName = $adUser.SamAccountName
                DisplayName    = $adUser.DisplayName
                Department     = $department
                InputProvided  = $logonNameInput
            }
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Error "Usuário com identificador '$logonNameInput' não encontrado no Active Directory."
        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            Write-Warning "Verifique se o usuário existe na OU especificada ($SearchBase) ou se o identificador é globalmente único."
        }
    }
    catch {
        Write-Error "Ocorreu um erro ao buscar o usuário '$logonNameInput': $($_.Exception.Message)"
    }
}

Write-Host "`n--------------------------------------------------"
Write-Host "Processamento de todos os usuários fornecidos concluído." -ForegroundColor Green

# Validação de Departamento
if ($foundUsersInfo.Count -eq 0) {
    Write-Host "`nVALIDAÇÃO DE DEPARTAMENTO: Nenhum usuário foi encontrado. Não é possível comparar departamentos." -ForegroundColor Yellow
} elseif ($foundUsersInfo.Count -eq 1) {
    Write-Host "`nVALIDAÇÃO DE DEPARTAMENTO: Apenas um usuário foi encontrado ($($foundUsersInfo[0].SamAccountName) - Depto: $($foundUsersInfo[0].Department)). Não há outros usuários para comparar." -ForegroundColor Yellow
} else {
    Write-Host "`n--- VALIDAÇÃO DE DEPARTAMENTO ---" -ForegroundColor Cyan
    
    $firstUserDepartment = $foundUsersInfo[0].Department
    $allSameDepartment = $true

    foreach ($userInfo in $foundUsersInfo) {
        Write-Host "  Usuário: $($userInfo.SamAccountName), Departamento: $($userInfo.Department)" # Lista para conferência
        if ($userInfo.Department -ne $firstUserDepartment) {
            $allSameDepartment = $false
        }
    }

    if ($allSameDepartment) {
        Write-Host "`nRESULTADO: Todos os $($foundUsersInfo.Count) usuários encontrados pertencem ao MESMO departamento: '$firstUserDepartment'." -ForegroundColor Green
    } else {
        Write-Host "`nRESULTADO: Os usuários encontrados NÃO pertencem todos ao mesmo departamento." -ForegroundColor Red
        Write-Host "Consulte a lista acima para ver os departamentos individuais."
    }
}
Write-Host "--------------------------------------------------"
