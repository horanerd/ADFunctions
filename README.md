# Script PowerShell Avançado para Consulta de Usuários e Análise Departamental no AD

Este script PowerShell versátil oferece duas formas principais para consultar informações de usuários no Active Directory e comparar seus "Departamentos Principais" (a primeira parte do nome do departamento, geralmente o que vem antes do primeiro espaço). Ele é projetado para ajudar administradores de sistemas e analistas a verificar a consistência departamental de usuários, o status de suas contas e informações sobre a última alteração de senha.

## Modos de Operação Principais

O script opera em dois modos distintos, selecionados pelos parâmetros fornecidos:

1.  **Modo Arquivo (`-FilePath`):**
    * **Entrada:** Processa um arquivo de texto (`.txt`) onde cada linha define um **par específico** de usuários a serem comparados. O formato esperado por linha é `identificador_usuario1,identificador_usuario2`.
    * **Ação Detalhada:**
        * Para cada par lido do arquivo, o script busca as informações de ambos os usuários, incluindo o status da conta (Ativada/Desativada) e o "Departamento Principal".
        * Especificamente para o **segundo usuário (`usuario2`)** de cada par, o script exibe a data da última alteração de senha e há quantos dias isso ocorreu.
        * Realiza uma comparação direta dos "Departamentos Principais" dos dois usuários do par e informa se são idênticos ou diferentes.
    * **Ideal para:** Validações direcionadas de consistência departamental para pares pré-definidos (ex: gerentes e seus liderados diretos, usuários em processos de transferência, etc.).

2.  **Modo Manual/Lista (`-UserLogonName`):**
    * **Entrada:** Recebe uma lista de um ou mais identificadores de usuário fornecidos diretamente na linha de comando (ex: `-UserLogonName "userA","userB","userC"`).
    * **Ação Detalhada:**
        * O script busca as informações de todos os usuários fornecidos, incluindo status da conta, dados da última alteração de senha e o "Departamento Principal".
        * As informações detalhadas de cada usuário encontrado são exibidas individualmente.
        * Ao final, um **sumário** agrupa todos os usuários encontrados por seu "Departamento Principal", indicando quais usuários compartilham o mesmo departamento (sem a listagem exaustiva de todas as comparações N x N).
    * **Ideal para:** Obter uma visão geral da distribuição departamental de um grupo de usuários e identificar rapidamente agrupamentos ou usuários isolados departamentalmente.

## Funcionalidades Chave

* **Dupla Modalidade de Entrada:** Suporte para lista de usuários via arquivo TXT (pares específicos) ou entrada manual (lista para análise resumida).
* **Status da Conta:** Verifica e exibe se cada conta de usuário está "Ativada" ou "Desativada".
* **Informação de `pwdLastSet` (Última Alteração de Senha):**
    * No "Modo Arquivo", exibe prominentemente a data da última alteração de senha e sua idade para o segundo usuário de cada par.
    * A informação de `pwdLastSet` é coletada para todos os usuários em ambos os modos e incluída nos detalhes individuais exibidos no "Modo Manual/Lista".
* **Análise de "Departamento Principal":** Extrai a primeira parte da string de departamento (o que vier antes do primeiro espaço, ou a string completa se não houver espaços) para uma comparação mais flexível.
* **Comparação Departamental Específica ou Agrupada:**
    * Modo Arquivo: Compara cada par explicitamente.
    * Modo Manual/Lista: Apresenta um sumário final que agrupa usuários pelo "Departamento Principal" compartilhado.
* **Busca Escopada Opcional:** O parâmetro `-SearchBase` permite direcionar a consulta do AD para uma Unidade Organizacional (OU) específica.
* **Saída Informativa:** Fornece feedback claro sobre os usuários encontrados, seus departamentos, status da conta, e o resultado das comparações ou do sumário.
* **Tratamento de Erros Robusto:** Gerencia de forma individual usuários não encontrados ou outros erros durante a consulta, continuando o processamento quando aplicável.

## Formato do Arquivo de Entrada (para `-FilePath`)

O arquivo de texto deve conter um par de identificadores de usuário por linha. Os dois identificadores em cada par devem ser separados por uma **vírgula (`,`)**.

**Exemplo de conteúdo para `pares_para_analise.txt`:**
``txt
ana.sousa,carlos.lima
bruno.martins@dominio.com,fernanda.ribeiro
joaquim.alves,TI004578``


Linhas em branco no arquivo são ignoradas. Espaços ao redor dos nomes e da vírgula são removidos pelo script (.Trim()).

##Informações Exibidas por Usuário (durante o processamento individual)

* **Para cada usuário encontrado, o script tenta exibir: **

    * Identificador de Entrada Fornecido
    * SamAccountName (Nome de logon)
    * DisplayName (Nome de Exibição)
    * Status da Conta (Ativada/Desativada)
    * Departamento Completo (como registrado no AD)
    * Departamento Principal (parte usada para comparação)
    * Data da Última Alteração de Senha e Idade da Senha
 
## Sumário Final (para ambos os modos)


Ao final da execução, um sumário agrupa todos os usuários únicos que foram encontrados com sucesso, organizados por seu "Departamento Principal". Para cada departamento, ele lista os usuários (SamAccountName) e o status de suas contas.


## Pré-requisitos

* Máquina Windows com PowerShell (versão 3.0 ou superior é recomendada para melhor compatibilidade com cmdlets do AD).
* Módulo PowerShell do Active Directory instalado. Este módulo é um componente das Ferramentas de Administração de Servidor Remoto (RSAT), especificamente para Active Directory Domain Services (AD DS).
* Permissões de leitura no Active Directory para consultar objetos de usuário e seus atributos (como `department`, `displayName`, `samAccountName`).

## Como Executar

1.  **Salvar o Script:** Copie o código do script e salve-o em um arquivo com a extensão `.ps1` (por exemplo, `Get-ADUsersInfoAndCompareMainDept.ps1`).
2.  **Abrir o PowerShell:** Inicie uma sessão do PowerShell.
3.  **Navegar até o Diretório:** Utilize o comando `cd` para ir até a pasta onde você salvou o script.
    ```powershell
    cd C:\Scripts\AD
    ```
4.  **Executar:** Chame o script fornecendo os parâmetros necessários, conforme os exemplos abaixo.

## Parâmetros

* `UserLogonName <string[]>`: **(Obrigatório)**
    * Define um ou mais nomes de logon (ou outros identificadores válidos no AD) dos usuários a serem pesquisados.
    * Ao fornecer múltiplos usuários diretamente na linha de comando, separe-os por vírgula.
    * Exemplos: `"josedasilva"`, `"josedasilva@empresa.com", "anapereira"`, `"CN=Carlos Santos,OU=TI,DC=empresa,DC=com"`

* `SearchBase <string>`: **(Opcional)**
    * Especifica o Distinguished Name (DN) de uma Unidade Organizacional (OU) ou contêiner para restringir a busca de todos os usuários listados em `-UserLogonName`.
    * Se omitido, a busca é realizada de forma mais ampla no domínio (o escopo exato pode depender do tipo de identidade fornecida e da configuração do AD).
    * Exemplo: `"OU=Financeiro,DC=empresa,DC=local"`

## Exemplos de Uso

* **Buscar informações de um único usuário:**
    ```powershell
    .\Get-ADUsersInfoAndCompareMainDept.ps1 -UserLogonName "carlos.santos"
    ```
    *(Neste caso, a validação de departamento informará que apenas um usuário foi processado.)*

* **Buscar dois usuários e validar se pertencem ao mesmo departamento principal:**
    ```powershell
    .\Get-ADUsersInfoAndCompareMainDept.ps1 -UserLogonName "ana.lima@empresa.com", "pedro.costa"
    ```
    *(Exemplo de resultado: Se Ana é do "Marketing Digital" e Pedro é do "Marketing Eventos", ambos serão considerados do departamento principal "Marketing".)*

* **Buscar múltiplos usuários, um deles com departamento que pode não existir, dentro de uma OU específica:**
    ```powershell
    .\Get-ADUsersInfoAndCompareMainDept.ps1 -UserLogonName "julia.alves", "logon.inexistente", "marcelo.gomes" -SearchBase "OU=Engenharia,DC=empresa,DC=com"
    ```
    *(O script reportará erro para "logon.inexistente" e prosseguirá com os outros, comparando os departamentos principais de Julia e Marcelo.)*

## Exemplo de Saída (Conceitual)
