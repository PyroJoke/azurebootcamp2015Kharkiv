<#
 # Create account.txt file with the username
 Read-Host -Prompt "Please type the user account name in your subscription to use" | Out-File .\account.txt

 # Create PWD File with this command: 
 Read-Host -Prompt "Password" -AsSecureString | ConvertFrom-SecureString | out-file ($env:USERPROFILE + "\pwdfile.txt")

#>
Param(
    [string]$PasswordFilePath = $env:USERPROFILE + "\pwdfile.txt",

    [string]$SubscriptionName = "Free Trial"
)

if(!(Test-Path $PasswordFilePath) ) 
{ 
    Write-Error @"
    PWD File not found. Please run the following command and type your Azure account password:
    Read-Host -Prompt "Password" -AsSecureString | ConvertFrom-SecureString | out-file $env:USERPROFILE + "\pwdfile.txt"
"@

    throw "PWD File not found"; 
}

if(!(Test-Path  ($PSScriptRoot + "\account.txt")) )
{
   throw "File account.txt not found"
}


$username = Get-Content ($PSScriptRoot + "\account.txt")
$password =  cat $PasswordFilePath | ConvertTo-SecureString;

Write-Host "Connecting as $username..."

$deploymentCreds = New-Object System.Management.Automation.PSCredential($username, $password);

$account = Add-AzureAccount -Credential $deploymentCreds


Write-Output "Selecting subscription $SubscriptionName ..."
$subscription = Get-AzureSubscription -SubscriptionName $SubscriptionName | Where TenantId -eq $account.Tenants


Select-AzureSubscription -SubscriptionId $subscription[0].SubscriptionId -Current
Set-AzureSubscription -SubscriptionId $subscription[0].SubscriptionId

