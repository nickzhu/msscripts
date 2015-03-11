param([String]$vmHyperVName, [String]$baseFolderPath)

. .\Tools.ps1
. .\Instantiate-VM.ps1
. .\ClientCenter.ps1
. .\CampaignMT.ps1
. .\CampaignUI.ps1
. .\CampaignApi.ps1
. .\Configuration.ps1

# Append The builds for UI Test So we can log which test were run. 
[string]$vmBaseFolder = "$baseFolderPath\$vmHyperVName";
[string]$vmBuildsXml = "$vmBaseFolder\Builds.xml"

$continueRun = Check-ExitDueToEnviromentIssues "$vmBuildsXml"

if (!$continueRun)
{
    Log-Info "Exiting the run." -isNewTask $true  
    exit
}

#Start Mock Service 
$mockLogPath =  "D:\Logs\AdverstiserMock"
#Test-Path $mockLogPath
mkdir $mockLogPath
Start-WebAppPool -Name AdvertiserMocks
Start-Website -Name AdvertiserMocks

# Overwrite The Builds Just in case a new build has been completed. 
$xml = [xml](Get-Content "$vmBuildsXml")
$campaignmtdroppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignMT']").Local 
$clientcenterdroppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='ClientCenterMT']").Local
$campaignDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignDB']").Local
$customerDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CustomerDB']").Local
$campaignUiDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignUITest']").Local
$clientCenterTestDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='ClientCenterUITest']").Local 

$address = $xml.Summary.MachineInfo.IpAddress
$fqdn = $xml.Summary.MachineInfo.FQDN

# Set app pool
Log-Info "Setting app pool"
[ScriptBlock]$command = {
cmd /c C:\windows\system32\inetsrv\appcmd set config /section:isapiCgiRestriction "/[path='C:\Windows\Microsoft.NET\Framework64\v4.0.30319\aspnet_isapi.dll'].allowed:""True""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config /section:isapiCgiRestriction "/[path='C:\Windows\Microsoft.NET\Framework\v4.0.30319\aspnet_isapi.dll'].allowed:""True""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='ASP.NET v4.0'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='ASP.NET v4.0 Classic'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_CampaignResources'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_CampaignUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_ClientCenterResources'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_CustomerUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_OldCustomerUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_ResearchUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_RootUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_SecureUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_StaticResourcesRoot'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_SupportUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='AUTOIISPOOL_ToolsUI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignApiV9BetaAppPool'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignMiddleTier'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignMiddleTierAPI'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignMiddleTierAPIv9'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignMiddleTierBingAdsODataApi'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='CampaignMiddleTierFileUpload'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='Classic .NET AppPool'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='ClientCenterApiBeta'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='ClientCenterBillingApiBeta'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='ClientCenterSecureDataMgmtApiBeta'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='crudservice'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='DefaultAppPool'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='FraudServiceAppPool'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='KeyService'].enable32BitAppOnWin64:""False""" /commit:apphost
cmd /c C:\windows\system32\inetsrv\appcmd set config -section:system.applicationHost/applicationPools "/[name='PhoneProvisioningService'].enable32BitAppOnWin64:""False""" /commit:apphost
}

$output = Execute-RemoteProcess $address $command $userName $password

# Log-Info "Wait for replciation. " -isNewTask $true 
# Start-Sleep -Seconds 30*60

#Start All Stopped Sites Just In case 
#This also starts any stopped App Pools
Start-RemoteStoppedSites $address $username $password

# hot start CM MT
Log-Info "Navigate to CM MT EVTs. " -isNewTask $true 
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:801/CampaignMT/v6/CampaignService.svc".Replace("{machine}", $address));
# Start-Sleep -Seconds 30 
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V8.Merged/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V8.Merged/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V8/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V8/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V9Beta/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V9Beta/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
#(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/Api/Advertiser/V7/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8585/Api/SecureDataManagement/v8/SecureDataManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8585/Api/SecureDataManagement/v9/SecureDataManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8585/Api/Billing/v8/CustomerBillingService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8585/Api/CustomerManagement/v8/CustomerManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8585/Api/CustomerManagement/v9/CustomerManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadStringAsync("http://{machine}:8080/ODataApi/Evt/health".Replace("{machine}", $address));
Start-Sleep -Seconds 120


Log-Info "Updating builds xml with Replication status"
Add-ReplicationStatusToXML $address $vmBuildsXml 


# Run Evts 
Log-Info "Updating builds xml with EVT Results"
Update-XMLWithEvtResults $vmBuildsXml 

[datetime]$timestamp = [datetime]::now; Log-Info "[process:: $timestamp]: EVT run completed"