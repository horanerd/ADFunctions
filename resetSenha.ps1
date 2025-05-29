# --- Configurações Iniciais ---
# Caracteres para a senha
$maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$minusculas = "abcdefghijklmnopqrstuvwxyz"
$especiais = "@!#$?%^&*" # Garanta que os caracteres especiais atendam à política do seu domínio.
$numeros = "0123456789"
$todosCaracteres = $maiusculas + $minusculas + $especiais + $numeros

# Tamanho da senha (ajuste conforme a política do seu domínio, mínimo comum é 8-12)
$TamanhoSenha = 12

# (OPCIONAL) Especifique um Controlador de Domínio para direcionar todas as operações AD.
# Deixe em branco ou $null para permitir que os cmdlets escolham automaticamente.
# Exemplo: $targetDC = "meudc01.meudominio.com"
$targetDC = $null 

# --- Função para Gerar Senha ---
function Gerar-NovaSenha {
    param (
        [int]$Comprimento = $TamanhoSenha
    )
    if ($Comprimento -lt 4) {
        Write-Warning "O comprimento da senha ($Comprimento) é muito curto. Recomenda-se no mínimo 4 para incluir todos os tipos de caracteres, idealmente $TamanhoSenha ou mais."
        $poolSimples = $todosCaracteres
        $senhaCurta = -join ((0..($Comprimento-1)) | ForEach-Object { $poolSimples[(Get-Random $poolSimples.Length)] })
        return $senhaCurta
    }
    $arraySenha = @()
    $arraySenha += $maiusculas[(Get-Random -Maximum $maiusculas.Length)]
    $arraySenha += $minusculas[(Get-Random -Maximum $minusculas.Length)]
    $arraySenha += $especiais[(Get-Random -Maximum $especiais.Length)]
    $arraySenha += $numeros[(Get-Random -Maximum $numeros.Length)]
    $restante = $Comprimento - $arraySenha.Length
    for ($i = 0; $i -lt $restante; $i++) {
        $arraySenha += $todosCaracteres[(Get-Random -Maximum $todosCaracteres.Length)]
    }
    $senhaFinal = ($arraySenha | Get-Random -Count $arraySenha.Length) -join ''
    return $senhaFinal
}

# --- Verificação do Módulo Active Directory ---
Write-Host "Verificando o módulo Active Directory..." -ForegroundColor Cyan
if (-not (Get-Module ActiveDirectory -ListAvailable)) {
    Write-Error "MÓDULO ACTIVE DIRECTORY NÃO ENCONTRADO. Verifique a instalação do RSAT."
    exit 1
}
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Módulo Active Directory importado com sucesso." -ForegroundColor Green
}
catch {
    Write-Error "Falha ao importar o módulo Active Directory: $($_.Exception.Message)"
    exit 1
}

# --- Configuração do Log ---
$logFile = ".\LogResetSenhaUsuarios_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Function Write-Log {
    param (
        [string]$Message,
        [System.ConsoleColor]$ConsoleForegroundColor
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "$timestamp - $Message"
    
    # Adiciona ao arquivo de log primeiro (sempre)
    Add-Content -Path $logFile -Value $logEntry

    # Tenta escrever no console com cor
    if ($PSBoundParameters.ContainsKey('ConsoleForegroundColor')) {
        try {
            Write-Host $logEntry -ForegroundColor $ConsoleForegroundColor
        }
        catch {
            $colorErrorMessage = $_.Exception.Message
            Write-Warning "$timestamp - AVISO CONSOLE: Falha ao definir a cor '$($ConsoleForegroundColor)'. Erro: $colorErrorMessage. Exibindo com cor padrão."
            Write-Host $logEntry # Fallback para cor padrão do console
        }
    }
    else {
        Write-Host $logEntry # Escreve com cor padrão do console se nenhuma cor for especificada
    }
}

# --- Obter Caminho do Arquivo de Usuários ---
$inputFile = Read-Host -Prompt "Por favor, insira o caminho completo para o arquivo TXT contendo os nomes de logon dos usuários (um por linha)"
if (-not (Test-Path $inputFile)) {
    Write-Log "ERRO: Arquivo '$inputFile' não encontrado." -ConsoleForegroundColor Red
    exit 1
}

# --- Ler Nomes de Usuário do Arquivo ---
try {
    $userLogonNamesFromFile = Get-Content $inputFile -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
catch {
    Write-Log "ERRO ao ler o arquivo '$inputFile': $($_.Exception.Message)" -ConsoleForegroundColor Red
    exit 1
}

if ($userLogonNamesFromFile.Count -eq 0) {
    Write-Log "ERRO: Nenhum nome de usuário válido encontrado no arquivo '$inputFile' ou o arquivo está vazio." -ConsoleForegroundColor Red
    exit 1
}

Write-Log "`nIniciando o processo de reset de senha para usuários do arquivo: $inputFile" -ConsoleForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($targetDC)) {
    Write-Log "Operações AD serão direcionadas para o servidor: $targetDC" -ConsoleForegroundColor Cyan
}
Write-Log "Total de entradas na lista a processar: $($userLogonNamesFromFile.Count)" -ConsoleForegroundColor Cyan
Write-Log ("-" * 70)

# --- Loop de Processamento dos Usuários ---
foreach ($userLogonNameInput in $userLogonNamesFromFile) {
    Write-Log "Processando entrada da lista: '$userLogonNameInput'..." -ConsoleForegroundColor Yellow
    $adUser = $null
    $displayName = "N/A"
    $samAccountName = $userLogonNameInput 
    $novaSenhaGerada = "" 

    # Parâmetros comuns para cmdlets AD (para adicionar -Server condicionalmente)
    $commonAdCmdletParams = @{}
    if (-not [string]::IsNullOrWhiteSpace($targetDC)) {
        $commonAdCmdletParams.Server = $targetDC
    }

    try {
        # 1. Tentar encontrar o usuário e obter DisplayName e SamAccountName
        $getADUserParams = @{
            Identity = $userLogonNameInput
            Properties = 'DisplayName', 'SamAccountName'
            ErrorAction = 'Stop'
        } + $commonAdCmdletParams # Adiciona -Server se $targetDC estiver definido

        try {
            $adUser = Get-ADUser @getADUserParams
        }
        catch {
            Write-Log "ERRO DETALHADO em Get-ADUser para '$userLogonNameInput': $($_.Exception.ToString())" -ConsoleForegroundColor Magenta
            throw # Re-lança o erro para ser pego pelo catch principal e pular este usuário
        }
        
        $samAccountName = $adUser.SamAccountName 
        if ($adUser.DisplayName) {
            $displayName = $adUser.DisplayName
        } else {
            $displayName = "<DisplayName não configurado>"
        }
        Write-Log "Usuário AD encontrado: '$samAccountName' (DisplayName: '$displayName')." -ConsoleForegroundColor DarkGray

        # 2. Gerar nova senha para o usuário atual
        $novaSenhaGerada = Gerar-NovaSenha -Comprimento $TamanhoSenha
        Write-Log "Senha gerada para '$samAccountName' (DisplayName: '$displayName'): $novaSenhaGerada"
        
        # 3. Resetar a senha no Active Directory (com verificação de $?)
        Write-Log "Tentando executar Set-ADAccountPassword para '$samAccountName'..."
        $securePassword = ConvertTo-SecureString $novaSenhaGerada -AsPlainText -Force
        
        $setPwdParams = @{
            Identity = $adUser 
            NewPassword = $securePassword
            Reset = $true
        } + $commonAdCmdletParams

        Set-ADAccountPassword @setPwdParams # ErrorAction é Continue por padrão aqui para podermos checar $?
            
        if (-not $?) { # $? é $false se o último comando falhou (mesmo com ErrorAction Continue)
            $ultimoErroCompleto = $Error[0] # Pega o registro de erro completo mais recente
            $mensagemErroEspecifica = $ultimoErroCompleto.ToString()
            if ($ultimoErroCompleto.Exception) { $mensagemErroEspecifica = $ultimoErroCompleto.Exception.ToString() }

            Write-Log "Set-ADAccountPassword FALHOU para '$samAccountName'. Status de $?: $?. Erro mais recente: $mensagemErroEspecifica" -ConsoleForegroundColor Red
            # Para depuração extrema do objeto de erro (descomente se necessário):
            # $ultimoErroCompleto.PSObject.Properties | ForEach-Object { Write-Log "Detalhe do Erro: $($_.Name) = $($_.Value)" }
            throw "Falha no Set-ADAccountPassword (detalhes registrados no log)" # Re-lança para o catch principal
        } else {
            # $? é $true, o PowerShell considera que o comando foi executado sem erros que ele detectaria como falha.
            Write-Log "Set-ADAccountPassword EXECUTADO com $? = True para '$samAccountName'. Isso sugere que o cmdlet não reportou erro." -ConsoleForegroundColor Yellow
            Write-Log "SUCESSO (conforme $?): Senha para '$samAccountName' (DisplayName: '$displayName') deveria ter sido resetada. Nova Senha Atribuída: $novaSenhaGerada" -ConsoleForegroundColor Green
            
            # 4. (Recomendado) Forçar o usuário a alterar a senha no próximo logon
            try {
                $setADUserParams = @{
                    Identity = $adUser
                    ChangePasswordAtLogon = $true
                    ErrorAction = 'Stop'
                } + $commonAdCmdletParams
                Set-ADUser @setADUserParams
                Write-Log "O usuário '$samAccountName' (DisplayName: '$displayName') precisará alterar esta senha no próximo logon." -ConsoleForegroundColor Green
            }
            catch {
                Write-Log "AVISO (após Set-ADAccountPassword aparentemente bem-sucedido): Não foi possível definir 'Alterar senha no próximo logon' para '$samAccountName'. Erro: $($_.Exception.ToString())" -ConsoleForegroundColor Yellow
                # Não relançar, pois o reset da senha principal (baseado em $?) pareceu funcionar.
            }
        }
    }
    catch { # Catch principal para cada usuário no loop foreach
        # $errorMessage já conteria a mensagem do erro que foi re-lançado pelos blocos try-catch internos
        # ou de qualquer outro erro não capturado internamente.
        $errorMessage = if ($_.Exception.InnerException) { $_.Exception.InnerException.ToString() } else { $_.Exception.ToString() } # Pegar ToString() para mais detalhes
        
        if ($adUser) { 
            Write-Log "FALHA NO PROCESSAMENTO GERAL do usuário '$samAccountName' (DisplayName: '$displayName'). Senha que seria usada (se gerada): '$novaSenhaGerada'. Erro: $errorMessage" -ConsoleForegroundColor Red
        } else { 
             Write-Log "FALHA NO PROCESSAMENTO GERAL: Usuário com identificador '$userLogonNameInput' não pôde ser processado (ex: não encontrado ou erro antes do reset). Erro: $errorMessage" -ConsoleForegroundColor Red
        }
    }
    Write-Log ("-" * 70) 
}

Write-Log "Processamento da lista de usuários concluído." -ConsoleForegroundColor Cyan
Write-Host "`nLog detalhado salvo em: $logFile"
