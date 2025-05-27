<#
.SYNOPSIS
    Busca informações de usuários no AD e compara seus departamentos principais.
    Opera em dois modos:
    1. Comparando pares específicos de um arquivo TXT.
    2. Comparando todos os pares possíveis de uma lista de usuários fornecida manualmente.

.DESCRIPTION
    Este script consulta o Active Directory para encontrar usuários e comparar seus "departamentos principais"
    (a primeira parte do nome do departamento).

    Modo Arquivo (-FilePath):
    Processa um arquivo TXT onde cada linha deve conter dois nomes de logon de usuário,
    separados por vírgula (ex: "usuarioA,usuarioB"). Para cada par lido do arquivo,
    busca as informações de ambos e compara seus departamentos principais.

    Modo Manual (-UserLogonName):
    Recebe uma lista de um ou mais nomes de logon. Busca as informações de todos os usuários
    fornecidos e, em seguida, realiza uma comparação individual entre cada par único possível
    formado a partir dessa lista, verificando se pertencem ao mesmo departamento principal.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 26/05/2025
    Requerimentos:
        - Módulo Active Directory para PowerShell (RSAT-AD-PowerShell).
        - Permissões para ler objetos de usuário no AD.
    Formato do Arquivo TXT (para -FilePath):
        usuario1_linha1,usuario2_linha1
        usuarioA_linha2,usuarioB_linha2

.PARAMETER FilePath
    (Modo Arquivo) Caminho para um arquivo TXT contendo um par de nomes de logon por linha, separados por vírgula.

.PARAMETER UserLogonName
    (Modo Manual) Um ou mais nomes de logon para realizar comparação de todos os pares possíveis (N x N). Separe por vírgula.

.PARAMETER SearchBase
    Opcional. DN da OU para restringir a pesquisa de todos os usuários (aplicável a ambos os modos).

.EXAMPLE
    # MODO ARQUIVO: Compara pares definidos no arquivo
    # Supondo que C:\temp\pares.txt contenha: "jorge.s,ana.p" e "maria.c,luis.o"
    .\Compare-ADUserDeptsAdvanced.ps1 -FilePath "C:\temp\pares.txt"

.EXAMPLE
    # MODO MANUAL: Compara todos os pares da lista fornecida
    .\Compare-ADUserDeptsAdvanced.ps1 -UserLogonName "userA", "userB", "userC"
    # (Compara A-B, A-C, B-C)

.EXAMPLE
    # MODO MANUAL com SearchBase
    .\Compare-ADUserDeptsAdvanced.ps1 -UserLogonName "userX", "userY" -SearchBase "OU=TI,DC=empresa,DC=com"
#>
[CmdletBinding(DefaultParameterSetName = "ByLogonNames")] # Define o modo manual como padrão se nenhum parâmetro obrigatório de conjunto for usado
param(
    [Parameter(Mandatory = $true,
               ParameterSetName = "ByLogonNames",
               ValueFromPipeline = $true,
               HelpMessage = "Um ou mais nomes de logon para realizar comparação de todos os pares possíveis (N x N). Separe múltiplos nomes por vírgula.")]
    [string[]]$UserLogonName,

    [Parameter(Mandatory = $true,
               ParameterSetName = "ByFile",
               HelpMessage = "Caminho para um arquivo TXT contendo um par de nomes de logon (usuario1,usuario2) por linha para comparação direta.")]
    [string]$FilePath,

    [Parameter(Mandatory = $false, 
               HelpMessage = "Opcional. DN da OU para restringir a pesquisa de todos os usuários (aplicável a ambos os modos).")]
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
    # Removido o Write-Host daqui para não poluir a saída ao buscar múltiplos usuários para a lista NxN
    # Ele será chamado explicitamente no modo ByFile ou antes da comparação NxN

    $getUserParams = @{
        Identity   = $trimmedLogonName
        Properties = 'DisplayName', 'Department', 'SamAccountName'
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchBaseForUser)) {
        $getUserParams.SearchBase = $SearchBaseForUser
    }

    $userData = [PSCustomObject]@{
        InputProvided   = $LogonNameInput
        SamAccountName  = $null
        DisplayName     = $null
        FullDepartment  = "N/A"
        MainDepartment  = "N/A"
        Found           = $false
        ErrorMessage    = $null
    }

    try {
        $adUser = Get-ADUser @getUserParams
        if ($adUser) {
            $userData.SamAccountName = $adUser.SamAccountName
            $userData.DisplayName    = $adUser.DisplayName
            $userData.Found          = $true

            $fullDepartmentFromAD = $adUser.Department
            if ([string]::IsNullOrWhiteSpace($fullDepartmentFromAD)) {
                $userData.FullDepartment = "Não especificado"
                $userData.MainDepartment = "Não especificado" 
            } else {
                $userData.FullDepartment = $fullDepartmentFromAD
                $userData.MainDepartment = ($fullDepartmentFromAD.Split(' ', 2)[0])
            }
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $userData.ErrorMessage = "Usuário '$trimmedLogonName' não encontrado."
    }
    catch {
        $userData.ErrorMessage = "Erro ao buscar '$trimmedLogonName': $($_.Exception.Message)"
    }
    return $userData
}
# --- FIM DA FUNÇÃO AUXILIAR ---

# Importar o módulo do Active Directory
if (-not (Get-Module ActiveDirectory)) {
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "Módulo ActiveDirectory importado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Error "Falha ao importar o módulo ActiveDirectory. RSAT para AD DS deve estar instalado."
        exit 1
    }
}

# Lógica principal baseada no conjunto de parâmetros
if ($PSCmdlet.ParameterSetName -eq "ByFile") {
    # MODO ARQUIVO: Processar pares de um arquivo TXT
    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Error "Arquivo de entrada não encontrado em '$FilePath'."
        exit 1
    }

    Write-Host "MODO ARQUIVO: Processando arquivo de pares: '$FilePath'" -ForegroundColor Cyan
    $linesFromFile = Get-Content -Path $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($linesFromFile.Count -eq 0) {
        Write-Warning "O arquivo '$FilePath' está vazio ou não contém linhas válidas para processamento."
        exit 1
    }
    Write-Host "Total de pares (linhas) a processar: $($linesFromFile.Count)"

    foreach ($line in $linesFromFile) {
        Write-Host "`n=================================================="
        Write-Host "Processando linha do arquivo: '$line'" -ForegroundColor Yellow

        $userPairStrings = $line.Split(',')
        if ($userPairStrings.Count -ne 2) {
            Write-Warning "Linha '$line' não está no formato esperado 'usuario1,usuario2'. Pulando esta linha."
            continue
        }

        $userInput1 = $userPairStrings[0].Trim()
        $userInput2 = $userPairStrings[1].Trim()

        if ([string]::IsNullOrWhiteSpace($userInput1) -or [string]::IsNullOrWhiteSpace($userInput2)) {
            Write-Warning "Linha '$line' contém um nome de usuário vazio. Pulando esta linha."
            continue
        }
        Write-Host "Par a comparar: [$userInput1] e [$userInput2]"

        $userInfo1 = Get-ProcessedUserInfo -LogonNameInput $userInput1 -SearchBaseForUser $SearchBase
        if (-not $userInfo1.Found) { Write-Warning $userInfo1.ErrorMessage } else {
             Write-Host "  Detalhes Usuário 1 ($($userInput1)): $($userInfo1.SamAccountName), Depto Principal '$($userInfo1.MainDepartment)' (Completo: '$($userInfo1.FullDepartment)')"
        }
        
        $userInfo2 = Get-ProcessedUserInfo -LogonNameInput $userInput2 -SearchBaseForUser $SearchBase
        if (-not $userInfo2.Found) { Write-Warning $userInfo2.ErrorMessage } else {
            Write-Host "  Detalhes Usuário 2 ($($userInput2)): $($userInfo2.SamAccountName), Depto Principal '$($userInfo2.MainDepartment)' (Completo: '$($userInfo2.FullDepartment)')"
        }

        if ($userInfo1.Found -and $userInfo2.Found) {
            $comparisonMessage = ""
            $comparisonColor = "White"
            if ($userInfo1.MainDepartment -eq $userInfo2.MainDepartment) {
                $comparisonMessage = "PERTENCEM ao MESMO departamento principal ('$($userInfo1.MainDepartment)')"
                $comparisonColor = "Green"
            } else {
                $comparisonMessage = "NÃO PERTENCEM ao mesmo departamento principal ('$($userInfo1.MainDepartment)' vs '$($userInfo2.MainDepartment)')"
                $comparisonColor = "Red"
            }
            Write-Host "  RESULTADO PARA O PAR: $comparisonMessage" -ForegroundColor $comparisonColor
        } else {
            Write-Warning "Não foi possível realizar a comparação para o par da linha '$line', pois um ou ambos os usuários não foram encontrados/processados corretamente."
        }
    }
    Write-Host "`n=================================================="
    Write-Host "Processamento do arquivo de pares concluído." -ForegroundColor Green

}
elseif ($PSCmdlet.ParameterSetName -eq "ByLogonNames") {
    # MODO MANUAL: Processar lista de usuários e comparar todos os pares (N x N)
    $logonNamesToProcess = $UserLogonName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($logonNamesToProcess.Count -eq 0) {
        Write-Warning "Nenhum nome de usuário válido fornecido para processamento."
        exit 1
    }
    
    Write-Host "MODO MANUAL: Coletando informações dos usuários fornecidos..." -ForegroundColor Cyan
    $foundUsersListForPairwise = @()
    foreach ($logonNameInput in $logonNamesToProcess) {
        Write-Host "`n--------------------------------------------------"
        Write-Host "Processando entrada: '$logonNameInput'" -ForegroundColor Yellow
         if ($PSBoundParameters.ContainsKey('SearchBase')) {
            Write-Host "Pesquisando na OU: $SearchBase..." -ForegroundColor Cyan
        }
        $userInfo = Get-ProcessedUserInfo -LogonNameInput $logonNameInput -SearchBaseForUser $SearchBase
        
        if ($userInfo.Found) {
            Write-Host "  -> Usuário Encontrado: $($userInfo.SamAccountName)"
            Write-Host "     Nome de Exibição   : $($userInfo.DisplayName)"
            Write-Host "     Departamento Compl.: $($userInfo.FullDepartment)"
            Write-Host "     Depto. Principal   : $($userInfo.MainDepartment)"
            $foundUsersListForPairwise += $userInfo
        } else {
            Write-Warning $userInfo.ErrorMessage # Exibe o erro já formatado pela função
        }
    }
    Write-Host "`n--------------------------------------------------"
    Write-Host "Coleta de informações individuais concluída." -ForegroundColor Green

    Write-Host "`n--- COMPARAÇÃO DE DEPARTAMENTO PRINCIPAL (ENTRE TODOS OS PARES DE USUÁRIOS ENCONTRADOS) ---" -ForegroundColor Cyan
    if ($foundUsersListForPairwise.Count -lt 2) {
        Write-Host "São necessários pelo menos dois usuários encontrados para realizar comparações entre pares." -ForegroundColor Yellow
    } else {
        Write-Host "Analisando os seguintes usuários encontrados (Nome de Logon e Depto. Principal para comparação):"
        $foundUsersListForPairwise | ForEach-Object { Write-Host "  - $($_.SamAccountName) ('$($_.MainDepartment)')" }
        Write-Host ""

        for ($i = 0; $i -lt ($foundUsersListForPairwise.Count - 1); $i++) {
            for ($j = $i + 1; $j -lt $foundUsersListForPairwise.Count; $j++) {
                $user1 = $foundUsersListForPairwise[$i]
                $user2 = $foundUsersListForPairwise[$j]

                $comparisonMessage = ""
                $comparisonColor = "White"
                if ($user1.MainDepartment -eq $user2.MainDepartment) {
                    $comparisonMessage = "PERTENCEM ao MESMO departamento principal ('$($user1.MainDepartment)')"
                    $comparisonColor = "Green"
                } else {
                    $comparisonMessage = "NÃO PERTENCEM ao mesmo departamento principal ('$($user1.MainDepartment)' vs '$($user2.MainDepartment)')"
                    $comparisonColor = "Red"
                }
                Write-Host "Comparando: [$($user1.SamAccountName)] e [$($user2.SamAccountName)] -> $comparisonMessage" -ForegroundColor $comparisonColor
            }
        }
    }
    Write-Host "`n--------------------------------------------------"
    Write-Host "Validação entre todos os pares (N x N) concluída." -ForegroundColor Green
}
