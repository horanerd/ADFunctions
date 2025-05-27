# Script PowerShell para Consulta de Usuário no Active Directory

Este script PowerShell permite consultar rapidamente o Active Directory para obter informações de um usuário específico com base no seu nome de logon (SamAccountName, UserPrincipalName, etc.). Ele recupera detalhes como Nome de Exibição (DisplayName), Departamento e Distinguished Name (DN).

## Funcionalidades

* Pesquisa usuários por vários identificadores (SamAccountName, UserPrincipalName, Distinguished Name, GUID ou SID).
* Recupera atributos chave do usuário: SamAccountName, DisplayName, Departamento e DistinguishedName.
* Opcionalmente, limita a pesquisa a uma Unidade Organizacional (OU) específica.
* Saída clara com os detalhes do usuário encontrado.
* Tratamento de erros para usuários não encontrados ou outros problemas durante a consulta.

## Pré-requisitos

* Máquina Windows com PowerShell (preferencialmente versão 3.0 ou superior).
* Módulo PowerShell do Active Directory instalado. Este módulo faz parte das Ferramentas de Administração de Servidor Remoto (RSAT) para Active Directory Domain Services (AD DS).
* Permissões suficientes para ler objetos de usuário e seus atributos no Active Directory do domínio que você está consultando.

## Como Executar

1.  **Download/Salvar:** Baixe ou copie o código do script e salve-o em um arquivo com a extensão `.ps1` (por exemplo, `Get-ADUserInfoByLogon.ps1`).
2.  **Abrir PowerShell:** Abra uma janela do PowerShell.
3.  **Navegar até o Diretório:** Use o comando `cd` para navegar até o diretório onde você salvou o script.
    ```powershell
    cd C:\Caminho\Para\Seu\Script
    ```
4.  **Executar o Script:** Execute o script fornecendo os parâmetros necessários. Veja os exemplos abaixo.

## Parâmetros

* `UserLogonName` (String - Obrigatório)
    * Descrição: O nome de logon ou outro identificador único do usuário a ser pesquisado. Pode ser o SamAccountName, UserPrincipalName (UPN), Distinguished Name (DN), GUID ou SID.
    * Exemplo: `"josedasilva"`, `"josedasilva@empresa.com"`, `"CN=Jose da Silva,OU=Usuarios,DC=empresa,DC=com"`

* `SearchBase` (String - Opcional)
    * Descrição: O Distinguished Name (DN) da Unidade Organizacional (OU) ou contêiner onde a busca do usuário deve ser restringida. Se omitido, a busca pode ocorrer em todo o domínio (dependendo do tipo de identidade fornecida e da configuração do AD).
    * Exemplo: `"OU=Vendas,DC=empresa,DC=com"`

## Exemplos de Uso

* **Buscar usuário pelo SamAccountName:**
    ```powershell
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva"
    ```

* **Buscar usuário pelo UserPrincipalName (UPN):**
    ```powershell
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva@empresa.com"
    ```

* **Buscar usuário pelo SamAccountName dentro de uma OU específica:**
    ```powershell
    .\Get-ADUserInfoByLogon.ps1 -UserLogonName "josedasilva" -SearchBase "OU=Marketing,DC=suaempresa,DC=com"
    ```

## Exemplo de Saída
