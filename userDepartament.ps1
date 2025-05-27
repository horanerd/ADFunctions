<#
.SYNOPSIS
    Busca e exibe informações de um ou mais usuários específicos no Active Directory
    e valida se pertencem ao mesmo departamento principal (primeira parte do nome do departamento).

.DESCRIPTION
    Este script consulta o Active Directory para encontrar um ou mais usuários específicos
    fornecendo seus nomes de logon. Exibe o SamAccountName, nome de exibição,
    departamento completo de cada usuário e, ao final, informa se todos os usuários encontrados
    compartilham o mesmo departamento principal (considerando apenas a string antes do primeiro espaço
    no nome do departamento, ou o nome completo se não houver espaços).

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
    .\Get-ADUsersInfoAndCompareMainDept.ps1 -UserLogonName "josedasilva", "anapereira"
    (Busca os usuários e valida se o início de seus departamentos é o mesmo.
     Ex: "Vendas" e "Vendas Internas" seriam considerados do mesmo departamento principal "Vendas".)

.EXAMPLE
    .\Get-ADUsersInfoAndCompareMainDept.ps1 -UserLogonName "ricardo.alves", "maria.souza"
    (Se Ricardo é "Diretoria12 Financeiro" e Maria é "Diretoria12 RH", serão considerados do mesmo
     departamento principal "Diretoria12".)
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
            $fullDepartmentFromAD = $adUser.Department # Departamento completo como está no AD
            $mainDepartmentForComparison = ""
            $fullDepartmentForDisplay = ""


            if ([string]::IsNullOrWhiteSpace($fullDepartmentFromAD)) {
                $fullDepartmentForDisplay = "Não especificado"
                $mainDepartmentForComparison = "Não especificado" # Padroniza para comparação
            } else {
                $fullDepartmentForDisplay = $fullDepartmentFromAD
                # Extrai a primeira parte do departamento (antes do primeiro espaço, ou o nome completo se não houver espaço)
                $mainDepartmentForComparison = ($fullDepartmentFromAD.Split(' ', 2)[0])
            }

            Write-Host "`n--- Informações do Usuário Encontrado ---" -ForegroundColor Green
            Write-Host "Entrada Fornecida             : $logonNameInput"
            Write-Host "Nome de Logon (SamAccountName): $($adUser.SamAccountName)"
            Write-Host "Nome de Exibição (DisplayName): $($adUser.DisplayName)"
            Write-Host "Departamento Completo         : $fullDepartmentForDisplay"
            Write-Host "Departamento Principal (Comp.): $mainDepartmentForComparison" # Mostra o que será comparado
            Write-Host "DN (DistinguishedName)      : $($adUser.DistinguishedName)"

            # Adiciona informações do usuário encontrado à lista para posterior comparação
            $foundUsersInfo += [PSCustomObject]@{
                SamAccountName  = $adUser.SamAccountName
                DisplayName     = $adUser.DisplayName
                FullDepartment  = $fullDepartmentForDisplay      # Armazena o departamento completo para exibição
                MainDepartment  = $mainDepartmentForComparison  # Armazena a parte principal para comparação
                InputProvided   = $logonNameInput
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

# Validação de Departamento Principal
if ($foundUsersInfo.Count -eq 0) {
    Write-Host "`nVALIDAÇÃO DE DEPARTAMENTO PRINCIPAL: Nenhum usuário foi encontrado. Não é possível comparar departamentos." -ForegroundColor Yellow
} elseif ($foundUsersInfo.Count -eq 1) {
    Write-Host "`nVALIDAÇÃO DE DEPARTAMENTO PRINCIPAL: Apenas um usuário foi encontrado ($($foundUsersInfo[0].SamAccountName) - Depto. Principal: $($foundUsersInfo[0].MainDepartment)). Não há outros usuários para comparar." -ForegroundColor Yellow
} else {
    Write-Host "`n--- VALIDAÇÃO DE DEPARTAMENTO PRINCIPAL (considerando a primeira parte do nome) ---" -ForegroundColor Cyan
    
    $firstUserMainDepartment = $foundUsersInfo[0].MainDepartment
    $allSameMainDepartment = $true # Assume que são iguais até encontrar um diferente

    Write-Host "Comparando os seguintes usuários e departamentos principais:"
    foreach ($userInfo in $foundUsersInfo) {
        Write-Host "  - Usuário: $($userInfo.SamAccountName), Depto. Completo: '$($userInfo.FullDepartment)', Depto. Principal (usado na comp.): '$($userInfo.MainDepartment)'"
        if ($userInfo.MainDepartment -ne $firstUserMainDepartment) {
            $allSameMainDepartment = $false
            # Não precisa de 'break' aqui se quiser listar todos, mas a validação já falhou neste ponto para a variável $allSameMainDepartment.
        }
    }

    if ($allSameMainDepartment) {
        Write-Host "`nRESULTADO: Todos os $($foundUsersInfo.Count) usuários encontrados pertencem ao MESMO departamento principal: '$firstUserMainDepartment'." -ForegroundColor Green
    } else {
        Write-Host "`nRESULTADO: Os usuários encontrados NÃO pertencem todos ao mesmo departamento principal." -ForegroundColor Red
        Write-Host "Consulte a lista detalhada acima para ver os departamentos principais de cada um."
    }
}
Write-Host "--------------------------------------------------"
