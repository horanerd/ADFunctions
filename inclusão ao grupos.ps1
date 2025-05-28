# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Caminho das OUs (substitua com o DN correto)
$ouFinanceiro = "OU=Financeiro,DC=horanerd,DC=com,DC=br"
$ouRH = "OU=RH,DC=horanerd,DC=com,DC=br"

# Nome dos grupos
$grupoFinanceiro = "Financeiro"
$grupoRH = "RH"

# Função para adicionar usuários ao grupo
function AdicionarUsuariosAoGrupo {
    param (
        [string]$ou,
        [string]$grupo
    )

    # Obtém os usuários da OU especificada
    $usuarios = Get-ADUser -Filter * -SearchBase $ou

    # Adiciona cada usuário ao grupo
    foreach ($usuario in $usuarios) {
        # Adiciona o usuário ao grupo
        Add-ADGroupMember -Identity $grupo -Members $usuario.SamAccountName
        Write-Host "Usuário '$($usuario.SamAccountName)' adicionado ao grupo '$grupo'."
    }
}

# Adiciona os usuários da OU Financeiro ao grupo Financeiro
AdicionarUsuariosAoGrupo -ou $ouFinanceiro -grupo $grupoFinanceiro

# Adiciona os usuários da OU RH ao grupo RH
AdicionarUsuariosAoGrupo -ou $ouRH -grupo $grupoRH
