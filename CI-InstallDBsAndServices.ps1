param([String]$ScriptsLocation, [String]$vmHyperVName, [String]$baseFolderPath, [String]$VMFolder, [int]$deployDBComponentsOnAzure)
  . .\Tools.ps1
  . .\Configuration.ps1

# Append The builds for these Web UI's 
  [string]$vmBaseFolder = "$baseFolderPath\$vmHyperVName";
  [string]$vmBuildsXml = "$vmBaseFolder\Builds.xml"
  $xml = [xml](Get-Content "$vmBuildsXml") 
  $address = $xml.Summary.MachineInfo.IpAddress

 Log-Info "Creating Jobs with these params: ScriptsLocation:$ScriptsLocation, vmHyperVName:$vmHyperVName, baseFolderPath:$baseFolderPath, VMFolder:$VMFolder, deployDBComponentsOnAzure:$deployDBComponentsOnAzure"

  $installDBJob = Start-Job -Name "Install DBs" -ScriptBlock {
    $ScriptsLocation = $args[0]
    $vmHyperVName = $args[1]
    $baseFolderPath = $args[2]
    $VMFolder = $args[3]
	$deployDBComponentsOnAzure = $args[4]
    $cargs = "-File $ScriptsLocation\CI-InstallDBs.ps1 ""$vmHyperVName"" ""$baseFolderPath"" ""$deployDBComponentsOnAzure"""
    cd $ScriptsLocation
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\4-InstallDB.log" -Wait -RedirectStandardError "$VMFolder\4-InstallDB_Error.log"

# Restart IIS after db deployments to force CampaignMT re-initialized.
    IISReset

  } -ArgumentList @($ScriptsLocation, $vmHyperVName, $baseFolderPath, $VMFolder, $deployDBComponentsOnAzure)

 
# Run DbValidator and log output
  $dbValidatorJob = Start-Job -Name "Run DbValidator" -ScriptBlock {
    $ScriptsLocation = $args[0]
    $vmHyperVName = $args[1]
    $baseFolderPath = $args[2]
    $VMFolder = $args[3]
    $cargs = "-File $ScriptsLocation\CI-RunDbValidator.ps1 ""$ScriptsLocation"" ""$vmHyperVName"""
    cd $ScriptsLocation
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\4.1-DbValidator.log" -Wait -RedirectStandardError "$VMFolder\4.1-DbValidator_Error.log"
  }  -ArgumentList @($ScriptsLocation, $vmHyperVName, $baseFolderPath, $VMFolder)

  $installServicesJob = Start-Job -Name "Install Services" -ScriptBlock {
    $ScriptsLocation = $args[0]
    $vmHyperVName = $args[1]
    $baseFolderPath = $args[2]
    $VMFolder = $args[3]
    $cargs = "-File $ScriptsLocation\CI-InstallServices.ps1 ""$vmHyperVName"" ""$baseFolderPath"""
    cd $ScriptsLocation
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\5-InstallServices.log" -Wait -RedirectStandardError "$VMFolder\5-InstallServices_Error.log"
    
    C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe /iru
    IISReset

    $cargs = "-File $ScriptsLocation\CI-InstallUI.ps1 ""$vmHyperVName"" ""$baseFolderPath"""
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\6-InstallUI.log" -Wait -RedirectStandardError "$VMFolder\6-InstallUI_Error.log"

    $cargs = "-File $ScriptsLocation\CI-InstallDesktop.ps1 ""$vmHyperVName"" ""$baseFolderPath"""
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\6.1-InstallDesktop.log" -Wait -RedirectStandardError "$VMFolder\6.1-InstallDesktop_Error.log"
 } -ArgumentList @($ScriptsLocation, $vmHyperVName, $baseFolderPath, $VMFolder)

  Wait-Job (@($installDBJob, $dbValidatorJob, $installServicesJob) | where {$_ -ne $null}) -Force
  Log-Info "Wait Job has completed, waiting for the install of DB/validate DB and install services"

  Restart-Service "Microsoft.AdCenter.ClientCenter.MiddleTierService"
  Start-Sleep -Seconds 60

  Log-Info "Setting services and restarting Net TCP Activator"

  # Start Net.Tcp services in case they are disabled.
  Set-Service "NetTcpPortSharing" -StartupType Automatic
  
  Log-Info "Setting services and restarting Net TCP Activator completed"

# PPS depends on CCMT service, so must be installed last
  $installPPSServicesJob = Start-Job -Name "Install PPS Service" -ScriptBlock {
    $ScriptsLocation = $args[0]
    $vmHyperVName = $args[1]
    $baseFolderPath = $args[2]
    $VMFolder = $args[3]
    $cargs = "-File $ScriptsLocation\CI-InstallPPSService.ps1 ""$vmHyperVName"" ""$baseFolderPath"""
    cd $ScriptsLocation
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\6.2-InstallPPSService.log" -Wait -RedirectStandardError "$VMFolder\6.2-InstallPPSService_Error.log"
    
    C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_regiis.exe /iru
    IISReset

 } -ArgumentList @($ScriptsLocation, $vmHyperVName, $baseFolderPath, $VMFolder)
  
  Wait-Job (@($installPPSServicesJob) | where {$_ -ne $null}) -Force

  # AP services as rules engine does not fit well into current IIS-oriented deployment model so 
  $installPPSServicesJob = Start-Job -Name "Install simple AP Services" -ScriptBlock {
    $ScriptsLocation = $args[0]
    $vmHyperVName = $args[1]
    $baseFolderPath = $args[2]
    $VMFolder = $args[3]
    $cargs = "-File $ScriptsLocation\CI-InstallSimpleAPServices.ps1 ""$vmHyperVName"" ""$baseFolderPath"""
    cd $ScriptsLocation
    Start-Process powershell -ArgumentList $cargs -WorkingDirectory $ScriptsLocation -RedirectStandardOutput "$VMFolder\6.3-InstallSimpleAPServices.log" -Wait -RedirectStandardError "$VMFolder\6.3-InstallSimpleAPServices_Error.log"

 } -ArgumentList @($ScriptsLocation, $vmHyperVName, $baseFolderPath, $VMFolder)
  
  Wait-Job (@($installPPSServicesJob) | where {$_ -ne $null}) -Force
  
  #UI post installation setup
  [ScriptBlock]$command = 
  {
    cd D:\app
    .\cfm.bat
  }
  Execute-RemoteProcess $address $command $username $password
