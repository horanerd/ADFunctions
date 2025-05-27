<#
.SYNOPSIS
    Busca informações de usuários no AD, incluindo status da conta e idade da senha (para usuário2 no modo arquivo,
    com validação de duplicidade), e compara o departamento principal entre pares ou grupos.

.DESCRIPTION
    Este script opera em dois modos para consultar o Active Directory.

    Modo Arquivo (-FilePath):
    Processa um arquivo TXT ("usuarioA,usuarioB" por linha). Valida se os usuários em um par são distintos.
    Para cada par válido:
    1. Busca informações de ambos, incluindo status da conta.
    2. Para o SEGUNDO usuário (usuario2):
        - Exibe há quanto tempo sua senha foi alterada, mas apenas na PRIMEIRA VEZ que este usuario2 aparece.
        - Em ocorrências subsequentes do MESMO usuario2 em outras linhas, um aviso é emitido.
    3. Compara os departamentos principais dos dois e informa o resultado.

    Modo Manual/Lista (-UserLogonName):
    Busca uma lista de usuários e apresenta um sumário final agrupando por departamento principal.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 27/05/2025
    # ... (outras notas)

.PARAMETER FilePath
    (Modo Arquivo) Caminho para um arquivo TXT com pares "usuario1,usuario2" por linha.

.PARAMETER UserLogonName
    (Modo Manual/Lista) Um ou mais nomes de logon.

.PARAMETER SearchBase
    Opcional. DN da OU para restringir a pesquisa.

.EXAMPLE
    # MODO ARQUIVO:
    # Supondo que C:\temp\pares.txt contenha:
    # jorge.s,ana.p
    # carlos.b,ana.p  <- ana.p é repetida como segundo usuário
    .\Compare-ADUserDeptsWithDupValidation.ps1 -FilePath "C:\temp\pares.txt"
    # (A info de pwdLastSet de ana.p será mostrada na primeira linha e um aviso na segunda)

.EXAMPLE
    # MODO MANUAL:
    .\Compare-ADUserDeptsWithDupValidation.ps1 -UserLogonName "userA", "userB", "userC"
#>
[CmdletBinding(DefaultParameterSetName = "ByLogonNames")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "ByLogonNames", ValueFromPipeline = $true,
               HelpMessage = "Um ou mais nomes de logon. A saída incluirá status da conta e um sumário agrupado por departamento principal.")]
    [string[]]$UserLogonName,

    [Parameter(Mandatory = $true, ParameterSetName = "ByFile",
               HelpMessage = "Caminho para um arquivo TXT contendo um par de nomes de logon (usuario1,usuario2) por linha.")]
    [string]$FilePath,

    [Parameter(Mandatory = $false, HelpMessage = "Opcional. DN da OU para restringir a pesquisa (aplicável a ambos os modos).")]
    [string]$SearchBase
)

# --- INÍCIO DA FUNÇÃO AUXILIAR ---
function Get-ProcessedUserInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogonNameInput,
        [Parameter(Mandatory = $false)]
        [string]$SearchBaseForUser
    )
    $trimmedLogonName = $LogonNameInput.Trim()
    $getUserParams = @{
        Identity   = $trimmedLogonName
        Properties = 'DisplayName', 'Department', 'SamAccountName', 'pwdLastSet', 'Enabled'
    }
    if (-not [string]::IsNullOrWhiteSpace($SearchBaseForUser)) {
        $getUserParams.SearchBase = $SearchBaseForUser
    }
    $userData = [PSCustomObject]@{
        InputProvided           = $LogonNameInput; SamAccountName = $null; DisplayName = $null
        AccountEnabledStatus    = "N/A"; FullDepartment = "N/A"; MainDepartment = "N/A"
        Found                   = $false; ErrorMessage = $null; PasswordLastSetDate = $null 
        PasswordLastSetDisplay  = "N/A"; PasswordAgeDisplay = "N/A" 
    }
    try {
        $adUser = Get-ADUser @getUserParams
        if ($adUser) {
            $userData.SamAccountName = $adUser.SamAccountName; $userData.DisplayName = $adUser.DisplayName
            $userData.Found = $true; $userData.AccountEnabledStatus = if ($adUser.Enabled) { "Ativada" } else { "Desativada" }
            $fullDepartmentFromAD = $adUser.Department
            if ([string]::IsNullOrWhiteSpace($fullDepartmentFromAD)) {
                $userData.FullDepartment = "Não especificado"; $userData.MainDepartment = "Não especificado" 
            } else {
                $userData.FullDepartment = $fullDepartmentFromAD
                $userData.MainDepartment = ($fullDepartmentFromAD.Split(' ', 2)[0])
            }
            if ($adUser.pwdLastSet -eq 0) {
                $userData.PasswordLastSetDisplay = "Usuário deve alterar senha no próximo logon"
            } elseif ($adUser.pwdLastSet -gt 0) { 
                try {
                    $pwdSetDateTimeUtc = [datetime]::FromFileTimeUtc($adUser.pwdLastSet)
                    $userData.PasswordLastSetDate = $pwdSetDateTimeUtc
                    $userData.PasswordLastSetDisplay = $pwdSetDateTimeUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm:ss")
                    $age = (Get-Date).ToUniversalTime() - $pwdSetDateTimeUtc
                    $userData.PasswordAgeDisplay = if ($age.TotalDays -ge 0) { "$($age.Days) dia(s) atrás" } else { "Data no futuro?" }
                } catch {
                    $userData.PasswordLastSetDisplay = "Data de senha inválida (valor bruto: $($adUser.pwdLastSet))"
                    $userData.PasswordAgeDisplay = "Erro na conversão"
                }
            } else { 
                $userData.PasswordLastSetDisplay = "Senha não definida para expirar ou config. especial (valor bruto: $($adUser.pwdLastSet))"
            }
        }
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $userData.ErrorMessage = "Usuário '$trimmedLogonName' não encontrado."
    } catch {
        $userData.ErrorMessage = "Erro ao buscar '$trimmedLogonName': $($_.Exception.Message)"
    }
    return $userData
}
# --- FIM DA FUNÇÃO AUXILIAR ---

if (-not (Get-Module ActiveDirectory)) {
    try { Import-Module ActiveDirectory -ErrorAction Stop; Write-Host "Módulo ActiveDirectory importado." -FG Green }
    catch { Write-Error "Falha ao importar módulo ActiveDirectory."; exit 1 }
}

$overallFoundUsersInfo = @{} 
$secondUserPwdAlreadyDisplayed = @{} # NOVO: Hashtable para rastrear exibição de pwdLastSet para usuário2

if ($PSCmdlet.ParameterSetName -eq "ByFile") {
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Error "Arquivo não encontrado: '$FilePath'."
        exit 1
    }
    Write-Host "MODO ARQUIVO: Processando '$FilePath'" -FG Cyan
    $linesFromFile = Get-Content -Path $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($linesFromFile.Count -eq 0) {
        Write-Warning "Arquivo '$FilePath' vazio ou sem linhas válidas."; exit 1
    }
    Write-Host "Total de pares (linhas) a processar: $($linesFromFile.Count)"

    foreach ($line in $linesFromFile) {
        Write-Host "`n=================================================="
        Write-Host "Processando linha: '$line'" -FG Yellow
        $userPairStrings = $line.Split(',')
        if ($userPairStrings.Count -ne 2) {
            Write-Warning "Linha '$line' formato inválido. Pulando."; continue
        }
        $userInput1 = $userPairStrings[0].Trim()
        $userInput2 = $userPairStrings[1].Trim()
        if ([string]::IsNullOrWhiteSpace($userInput1) -or [string]::IsNullOrWhiteSpace($userInput2)) {
            Write-Warning "Linha '$line' nome de usuário vazio. Pulando."; continue
        }
        if ($userInput1 -eq $userInput2) {
            Write-Error -Message "ENTRADA INCORRETA NA LINHA: '$line'. Os dois identificadores são idênticos ('$userInput1'). Pulando par."
            continue 
        }
        Write-Host "Par a comparar: [$userInput1] e [$userInput2]"

        Write-Host "  Buscando usuário 1: '$userInput1'..." -FG DarkGray
        $userInfo1 = Get-ProcessedUserInfo -LogonNameInput $userInput1 -SearchBaseForUser $SearchBase
        if ($userInfo1.Found) {
            Write-Host "    -> Encontrado: $($userInfo1.SamAccountName) (Status: $($userInfo1.AccountEnabledStatus)), Depto Principal: $($userInfo1.MainDepartment) (Completo: '$($userInfo1.FullDepartment)')" -FG DarkCyan
            if (-not $overallFoundUsersInfo.ContainsKey($userInfo1.SamAccountName)) { $overallFoundUsersInfo[$userInfo1.SamAccountName] = $userInfo1 }
        } else { Write-Warning $userInfo1.ErrorMessage }
        
        Write-Host "  Buscando usuário 2: '$userInput2'..." -FG DarkGray
        $userInfo2 = Get-ProcessedUserInfo -LogonNameInput $userInput2 -SearchBaseForUser $SearchBase
        if ($userInfo2.Found) {
            Write-Host "    -> Encontrado: $($userInfo2.SamAccountName) (Status: $($userInfo2.AccountEnabledStatus)), Depto Principal: $($userInfo2.MainDepartment) (Completo: '$($userInfo2.FullDepartment)')" -FG DarkCyan
            
            # --- Validação de duplicidade para exibição de pwdLastSet do usuário2 ---
            if ($secondUserPwdAlreadyDisplayed.ContainsKey($userInfo2.SamAccountName)) {
                Write-Warning "Aviso: Informação de última alteração de senha para '$($userInfo2.SamAccountName)' (como segundo usuário do par) já foi exibida anteriormente."
                Write-Host "       (Info PwdLastSet para $($userInfo2.SamAccountName): Reutilizada/Já exibida)" -ForegroundColor Gray
            } else {
                Write-Host "       Última alteração de senha (para $($userInfo2.SamAccountName)): $($userInfo2.PasswordLastSetDisplay) - $($userInfo2.PasswordAgeDisplay)" -ForegroundColor Blue 
                $secondUserPwdAlreadyDisplayed[$userInfo2.SamAccountName] = $true # Marca como exibido
            }
            # --- Fim da validação de duplicidade ---

            if (-not $overallFoundUsersInfo.ContainsKey($userInfo2.SamAccountName)) { $overallFoundUsersInfo[$userInfo2.SamAccountName] = $userInfo2 }
        } else { Write-Warning $userInfo2.ErrorMessage }

        if ($userInfo1.Found -and $userInfo2.Found) {
            $comparisonMessage = ""; $comparisonColor = "White"
            if ($userInfo1.MainDepartment -eq $userInfo2.MainDepartment) {
                $comparisonMessage = "PERTENCEM ao MESMO departamento principal ('$($userInfo1.MainDepartment)')"; $comparisonColor = "Green"
            } else {
                $comparisonMessage = "NÃO PERTENCEM ao mesmo departamento principal ('$($userInfo1.MainDepartment)' vs '$($userInfo2.MainDepartment)')"; $comparisonColor = "Red"
            }
            Write-Host "  RESULTADO PARA O PAR: $comparisonMessage" -FG $comparisonColor
        } else {
            Write-Warning "Comparação não realizada para o par da linha '$line' (um ou ambos não encontrados)."
        }
    }
    Write-Host "`n=================================================="
    Write-Host "Processamento do arquivo de pares concluído." -FG Green

}
elseif ($PSCmdlet.ParameterSetName -eq "ByLogonNames") {
    $logonNamesToProcess = $UserLogonName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($logonNamesToProcess.Count -eq 0) { Write-Warning "Nenhum nome de usuário válido fornecido."; exit 1 }
    
    Write-Host "MODO MANUAL/LISTA: Coletando informações dos usuários..." -FG Cyan
    foreach ($logonNameInput in $logonNamesToProcess) {
        Write-Host "`n--------------------------------------------------"
        Write-Host "Processando entrada: '$logonNameInput'" -FG Yellow
        if ($PSBoundParameters.ContainsKey('SearchBase')) { Write-Host "Pesquisando na OU: $SearchBase..." -FG Cyan }
        
        Write-Host "  Buscando detalhes para: '$($logonNameInput.Trim())'..." -FG DarkGray
        $userInfo = Get-ProcessedUserInfo -LogonNameInput $logonNameInput -SearchBaseForUser $SearchBase
        
        if ($userInfo.Found) {
            Write-Host "    -> Usuário Encontrado: $($userInfo.SamAccountName)" -FG DarkCyan
            Write-Host "       Nome de Exibição   : $($userInfo.DisplayName)"
            Write-Host "       Status da Conta    : $($userInfo.AccountEnabledStatus)" 
            Write-Host "       Departamento Compl.: $($userInfo.FullDepartment)"
            Write-Host "       Depto. Principal   : $($userInfo.MainDepartment)"
            Write-Host "       Última Alt. Senha  : $($userInfo.PasswordLastSetDisplay) ($($userInfo.PasswordAgeDisplay))" 
            if (-not $overallFoundUsersInfo.ContainsKey($userInfo.SamAccountName)) { $overallFoundUsersInfo[$userInfo.SamAccountName] = $userInfo }
        } else {
            Write-Warning $userInfo.ErrorMessage
        }
    }
    Write-Host "`n--------------------------------------------------"
    Write-Host "Coleta de informações individuais concluída." -FG Green
}

# --- SUMÁRIO FINAL DE DEPARTAMENTOS ---
Write-Host "`n=================================================="
Write-Host "SUMÁRIO DE DEPARTAMENTOS PRINCIPAIS DOS USUÁRIOS ENCONTRADOS" -ForegroundColor Magenta
if ($overallFoundUsersInfo.Count -eq 0) {
    Write-Host "Nenhum usuário foi encontrado com sucesso para resumir." -ForegroundColor Yellow
} else {
    $departmentsGrouped = $overallFoundUsersInfo.Values | Group-Object -Property MainDepartment
    Write-Host "Total de usuários únicos encontrados e processados: $($overallFoundUsersInfo.Count)"
    Write-Host "Distribuição por Departamento Principal:" -FG Cyan
    foreach ($group in $departmentsGrouped) {
        $departmentName = $group.Name
        $usersInGroupObjects = $group.Group
        $userDisplayList = @()
        foreach($usrObj in $usersInGroupObjects){
            $userDisplayList += "$($usrObj.SamAccountName) ($($usrObj.AccountEnabledStatus))" 
        }
        $usersDisplay = $userDisplayList -join ", "
        if ($usersInGroupObjects.Count -gt 1) {
            Write-Host "  Departamento Principal: '$departmentName'" -ForegroundColor Green
            Write-Host "    Usuários ($($usersInGroupObjects.Count)): $usersDisplay"
            Write-Host "    (Estes usuários compartilham o mesmo departamento principal entre si)" -FG DarkGreen
        } else {
            Write-Host "  Departamento Principal: '$departmentName'" -ForegroundColor Cyan
            Write-Host "    Usuário ($($usersInGroupObjects.Count)): $usersDisplay"
            Write-Host "    (Este usuário é o único encontrado neste departamento principal na lista processada)" -FG DarkCyan
        }
    }
    Write-Host "`nEste sumário indica quais usuários compartilham o mesmo departamento principal."
    Write-Host "Usuários em grupos diferentes NÃO compartilham o mesmo departamento principal."
}
Write-Host "=================================================="
Write-Host "Script concluído."
