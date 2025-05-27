<#
.SYNOPSIS
    Busca e exibe informações de um ou mais usuários específicos no Active Directory
    com base em seus nomes de logon.

.DESCRIPTION
    Este script consulta o Active Directory para encontrar um ou mais usuários específicos
    fornecendo seus nomes de logon (SamAccountName, UserPrincipalName, etc.).
    Ele então exibe o SamAccountName, nome de exibição (DisplayName) e
    o departamento para cada usuário encontrado.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 26/05/2025
    Requerimentos:
        - Módulo Active Directory para PowerShell (RSAT-AD-PowerShell).
        - Permissões para ler objetos de usuário no AD (incluindo os atributos
          SamAccountName, DisplayName, Department).

.PARAMETER UserLogonName
    Um ou mais nomes de logon de usuário a serem pesquisados. Separe múltiplos nomes
    por vírgula. Pode ser o SamAccountName (ex: 'josedasilva'), UserPrincipalName
    (ex: 'josedasilva@empresa.com'), Distinguished Name, GUID ou SID.
    Este parâmetro é obrigatório.

.PARAMETER SearchBase
    Opcional. Especifica o Distinguished Name (DN) da Unidade Organizacional (OU)
    ou contêiner para limitar a pesquisa de todos os usuários fornecidos. Se não especificado,
    a pesquisa pode ocorrer em todo o domínio.

.EXAMPLE
    .\Get-ADUsersInfoByLogon.ps1 -UserLogonName "josedasilva"
    (Busca o usuário com SamAccountName 'josedasilva')

.EXAMPLE
    .\Get-ADUsersInfoByLogon.ps1 -UserLogonName "josedasilva@empresa.com", "anapereira"
    (Busca o usuário com UPN 'josedasilva@empresa.com' E o usuário com SamAccountName 'anapereira')

.EXAMPLE
    .\Get-ADUsersInfoByLogon.ps1 -UserLogonName "josedasilva", "anapereira" -SearchBase "OU=Vendas,DC=empresa,DC=com"
    (Busca os usuários 'josedasilva' e 'anapereira' especificamente dentro da OU 'Vendas')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Um ou mais nomes de logon de usuário (SamAccountName, UPN, DN, GUID ou SID). Separe múltiplos nomes por vírgula se fornecer diretamente na linha de comando.")]
    [string[]]$UserLogonName, # Alterado para aceitar um array de strings

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
        exit 1 # Sai do script se o módulo não puder ser carregado
    }
}

# Loop para processar cada nome de logon fornecido
foreach ($logonNameInput in $UserLogonName) {
    Write-Host "`n--------------------------------------------------" # Separador para cada usuário
    Write-Host "Processando solicitação para: '$logonNameInput'" -ForegroundColor Yellow

    $getUserParams = @{
        Properties = 'DisplayName', 'Department', 'SamAccountName' # SamAccountName é bom ter explicitamente
    }

    # Tentar resolver a identidade. Se Identity for um DN, SearchBase não é usado.
    # Se for um nome ambíguo (como SamAccountName), SearchBase pode ajudar a refinar.
    try {
        # Primeiro, tentar identificar o usuário.
        # O parâmetro -Identity é flexível.
        $getUserParams.Identity = $logonNameInput

        if ($PSBoundParameters.ContainsKey('SearchBase')) {
            # Adicionar SearchBase apenas se a identidade não for um DN,
            # pois Get-ADUser ignora SearchBase se Identity é um DN.
            # No entanto, para simplificar e cobrir casos de SamAccountName, vamos permitir que seja passado.
            # O usuário deve estar ciente de que se $logonNameInput for um DN completo, SearchBase não terá efeito.
            $getUserParams.SearchBase = $SearchBase
            Write-Host "Pesquisando '$logonNameInput' na OU: $SearchBase..." -ForegroundColor Cyan
        } else {
            Write-Host "Pesquisando '$logonNameInput'..." -ForegroundColor Cyan
        }
        
        $adUser = Get-ADUser @getUserParams
        
        if ($adUser) {
            $department = $adUser.Department
            if ([string]::IsNullOrWhiteSpace($department)) {
                $department = "Não especificado"
            }

            Write-Host "`n--- Informações do Usuário Encontrado ---" -ForegroundColor Green
            Write-Host "Entrada Fornecida             : $logonNameInput"
            Write-Host "Nome de Logon (SamAccountName): $($adUser.SamAccountName)"
            Write-Host "Nome de Exibição (DisplayName): $($adUser.DisplayName)"
            Write-Host "Departamento                  : $department"
            Write-Host "DN (DistinguishedName)      : $($adUser.DistinguishedName)"
        }
        # Get-ADUser com -Identity lança um erro se não encontra, então não precisamos de um 'else' aqui.
        # O bloco catch cuidará do usuário não encontrado.
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
