<#
.SYNOPSIS
    Busca e exibe informações de um usuário específico no Active Directory
    com base no seu nome de logon.

.DESCRIPTION
    Este script consulta o ActiveDirectory para encontrar um usuário específico
    fornecendo seu nome de logon (SamAccountName, UserPrincipalName, etc.).
    Ele então exibe o SamAccountName, nome de exibição (DisplayName) e
    o departamento do usuário encontrado.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 26/05/2025
    Requerimentos:
        - Módulo Active Directory para PowerShell (RSAT-AD-PowerShell).
        - Permissões para ler objetos de usuário no AD (incluindo os atributos
          SamAccountName, DisplayName, Department).

.PARAMETER UserLogonName
    O nome de logon do usuário a ser pesquisado. Pode ser o SamAccountName
    (ex: 'josedasilva'), UserPrincipalName (ex: 'josedasilva@empresa.com'),
    Distinguished Name, GUID ou SID. Este parâmetro é obrigatório.

.PARAMETER SearchBase
    Opcional. Especifica o Distinguished Name (DN) da Unidade Organizacional (OU)
    ou contêiner para limitar a pesquisa do usuário. Se não especificado,
    a pesquisa pode ocorrer em todo o domínio (dependendo da configuração do AD
    e do tipo de identidade fornecida).

.EXAMPLE
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva"
    (Busca o usuário com SamAccountName 'josedasilva')

.EXAMPLE
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva@empresa.com"
    (Busca o usuário com UserPrincipalName 'josedasilva@empresa.com')

.EXAMPLE
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva" -SearchBase "OU=Vendas,DC=empresa,DC=com"
    (Busca o usuário 'josedasilva' especificamente dentro da OU 'Vendas')
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Nome de logon do usuário (SamAccountName, UPN, DN, GUID ou SID).")]
    [string]$UserLogonName,

    [Parameter(Mandatory = $false, HelpMessage = "Opcional. DN da OU para restringir a pesquisa.")]
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

# Parâmetros para Get-ADUser
$getUserParams = @{
    Identity   = $UserLogonName
    Properties = 'DisplayName', 'Department', 'SamAccountName' # SamAccountName é bom ter explicitamente
}

if ($PSBoundParameters.ContainsKey('SearchBase')) {
    $getUserParams.SearchBase = $SearchBase
    Write-Host "Pesquisando usuário '$UserLogonName' na OU: $SearchBase..." -ForegroundColor Cyan
} else {
    Write-Host "Pesquisando usuário '$UserLogonName'..." -ForegroundColor Cyan
}

try {
    $adUser = Get-ADUser @getUserParams
    
    if ($adUser) {
        $department = $adUser.Department
        if ([string]::IsNullOrWhiteSpace($department)) {
            $department = "Não especificado"
        }

        Write-Host "`n--- Informações do Usuário ---" -ForegroundColor Green
        Write-Host "Nome de Logon (SamAccountName): $($adUser.SamAccountName)"
        Write-Host "Nome de Exibição (DisplayName): $($adUser.DisplayName)"
        Write-Host "Departamento                  : $department"
        Write-Host "DN (DistinguishedName)      : $($adUser.DistinguishedName)"
        
        # Você pode criar um objeto para exportação ou uso posterior se desejar
        # $userInfo = [PSCustomObject]@{
        #     SamAccountName = $adUser.SamAccountName
        #     DisplayName    = $adUser.DisplayName
        #     Departamento   = $department
        #     UserDN         = $adUser.DistinguishedName
        # }
        # $userInfo | Format-List # Ou Format-Table
        
    }
    # Get-ADUser com -Identity lança um erro se não encontra, então não precisamos de um 'else' aqui.
    # O bloco catch cuidará do usuário não encontrado.

}
catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Error "Usuário com identificador '$UserLogonName' não encontrado no Active Directory."
    if ($PSBoundParameters.ContainsKey('SearchBase')) {
        Write-Warning "Verifique se o usuário existe na OU especificada: $SearchBase"
    }
}
catch {
    Write-Error "Ocorreu um erro ao buscar o usuário '$UserLogonName': $($_.Exception.Message)"
}
