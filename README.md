# Script PowerShell para Consulta de Usuários e Comparação de Departamento Principal no AD

Este script PowerShell robusto consulta o Active Directory para obter informações detalhadas de um ou mais usuários especificados por seus nomes de logon. Além de exibir atributos como SamAccountName, Nome de Exibição e Departamento Completo, ele deriva e exibe o "Departamento Principal" (a primeira parte da string de departamento, usualmente antes do primeiro espaço). Ao final do processamento, o script realiza uma validação crucial: verifica se todos os usuários encontrados e processados pertencem ao mesmo "Departamento Principal".

## Funcionalidades Principais

* **Consulta Múltipla de Usuários:** Permite pesquisar informações de vários usuários em uma única execução, fornecendo uma lista de nomes de logon.
* **Identificação Flexível:** Aceita diversos tipos de identificadores de usuário (SamAccountName, UserPrincipalName, Distinguished Name, GUID, SID).
* **Extração Detalhada de Atributos:** Recupera e exibe SamAccountName, DisplayName (Nome de Exibição), Departamento Completo e DistinguishedName (DN).
* **Derivação de Departamento Principal:** Identifica e exibe o "Departamento Principal" de cada usuário, extraindo a porção da string de departamento antes do primeiro espaço (ou a string completa, se não houver espaços). Esta é a base para a comparação.
* **Validação de Consistência Departamental:** Compara os "Departamentos Principais" de todos os usuários encontrados e informa se são todos idênticos.
* **Busca Escopada (Opcional):** Permite restringir a pesquisa a uma Unidade Organizacional (OU) específica através do parâmetro `-SearchBase`.
* **Saída Informativa:** Fornece feedback detalhado para cada usuário processado, incluindo o departamento completo e o principal utilizado na comparação, além de um sumário claro da validação.
* **Tratamento de Erros Individualizado:** Se um usuário não for encontrado ou ocorrer um erro durante sua busca, o script reporta o problema e continua o processamento para os demais usuários.

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
