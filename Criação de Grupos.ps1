# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Nome dos grupos
$grupoFinanceiro = "Financeiro"
$grupoRH = "RH"

# Caminho das OUs onde os grupos serão criados
$ouFinanceiro = "OU=Financeiro,DC=horanerd,DC=com,DC=br"  # Substitua pelo DN correto da sua OU Financeiro
$ouRH = "OU=RH,DC=horanerd,DC=com,DC=br"  # Substitua pelo DN correto da sua OU RH

# Cria o grupo "Financeiro" dentro da OU "Financeiro", se não existir
if (-not (Get-ADGroup -Filter "Name -eq '$grupoFinanceiro'" -SearchBase $ouFinanceiro -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name $grupoFinanceiro -SamAccountName $grupoFinanceiro -GroupCategory Security -GroupScope Global -Path $ouFinanceiro -Description "Grupo de acesso à pasta Financeiro"
    Write-Host "Grupo '$grupoFinanceiro' criado com sucesso na OU 'Financeiro'."
} else {
    Write-Host "O grupo '$grupoFinanceiro' já existe na OU 'Financeiro'."
}

# Cria o grupo "RH" dentro da OU "RH", se não existir
if (-not (Get-ADGroup -Filter "Name -eq '$grupoRH'" -SearchBase $ouRH -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name $grupoRH -SamAccountName $grupoRH -GroupCategory Security -GroupScope Global -Path $ouRH -Description "Grupo de acesso à pasta RH"
    Write-Host "Grupo '$grupoRH' criado com sucesso na OU 'RH'."
} else {
    Write-Host "O grupo '$grupoRH' já existe na OU 'RH'."
}
