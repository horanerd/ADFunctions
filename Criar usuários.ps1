# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Nome do domínio base (ajuste conforme seu domínio real)
$dominio = "DC=horanerd,DC=com,DC=br"

# Criação da Unidade Organizacional "RH"
$ouPath = "OU=RH,$dominio"
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'RH'" -SearchBase $dominio -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name "RH" -Path $dominio
    Write-Host "OU 'RH' criada com sucesso."
} else {
    Write-Host "OU 'RH' já existe."
}

# Lista de usuários a serem criados
$usuarios = @(
    @{Nome="Ana Silva";       Cargo="Analista Jr";   Usuario="ana.silva";     Senha="Senha@123"},
    @{Nome="Bruno Costa";     Cargo="Analista Jr";   Usuario="bruno.costa";   Senha="Senha@123"},
    @{Nome="Carlos Mendes";   Cargo="Analista Pleno";Usuario="carlos.mendes"; Senha="Senha@123"},
    @{Nome="Daniela Rocha";   Cargo="Analista Pleno";Usuario="daniela.rocha"; Senha="Senha@123"},
    @{Nome="Eduardo Lima";    Cargo="Coordenador RH";Usuario="eduardo.lima";  Senha="Senha@123"}
)

# Criação dos usuários
foreach ($usuario in $usuarios) {
    $userDn = "CN=$($usuario.Nome),$ouPath"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($usuario.Usuario)'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name $usuario.Nome `
            -SamAccountName $usuario.Usuario `
            -UserPrincipalName "$($usuario.Usuario)@empresa.local" `
            -AccountPassword (ConvertTo-SecureString $usuario.Senha -AsPlainText -Force) `
            -Path $ouPath `
            -Enabled $true `
            -GivenName ($usuario.Nome.Split(" ")[0]) `
            -Surname ($usuario.Nome.Split(" ")[1]) `
            -DisplayName $usuario.Nome `
            -Title $usuario.Cargo `
            -ChangePasswordAtLogon $true

        Write-Host "Usuário '$($usuario.Nome)' criado com sucesso."
    } else {
        Write-Host "Usuário '$($usuario.Nome)' já existe."
    }
}
