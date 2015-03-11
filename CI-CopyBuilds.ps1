param(
	# d:\Vhd-Release\
	[String]$baseDestinationPath,
	[String]$vmHyperVName, 
	[String]$baseFolderPath,
    [String]$buildLocation,
  	[String]$mtBuildLocation,
    [String]$branchName,
    [String]$runboxType = "",
	[String]$i386BuildLocation = "",
    [string]$release = $null,
    [string]$environment = $null
)

. .\Tools.ps1 
. .\Configuration.ps1
. .\TFSHelper.ps1

Log-Info "Parameters." -isNewTask $true
Log-Info "Parameter baseDestinationPath: $baseDestinationPath" 
Log-Info "Parameter vmHyperVName       : $vmHyperVName" 
Log-Info "Parameter baseFolderPath     : $baseFolderPath" 

# create xml to hold builds
[string]$vmBaseFolder = "$baseFolderPath\$vmHyperVName";
[string]$vmBuildsXml = "$vmBaseFolder\Builds.xml"

Log-Info "Creating xml file $vmBuildsXml." -isNewTask $true

$xml = New-Object xml  
$summary = $xml.CreateElement("Summary")
$components = $xml.CreateElement("Components")
$summary.AppendChild($components)
[void]$components.SetAttribute("VMName","$vmHyperVName")
[void]$components.SetAttribute("StartTime","$([datetime]::Now)")
[void]$components.SetAttribute("RunboxType", $runboxType)
[void]$xml.AppendChild($summary)
[void]$xml.Save("$vmBuildsXml")

Log-Info "Getting build locations." -isNewTask $true

#Build Locations 
[string]$latestQBuildDropPath = ""
[string]$latestQBuildi386DropPath = "";
[string]$latestQBuildMTDropPath = "";
[string]$latestCacheV2CCDropPath = "";
[string]$cacheV2CCBranchName = "adsappscc_vnext";

if($release)
{
    Log-Info "Release parameter for Getting builds from RME:        : $release" 
    Log-Info "Environment parameter for Getting builds from RME:      : $environment" 
    Set-BuildsFromRMEToXML $release $environment $vmBuildsXml
}
else
{
    #Using CacheV2 drop only for Release Branch CI runs and all Accounts and Billing components only
    if($baseFolderPath.ToLower().Contains("release"))
    {
            $latestCacheV2CCDropPath = Get-LatestCacheV2BuildPathUsingDropService $cacheV2CCBranchName    
    }

    if([string]::IsNullOrEmpty($buildLocation))
    {
        $latestQBuildDropPath = Get-LatestBuildPathFromQBuild $branchName $vmBaseFolder $true
       
        $latestQBuildMTDropPath = Get-LatestBuildPathFromQBuild $mtVirtualBranchName $vmBaseFolder $true $true
        
        if([string]::IsNullOrEmpty($latestCacheV2CCDropPath))
        {
            $latestCacheV2CCDropPath = $latestQBuildDropPath           
        }
    }
    else 
    {
        $latestQBuildDropPath = $buildLocation
   		if($mtBuildLocation) 
		{
			$latestQBuildMTDropPath = $mtBuildLocation
		}
		else 
		{
			$latestQBuildMTDropPath = $buildLocation
		}

        if([string]::IsNullOrEmpty($latestCacheV2CCDropPath))
        {
            $latestCacheV2CCDropPath = $latestQBuildDropPath           
        }        
    }

    if ([string]::IsNullOrEmpty($i386BuildLocation))
    {
        $latestQBuildi386DropPath = Get-LatestBuildPathFromQBuild $branchName $vmBaseFolder $false
    }
    else
    {
        $latestQBuildi386DropPath = $i386BuildLocation
    }

    [string]$campaignDbDropPath = $latestQBuildDropPath
    [string]$customerDbDropPath = $latestCacheV2CCDropPath
    [string]$fraudDbDropPath = $latestQBuildDropPath
    [string]$pubCenterDbDropPath = $latestQBuildDropPath
    [string]$clientCenterDropPath = $latestCacheV2CCDropPath
    [string]$campaignMtDropPath = $latestQBuildMTDropPath
    [string]$clientCenterApiDropPath = $latestCacheV2CCDropPath
    [string]$campaignUiDropPath = $latestQBuildDropPath 
	[string]$clientCenterUiDropPath = $latestCacheV2CCDropPath
    [string]$fraudMtDropPath = $latestQBuildDropPath
    [string]$campaignUiTestDropPath = $latestCacheV2CCDropPath
    [string]$clientCenterTestDropPath = $latestCacheV2CCDropPath
    [string]$publicDropPath = "$latestQBuildDropPath\..\..\public" 
    [string]$privateDropPath = "$latestQBuildDropPath\..\..\private" 
    [string]$desktopDropPath = $latestQBuildi386DropPath
    #Below build is preserved for BSC and will be replaced later by automatic latest build detection.
	[string]$AdvbibscDropPath = "\\asgdrops\search\nonrelease\sdpstripe\4596.0.150310-0130\retail\amd64\app"

    Log-Info "Setting drops to xml." -isNewTask $true

    Add-BuildsToXML $vmBuildsXml "CampaignDB" $campaignDbDropPath

    Add-BuildsToXML $vmBuildsXml "CustomerDB" $customerDbDropPath -isCacheV2BuildPath $true

    Add-BuildsToXML $vmBuildsXml "FraudDB" $fraudDbDropPath 

    Add-BuildsToXML $vmBuildsXML "PublisherDB" $pubCenterDbDropPath 

    Add-BuildsToXML $vmBuildsXML "ClientCenterMT" $clientCenterDropPath -isCacheV2BuildPath $true

    Add-BuildsToXML $vmBuildsXML "CampaignMT" $campaignMtDropPath 

    Add-BuildsToXML $vmBuildsXML "CustomerManagementAPI" $clientCenterApiDropPath -isCacheV2BuildPath $true 

    Add-BuildsToXML $vmBuildsXML "ClientCenterUITest" $clientCenterUiDropPath -isCacheV2BuildPath $true

    Add-BuildsToXML $vmBuildsXML "CampaignUI" $campaignUiDropPath 
	
	Add-BuildsToXML $vmBuildsXML "ClientCenterUI" $clientCenterUiDropPath -isCacheV2BuildPath $true

    Add-BuildsToXML $vmBuildsXML "CampaignUITest" $campaignUiTestDropPath

    Add-BuildsToXML $vmBuildsXML "FraudMT" $fraudMtDropPath
	
	Add-BuildsToXML $vmBuildsXML "Public" $publicDropPath
	
	Add-BuildsToXML $vmBuildsXML "Private" $privateDropPath

    #i386 Builds
    Add-BuildsToXML $vmBuildsXml "Desktop" $desktopDropPath
	
	#Advbi BSC
	Add-BuildsToXML $vmBuildsXml "AdvertiserBIBSC" $AdvbibscDropPath

    Add-BuildsToXML $vmBuildsXml "RulesEngine" $campaignMtDropPath

    Add-BuildsToXML $vmBuildsXml "MapOffersTreeNodesService" $latestQBuildDropPath
}
Log-Info "Setting drops completed." -isNewTask $true

$output = Check-IsAdrelOnline "$vmBuildsXml"