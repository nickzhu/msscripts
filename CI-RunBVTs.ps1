param([String]$vmHyperVName, [String]$baseFolderPath)

. .\Tools.ps1
. .\AppsDatabase.ps1
. .\Instantiate-VM.ps1
. .\ClientCenter.ps1
. .\CampaignMT.ps1
. .\CampaignUI.ps1
. .\CampaignApi.ps1
. .\Desktop.ps1
. .\Configuration.ps1

Import-Module .\CI-Selenium.psm1

#remove exired clientcenter certificate from Store
#$today = Get-Date
#Get-ChildItem Cert:\LocalMachine\My |Where-Object NotAfter -lt $today| Where-Object {$_.Subject -eq "CN=clientcenterdev.redmond.corp.microsoft.com"} | Remove-Item


[string]$bvtBaseDropFolder = "$baseFolderPath\$vmHyperVName";


Log-Info "bvtBaseDropFolder "
Log-Info $bvtBaseDropFolder

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
$desktopTestDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='Desktop']").Local 

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
(New-Object Net.Webclient).DownloadString("http://{machine}:801/CampaignMT/v6/CampaignService.svc".Replace("{machine}", $address));
# Start-Sleep -Seconds 30 
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V8.Merged/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address)) ;
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V8.Merged/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V8/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V8/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V9Beta/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V9Beta/CampaignManagement/CampaignManagementServiceRest.svc".Replace("{machine}", $address));
#(New-Object Net.Webclient).DownloadString("http://{machine}:8080/Api/Advertiser/V7/CampaignManagement/CampaignManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8585/Api/SecureDataManagement/v8/SecureDataManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8585/Api/SecureDataManagement/v9/SecureDataManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8585/Api/Billing/v8/CustomerBillingService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8585/Api/CustomerManagement/v8/CustomerManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8585/Api/CustomerManagement/v9/CustomerManagementService.svc".Replace("{machine}", $address));
(New-Object Net.Webclient).DownloadString("http://{machine}:8080/ODataApi/Evt/health".Replace("{machine}", $address));
Start-Sleep -Seconds 120


Log-Info "Updating builds xml with Replication status"
Add-ReplicationStatusToXML $address $vmBuildsXml 


if ($miniTestSuites -eq $true)
{
    Log-Info "Regression test Suites Are Enabled skipping BVTs" -isNewTask $true
    exit 
}

Start-SqlTrace $address

#run Bulk first
Log-Info "running functional tests - Bulk upload-download Test." -isNewTask $true
$bulkBvtJob = RunBVT-CampaignMiddleTierTest $campaignmtdroppath $address "$bvtbasedropfolder\bulk\" "Bulk"
#
# run BVTs
#

Log-Info "Initiating Desktop BVTs" -isNewTask $true
$desktopJob = RunBVT-Desktop "$desktopTestDropPath\Desktop" $address "$bvtbasedropfolder\Desktop"

$campaignDBDeploymentStatus = $xml.SelectSingleNode("/Summary/Deployments/Deployment[@Name='CampaignDb - RunDbDeploy']").Status 
if ($campaignDBDeploymentStatus -eq "Pass")
{
  Log-Info "Initiating Campaign DB BVTs" -isNewTask $true 
  $campaignDBJob = RunBVT-CampaignDB $campaignmtdroppath $address "$bvtbasedropfolder\bvt-campaigndb" "AppsVHDBVTs"
}
else
{
  Log-Info "Campaign DB BVTs skipped because CampaignDb - RunDbDeploy failed." -isNewTask $true
  $campaignDBJob = $null
}

#Log-Info "Initiating Staging Area BVTs" -isNewTask $true 
$stagingAreaJob = RunBVT-AdminSA $campaignDbDropPath $address "$bvtbasedropfolder\bvt-adminsa"

$customerDBDeploymentStatus = $xml.SelectSingleNode("/Summary/Deployments/Deployment[@Name='CustomerDB - Incremental']").Status
if ($customerDBDeploymentStatus -eq "Pass")
{
  Log-Info "Initiating Customer DB BVTs" -isNewTask $true 
  $customerDBJob = RunBVT-CustomerDB "$customerDbDropPath\ClientCenter\DB\Test\CustomerDBTests" $address "$bvtbasedropfolder\bvt-customerdb" "AppsVHDBVTs"  
}
else
{
  Log-Info "Customer DB BVTs skipped because CustomerDB - Incremental failed." -isNewTask $true
  $customerDBJob = $null
}

Log-Info "running functional tests - campaign management mt." -isNewTask $true
$campaignmtbvtjob = runbvt-campaignmt $campaignmtdroppath $address "$bvtbasedropfolder\campaignmt\"

Log-Info "running functional tests - Campaign MiddleTier Test." -isNewTask $true
$campaignMiddleTierBvtJob = RunBVT-CampaignMiddleTierTest $campaignmtdroppath $address "$bvtbasedropfolder\campaignMiddleTier\"

#Log-Info "running functional tests - Fraud MiddleTier Test." -isNewTask $true
#$fraudMiddleTierBvtJob = RunBVT-FraudMiddleTierTest $campaignmtdroppath $address "$bvtbasedropfolder\FraudMT\"

Log-Info "running functional tests - Client Center Test Team Test." -isNewTask $true
$cctestjob = RunBVT-ClientCenterTest "$clientCenterDropPath\CCMT\ClientCenterTest" $address "$bvtbasedropfolder\cctest"  "MT/BVT"

#Start All Stopped Sites Just In case 
Start-RemoteStoppedSites $address $username $password

Log-Info "running functional tests - Client Center Test Framework API test For CCAPI V8." -isNewTask $true
$ccapiTestJob = RunBVT-ClientCenterTest "$clientcenterdroppath\CCMT\ClientCenterTest" $address "$bvtbasedropfolder\ccapitest" "API/BVT" -version "8"

Log-Info "running functional tests - Client Center Test Framework API test For CCAPI V9." -isNewTask $true
$ccapiv9TestJob = RunBVT-ClientCenterTest "$clientcenterdroppath\CCMT\ClientCenterTest" $address "$bvtbasedropfolder\ccapiv9test" "API/BVT_V9" -version "9"

Log-Info "running functional tests - Message Center MT test." -isNewTask $true
$mcmtTestJob = RunBVT-ClientCenterTest "$clientcenterdroppath\CCMT\ClientCenterTest" $address "$bvtbasedropfolder\mcmttest" "MessageCenter/BVT"
 
Log-Info "running functional tests - campaign management api 8 merged." -isNewTask $true
$campaignapi8mergedbvtjob = runbvt-campaignapi $campaignmtdroppath $address "$bvtbasedropfolder\campaignapi8merged\" -version "8.merged"

Log-Info "running functional tests - campaign management api v8." -isNewTask $true
$campaignapibvtjob = runbvt-campaignapi $campaignmtdroppath $address "$bvtbasedropfolder\campaignapi8\" -version "8"

Log-Info "running functional tests - campaign management api v9" -isNewTask $true
$campaignapiv9bvtjob = runbvt-campaignapi $campaignmtdroppath $address "$bvtbasedropfolder\campaignapiv9\" -version "9"

Log-Info "running functional tests - campaign management api v9Beta." -isNewTask $true
$campaignapi9bvtjob = runbvt-campaignapi $campaignmtdroppath $address "$bvtbasedropfolder\campaignapi9\" -version "9beta"
 
Log-Info "running functional tests - ClientCenter UI test."
$ccuiTestJob = RunBVT-ClientCenterUI "$clientCenterTestDropPath" $address $fqdn "$bvtbasedropfolder\ccuitest"

Log-Info "Starting Campaign UI BVT's" -isNewTask $true
$cmJob = RunBVT-CampaignUI "$campaignUiDropPath" $address $fqdn "$bvtbasedropfolder\bvt-campaignui"

Log-Info "Waiting For Test To Complete with Timeout set to $($bvtTimeLimit) seconds. " -isNewTask $true
Wait-Job ( @($campaignmtbvtjob,$campaignapi8mergedbvtjob,$campaignapibvtjob,$campaignapi9bvtjob,$cctestjob,$mcmtTestJob,$campaignDBJob,$stagingAreaJob,$customerDBJob,$cmJob,$ccuiTestJob,$campaignMiddleTierBvtJob,$ccapiv9TestJob,$bulkBvtJob,$ccapiTestJob,$desktopJob) | where {$_ -ne $null} ) -Timeout (35 * 60) # time in seconds 


# Run Evts 
Log-Info "Updating builds xml with EVT Results"
Update-XMLWithEvtResults $vmBuildsXml 


Stop-SqlTrace $address
#Read-ErrorLog $address

[datetime]$timestamp = [datetime]::now; Log-Info "[process:: $timestamp]: BVT run completed. $nl"

Start-Sleep -Seconds 10


Remove-Module -Name CI-Selenium
