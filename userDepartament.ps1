<#
.SYNOPSIS
    Lê pares de usuários de um arquivo TXT, busca suas informações no AD
    e compara o departamento principal para cada par individualmente.

.DESCRIPTION
    Este script processa um arquivo TXT onde cada linha deve conter dois nomes de logon de usuário,
    separados por vírgula (ex: "usuarioA,usuarioB"). Para cada par lido do arquivo:
    1. Busca as informações de ambos os usuários no Active Directory.
    2. Determina o "departamento principal" de cada um (primeira parte do nome do departamento).
    3. Compara os departamentos principais e informa se são iguais ou diferentes para aquele par específico.

.NOTES
    Autor: Seu Nome/Empresa
    Data: 26/05/2025
    Requerimentos:
        - Módulo Active Directory para PowerShell (RSAT-AD-PowerShell).
        - Permissões para ler objetos de usuário no AD.
    Formato do Arquivo TXT:
        usuario1_linha1,usuario2_linha1
        usuarioA_linha2,usuarioB_linha2
        # ... e assim por diante

.PARAMETER FilePath
    Caminho para um arquivo TXT contendo um par de nomes de logon de usuário por linha,
    separados por vírgula. Obrigatório.

.PARAMETER SearchBase
    Opcional. DN da OU para restringir a pesquisa de todos os usuários mencionados no arquivo.

.EXAMPLE
    # Supondo que o arquivo C:\temp\pares_usuarios.txt contenha:
    # josedasilva,anapereira
    # ricardo.alves@empresa.com,maria.souza
    .\Compare-ADUserPairDepartmentsFromFile.ps1 -FilePath "C:\temp\pares_usuarios.txt"

.EXAMPLE
    .\Compare-ADUserPairDepartmentsFromFile.ps1 -FilePath "C:\temp\pares.txt" -SearchBase "OU=Funcionarios,DC=empresa,DC=com"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true,
               HelpMessage = "Caminho para um arquivo TXT contendo um par de nomes de logon de usuário por linha, separados por vírgula.")]
    [string]$FilePath,

    [Parameter(Mandatory = $false, HelpMessage = "Opcional. DN da OU para restringir a pesquisa para todos os usuários.")]
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
    Write-Host "  Buscando detalhes para: '$trimmedLogonName'..." -ForegroundColor DarkGray

    $getUserParams = @{
        Identity   = $trimmedLogonName
        Properties = 'DisplayName', 'Department', 'SamAccountName'
    }

    if (-not [string]::IsNullOrWhiteSpace($SearchBaseForUser)) {
        $getUserParams.SearchBase = $SearchBaseForUser
    }

    # Objeto para armazenar os dados do usuário processado
    $userData = [PSCustomObject]@{
        InputProvided   = $LogonNameInput # Mantém a entrada original
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
            Write-Host "    -> Encontrado: $($adUser.SamAccountName), Depto Principal: $($userData.MainDepartment) (Completo: $($userData.FullDepartment))" -ForegroundColor DarkCyan
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $userData.ErrorMessage = "Usuário '$trimmedLogonName' não encontrado."
        Write-Warning $userData.ErrorMessage
    }
    catch {
        $userData.ErrorMessage = "Erro ao buscar '$trimmedLogonName': $($_.Exception.Message)"
        Write-Warning $userData.ErrorMessage
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

# Validar se o arquivo de entrada existe
if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    Write-Error "Arquivo de entrada não encontrado em '$FilePath'."
    exit 1
}

Write-Host "Processando arquivo de pares: '$FilePath'" -ForegroundColor Cyan
$linesFromFile = Get-Content -Path $FilePath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($linesFromFile.Count -eq 0) {
    Write-Warning "O arquivo '$FilePath' está vazio ou não contém linhas válidas para processamento."
    exit 1
}

Write-Host "Total de pares (linhas) a processar: $($linesFromFile.Count)"

# Loop para processar cada linha (par) do arquivo
foreach ($line in $linesFromFile) {
    Write-Host "`n=================================================="
    Write-Host "Processando linha do arquivo: '$line'" -ForegroundColor Yellow

    $userPairStrings = $line.Split(',')
    if ($userPairStrings.Count -ne 2) {
        Write-Warning "Linha '$line' não está no formato esperado 'usuario1,usuario2'. Pulando esta linha."
        continue # Pula para a próxima linha
    }

    $userInput1 = $userPairStrings[0].Trim()
    $userInput2 = $userPairStrings[1].Trim()

    if ([string]::IsNullOrWhiteSpace($userInput1) -or [string]::IsNullOrWhiteSpace($userInput2)) {
        Write-Warning "Linha '$line' contém um nome de usuário vazio após o split e trim. Pulando esta linha."
        continue
    }

    Write-Host "Par a comparar: [$userInput1] e [$userInput2]"

    # Obter informações do primeiro usuário do par
    $userInfo1 = Get-ProcessedUserInfo -LogonNameInput $userInput1 -SearchBaseForUser $SearchBase
    
    # Obter informações do segundo usuário do par
    $userInfo2 = Get-ProcessedUserInfo -LogonNameInput $userInput2 -SearchBaseForUser $SearchBase

    # Realizar a comparação se ambos os usuários foram encontrados
    if ($userInfo1.Found -and $userInfo2.Found) {
        $comparisonMessage = ""
        $comparisonColor = "White"

        Write-Host "  Comparando Departamentos Principais:"
        Write-Host "    - $($userInfo1.SamAccountName) ('$($userInfo1.MainDepartment)')"
        Write-Host "    - $($userInfo2.SamAccountName) ('$($userInfo2.MainDepartment)')"

        if ($userInfo1.MainDepartment -eq $userInfo2.MainDepartment) {
            $comparisonMessage = "PERTENCEM ao MESMO departamento principal ('$($userInfo1.MainDepartment)')"
            $comparisonColor = "Green"
        } else {
            $comparisonMessage = "NÃO PERTENCEM ao mesmo departamento principal ('$($userInfo1.MainDepartment)' vs '$($userInfo2.MainDepartment)')"
            $comparisonColor = "Red"
        }
        Write-Host "  RESULTADO PARA O PAR: $comparisonMessage" -ForegroundColor $comparisonColor
    } else {
        Write-Warning "Não foi possível realizar a comparação para o par da linha '$line', pois um ou ambos os usuários não foram encontrados ou houve erro."
    }
}

Write-Host "`n=================================================="
Write-Host "Processamento do arquivo de pares concluído." -ForegroundColor Green
