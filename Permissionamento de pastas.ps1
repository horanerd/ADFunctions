# Caminho das pastas
$financeiroPath = "C:\Arquivos\Financeiro"
$rhPath = "C:\Arquivos\RH"

# Nome dos grupos que foram criados
$grupoFinanceiro = "Financeiro"
$grupoRH = "RH"

# Atribui permissões para o grupo Financeiro na pasta "C:\Arquivos\Financeiro"
if (Test-Path $financeiroPath) {
    $aclFinanceiro = Get-Acl $financeiroPath
    $accessRuleFinanceiro = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$grupoFinanceiro", 
        "Modify", 
        "ContainerInherit,ObjectInherit", 
        "None", 
        "Allow"
    )
    $aclFinanceiro.AddAccessRule($accessRuleFinanceiro)
    Set-Acl -Path $financeiroPath -AclObject $aclFinanceiro
    Write-Host "Permissões 'Modify' atribuídas ao grupo '$grupoFinanceiro' na pasta '$financeiroPath'."
} else {
    Write-Host "A pasta '$financeiroPath' não existe."
}

# Atribui permissões para o grupo RH na pasta "C:\Arquivos\RH"
if (Test-Path $rhPath) {
    $aclRH = Get-Acl $rhPath
    $accessRuleRH = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$grupoRH", 
        "Modify", 
        "ContainerInherit,ObjectInherit", 
        "None", 
        "Allow"
    )
    $aclRH.AddAccessRule($accessRuleRH)
    Set-Acl -Path $rhPath -AclObject $aclRH
    Write-Host "Permissões 'Modify' atribuídas ao grupo '$grupoRH' na pasta '$rhPath'."
} else {
    Write-Host "A pasta '$rhPath' não existe."
}
