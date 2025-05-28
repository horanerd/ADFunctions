# Script para criar a OU "Desligados" no Active Directory

# Define o nome do domínio
$DomainDN = "DC=horanerd,DC=com,DC=br"

# Define o nome da OU a ser criada
$OuName = "Desligados"

# Define o caminho completo (Distinguished Name) da nova OU
$OuDN = "OU=$OuName,$DomainDN"

# Verifica se a OU já existe
if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$OuDN'" -ErrorAction SilentlyContinue) {
    Write-Host "A OU '$OuName' já existe em '$DomainDN'." -ForegroundColor Yellow
}
else {
    try {
        # Tenta criar a nova OU
        New-ADOrganizationalUnit -Name $OuName -Path $DomainDN -ProtectedFromAccidentalDeletion $true -PassThru
        Write-Host "A OU '$OuName' foi criada com sucesso em '$DomainDN'." -ForegroundColor Green
    }
    catch {
        Write-Host "Ocorreu um erro ao tentar criar a OU '$OuName': $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Opcional: Se você quiser que a OU seja criada dentro de outra OU existente,
# ajuste a variável $DomainDN ou adicione um $ParentOuDN.
# Exemplo para criar dentro de uma OU "Usuarios":
# $ParentOuDN = "OU=Usuarios,DC=horanerd,DC=com,DC=br"
# $OuDN = "OU=$OuName,$ParentOuDN"
#