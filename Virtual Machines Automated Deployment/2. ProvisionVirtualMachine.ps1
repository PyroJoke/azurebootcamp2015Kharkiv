# Import constants
. .\Constants.ps1
# Get subscriptions list and change default one
#Get-AzureSubscription | ft -AutoSize SubscriptionId, SubscriptionName, IsDefault, IsCurrent, CurrentStorageAccountName
#Select-AzureSubscription -SubscriptionName $DefaultSubscription

# Create new storage account where all machine images will exist
#New-AzureStorageAccount -StorageAccountName $StorageAccountName -Location $Region

# Associate a newly created storage account with current subscription
#Set-AzureSubscription -SubscriptionName $DefaultSubscription -CurrentStorageAccountName $StorageAccountName

# Provision new cloud service
#New-AzureService -ServiceName $CloudServiceName -Location $Region

# Get the list of available vm images
#Get-AzureVMImage | where {$_.OS -eq "Windows"} | ft -AutoSize ImageName, Location, Label

# Provision new vms
$frontendVMImage = (Get-AzureVMImage -Verbose:$false | Where-Object {$_.label -like “Windows Server 2012 Datacenter*”}| Sort-Object –Descending PublishedDate)[0].ImageName
$sqlVMImage = (Get-AzureVMImage -Verbose:$false | Where-Object {$_.label -like “SQL Server 2014*”}| Sort-Object –Descending PublishedDate)[0].ImageName
$size = "Medium"
$availabilitySetName = "azurebootcamp2015kh"
$http80LoadBalancedSet = "http80"
$secPassword = ConvertTo-SecureString $AdminUserPassword -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($AdminUserName, $secPassword)

foreach($virtualMachine in $VirtualMachines){
$vmConfig = New-AzureVMConfig -Name $virtualMachine.Name -InstanceSize $size -ImageName $frontendVMImage -AvailabilitySetName $availabilitySetName |
			Add-AzureProvisioningConfig -Windows -AdminUsername $AdminUserName -Password $AdminUserPassword |
			Add-AzureEndpoint -Name "HttpIn" -Protocol tcp -LocalPort 80 -PublicPort 80 -LBSetName $http80LoadBalancedSet -ProbePort 80 -ProbeProtocol "http" -ProbePath '/' |
            Add-AzureEndpoint -Name "WebDeploy" -Protocol tcp -LocalPort 8172 -PublicPort $virtualMachine.WebDeployPort
$vmConfig | New-AzureVM -ServiceName $CloudServiceName -WaitForBoot

"Installing certificate for secure remote Powershell access"
.\InstallWinRMCertAzureVM.ps1 -SubscriptionName $DefaultSubscription -ServiceName $CloudServiceName -Name $virtualMachine.Name

# Return back the correct URI for Remote PowerShell  
$uri = Get-AzureWinRMUri -ServiceName $CloudServiceName -Name $virtualMachine.Name 

# For x86 Host
Invoke-Command -ConnectionUri $uri.ToString() -Credential $credential -ScriptBlock {
Set-Alias ps64 "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
ps64 {
    $logLabel = $((get-date).ToString("yyyyMMddHHmmss"))
    $logPath = "$env:TEMP\init_webservervm_install_log_$logLabel.txt"
    "Installing Windows Features"
    Import-Module -Name ServerManager
    Install-WindowsFeature Web-Server, Web-Mgmt-Service, Web-Asp-Net45 -IncludeManagementTools -LogPath $logPath
    "Modifying default app pool. Setting up admin credentials."
    Import-Module WebAdministration
    Set-ItemProperty IIS:\AppPools\DefaultAppPool -name processModel -value @{userName="BootcampAdmin";password="some@strongPassword1";identitytype=3}
    "Enabling IIS Remote Management"
    # Enable IIS Remote Management
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement -Value 1
    Set-Service -name WMSVC -StartupType Automatic
    Start-service WMSVC
    # Opening WebDeploy port
    "Opening WebDeploy port"
    $port = New-Object -ComObject HNetCfg.FWOpenPort
    $port.Port = 8172
    $port.Name = 'WebDeploy Inbound Port'
    $port.Enabled = $true
    
    $fwMgr = New-Object -ComObject HNetCfg.FwMgr
    $profile = $fwMgr.LocalPolicy.CurrentProfile
    $profile.GloballyOpenPorts.Add($port)
}
}
$currentVm = Get-AzureVM -ServiceName $CloudServiceName -Name $virtualMachine.Name
Set-AzureVMExtension -ExtensionName WebDeployForVSDevTest -Publisher "Microsoft.VisualStudio.WindowsAzure.DevTest" -Version "1.0" -VM $currentVm | Update-AzureVM -Verbose
}

# Provision SQL Server
$vmConfig = New-AzureVMConfig -Name $SqlServerVMName -InstanceSize $size -ImageName $sqlVMImage |
			Add-AzureProvisioningConfig -Windows -AdminUsername $AdminUserName -Password $AdminUserPassword
$vmConfig | New-AzureVM -ServiceName $CloudServiceName -WaitForBoot
"Installing certificate for secure remote Powershell access"
.\InstallWinRMCertAzureVM.ps1 -SubscriptionName $DefaultSubscription -ServiceName $CloudServiceName -Name $SqlServerVMName

# Return back the correct URI for Remote PowerShell  
$uri = Get-AzureWinRMUri -ServiceName $CloudServiceName -Name $SqlServerVMName
Invoke-Command -ConnectionUri $uri.ToString() -Credential $credential -ScriptBlock {
Set-Alias ps64 "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
ps64 {
    # Open required port
    $port = New-Object -ComObject HNetCfg.FWOpenPort
    $port.Port = 1433
    $port.Name = 'SQL Server Default Port'
    $port.Enabled = $true
    
    $fwMgr = New-Object -ComObject HNetCfg.FwMgr
    $profile = $fwMgr.LocalPolicy.CurrentProfile
    "Adding port"
    $profile.GloballyOpenPorts.Add($port)
}
}