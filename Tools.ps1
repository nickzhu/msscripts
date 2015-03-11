function Install-OctopusDeploy([string]$dropFullPath,[string]$componentName,[string]$environmentFile,
    [string]$machineIpAddress, [string]$username, [string]$password,[bool]$wait = $false)
{ 
    Log-Info "Copying bits to VM." -isNewTask $true
    [string]$destinationPath = "\\$machineIpAddress\d$\Deploy\$componentName\"
    #copy build drop to d drive
    [string]$dropPath = "$dropFullPath\."
    $copyTime = [datetime]::UtcNow
    $output = robocopy $dropPath $destinationPath /s /mt:64 /copy:d /XO /log+:robocopyLog.txt /r:7 /w:10
    $copyTime = [datetime]::UtcNow - $copyTime 

    Log-Info "Octopus Deployment." -isNewTask $true
    
    [bool]$succeeded = $false;
    [int]$counter = 0;
    $deploymentTime = [datetime]::UtcNow
    do{
        Log-Info "Octopus attempt #$counter  "
        [ScriptBlock]$command = {
             Param
              (
                [string]$componentName,
                [string]$environmentFile,                
                [string]$password
              )

            New-Item d:\Deploy\Logs -type directory -Force
            cd "C:\Program Files\Microsoft Octopus"
            cmd /c kill msiexec* >> d:\Deploy\logs\kill.log
            
            $deployLog = "\\127.0.0.1\d$\Deploy\Logs\$($componentName)DeployLog.log"
            # NOTE: OcotpusCLI throws a fit if the folders do not follow UNC naming convention. 
            cmd /c "C:\Program Files\Microsoft Octopus\octopuscli.exe" -config "\\127.0.0.1\D$\Deploy\$componentName\$environmentFile" -uninstall -adminPassword $password  -OnPendingRebootOperation Ignore
            cmd /c "C:\Program Files\Microsoft Octopus\octopuscli.exe" -config "\\127.0.0.1\D$\Deploy\$componentName\$environmentFile" -install -adminPassword $password  -OnPendingRebootOperation Ignore > $deployLog
        }
        
        $output = Execute-RemoteProcess $machineIpAddress $command $userName $password @($componentName,$environmentFile,$password)

        $deploymentStatus =  Select-String -pattern "Deployment finished successfully." -path "\\$machineIpAddress\d$\Deploy\Logs\$($componentName)DeployLog.log"
        
        if($deploymentStatus -ne $null){
            Log-Info "Deployment succeeded for $componentName."
            $succeeded = $true;
        }else{
            Log-Info "Deployment failed for $componentName. waiting 30 sec and will retry "
        }
        $counter = $counter + 1;
    }while(!$succeeded -and ($counter -le 3))
    $deploymentTime = [datetime]::UtcNow -$deploymentTime 

    Log-Info "Octopus Deployment completed." -isNewTask $true

    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name CopyTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $copyTime.Hours,$copyTime.Minutes,$copyTime.Seconds)
    $ret | Add-Member -type NoteProperty -name DeploymentStatus -value $succeeded;
    $ret | Add-Member -type NoteProperty -name DeploymentTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $deploymentTime.Hours,$deploymentTime.Minutes,$deploymentTime.Seconds)


    return $ret
}

function Install-BinRefresh([string]$dropFullPath, [string]$appRoot)
{ 
       
    [string]$dropPath = "$dropFullPath\." 
                            
    $output = robocopy $dropPath $appRoot /s /mt:64 /XO /r:7 /w:10 /NFL /NDL /NP
    
    Log-Info $output    
}

function Install-FlattenConfig([string]$componentName, [string]$environmentName) {
    [string]$appRoot = "D:\app\$componentName"

    $output = Remove-Item "$appRoot\*.original.config" -Recurse -Force

	if (Test-Path "$appRoot\Web.config") {
		$output += Set-ItemProperty "$appRoot\Web.config" -name IsReadOnly -value $false	
	}
	
	if (Test-Path "$appRoot\DeploymentTools\EnvironmentConfiguration.config") {
		$output += Set-ItemProperty "$appRoot\DeploymentTools\EnvironmentConfiguration.config" -name IsReadOnly -value $false
	}    
    
    $output += D:\App\APTools.standalone\XMLConfigFlattener.exe -dir $appRoot -setenv "environment=$environmentName"

    Log-Info $output
}

function CopyBackCompactDetectorFiles([string]$campaignMTDropPath, [string]$machineIpAddress){
    [dateTime]$timestamp = [DateTime]::Now; Write-Host -BackgroundColor Yellow "[Process:: $timestamp] Copying CopyBackCompactDetectorFiles bits to VM."

    $sourceBaseMetadata = "$campaignMTDropPath\BaseMetadata"
    $sourceTools = "$campaignMTDropPath\Tools"

    [string]$destinationBaseMetadata = "\\$machineIpAddress\d$\BackCompactDetector\BaseMetadata"
    [string]$destinationTools = "\\$machineIpAddress\D$\BackCompactDetector\Tools"

    robocopy $sourceBaseMetadata $destinationBaseMetadata /s /mt:64 /nfl /ndl /copy:d /XO /log+:robocopyLog.txt /r:7 /w:10
    robocopy $sourceTools $destinationTools /s /mt:64 /nfl /ndl /copy:d /XO /log+:robocopyLog.txt /r:7 /w:10
   
}
function Install-FakeAP([string]$dropFullPath,[string]$componentName,[string]$deploymentScript, [string]$machineIpAddress,
    [string]$username, [string]$password, [ScriptBlock]$validate)
{
    [dateTime]$timestamp = [DateTime]::Now; Write-Host -BackgroundColor Yellow "[Process:: $timestamp] Copying bits to VM."
    [string]$destinationPath = "\\$machineIpAddress\d$\Deploy\$componentName"
    #copy build drop to d drive
    $output = New-Item $destinationPath -ItemType directory -force
    [string]$dropPath = "$dropFullPath\." 
    $copyTime = [datetime]::UtcNow
    $output = robocopy "$dropPath" $destinationPath /s /mt:64 /copy:d /XO /log+:robocopyLog.txt  /r:7 /w:10
    $copyTime = [datetime]::UtcNow - $copyTime

    Log-Info "Starting Fake AP deployment for $componentName." -isNewTask $true

    [ScriptBlock]$command = {
            Param
            (
            [string]$componentName,
            [string]$deploymentScript             
            )
            
        $output = New-Item d:\Deploy\Logs -type directory -Force
        if (Test-Path "D:\app\$componentName") 
        {
            $output = cd D:\app\$componentName
            cmd stop.bat ; 
        }
        $output = robocopy D:\Deploy\$componentName D:\app\$componentName /s /mt:64 /copy:d /XO /r:7 /w:10
        
        $output = cd d:\app\$componentName 
        $output = cmd /c $deploymentScript >> d:\Deploy\Logs\$componentName.log 2>&1
    }

    $deploymentTime = [datetime]::UtcNow        
    $output = ""
    $output = Execute-RemoteProcess $machineIpAddress $command $userName $password @($componentName,$deploymentScript)
    $deploymentTime = [datetime]::UtcNow - $deploymentTime 

    Log-Info $output
    
    Log-Info "Validating deployment for $componentName." -isNewTask $true
    [bool]$success = $false 
    $output = Execute-RemoteProcess $machineIpAddress $validate $username $password
    $success = $output
    
    Log-Info "Fake AP deployment for $componentName completed." -isNewTask $true    

    [object]$ret = New-Object System.Object
    #$ret | Add-Member -type NoteProperty -name CopyTime -value $copyTime.ToString("hh\:mm\:ss");
    $ret | Add-Member -type NoteProperty -name CopyTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $copyTime.Hours,$copyTime.Minutes,$copyTime.Seconds)
    $ret | Add-Member -type NoteProperty -name DeploymentStatus -value $success;
    #$ret | Add-Member -type NoteProperty -name DeploymentTime -value $deploymentTime.ToString("hh\:mm\:ss");
    $ret | Add-Member -type NoteProperty -name DeploymentTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $deploymentTime.Hours,$deploymentTime.Minutes,$deploymentTime.Seconds)

    return $ret
}


function Install-FakeAP-RichOutput([string]$dropFullPath,[string]$componentName,[string]$deploymentScript, [string]$machineIpAddress,
    [string]$username, [string]$password, [ScriptBlock]$validate)
{
    [dateTime]$timestamp = [DateTime]::Now; Write-Host -BackgroundColor Yellow "[Process:: $timestamp] Copying bits to VM."
    [string]$destinationPath = "\\$machineIpAddress\d$\Deploy\$componentName"
    #copy build drop to d drive
    $output = New-Item $destinationPath -ItemType directory -force
    [string]$dropPath = "$dropFullPath\." 
    $copyTime = [datetime]::UtcNow
    $output = robocopy "$dropPath" $destinationPath /s /mt:64 /copy:d /XO /log+:robocopyLog.txt  /r:7 /w:10
    $copyTime = [datetime]::UtcNow - $copyTime

    Log-Info "Starting Fake AP deployment for $componentName." -isNewTask $true

    [ScriptBlock]$command = {
            Param
            (
            [string]$componentName,
            [string]$deploymentScript             
            )
            
        $output = New-Item d:\Deploy\Logs -type directory -Force
        if (Test-Path "D:\app\$componentName") 
        {
            $output = cd D:\app\$componentName
            cmd stop.bat ; 
        }
        $output = robocopy D:\Deploy\$componentName D:\app\$componentName /s /mt:64 /copy:d /XO /r:7 /w:10
        
        $output = cd d:\app\$componentName 
        $output = cmd /c $deploymentScript >> d:\Deploy\Logs\$componentName.log 2>&1
    }

    $deploymentTime = [datetime]::UtcNow        
    $output = ""
    $output = Execute-RemoteProcess $machineIpAddress $command $userName $password @($componentName,$deploymentScript)
    $deploymentTime = [datetime]::UtcNow - $deploymentTime 

    Log-Info $output
    
    Log-Info "Validating deployment for $componentName." -isNewTask $true
  
    $output = Execute-RemoteProcess $machineIpAddress $validate $username $password
        
    Log-Info "Fake AP deployment for $componentName completed." -isNewTask $true    

    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name CopyTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $copyTime.Hours,$copyTime.Minutes,$copyTime.Seconds)
    $ret | Add-Member -type NoteProperty -name DeploymentStatus -value $output.Result;
	$ret | Add-Member -type NoteProperty -name DeploymentDetails -value $output.Details;
    $ret | Add-Member -type NoteProperty -name DeploymentTime -value ("{0:D2}:{1:D2}:{2:D2}" -f $deploymentTime.Hours,$deploymentTime.Minutes,$deploymentTime.Seconds)

    return $ret
}

function Start-FakeAP([string]$componentName, [string]$machineIpAddress)
{
    Set-Alias psexec .\psexec.exe 
    $ouput = psexec \\$machineIpAddress -accepteula -d -s -w D:\app\$componentName\ D:\app\$componentName\Start.bat
    return $ouput
}

function Validate-APProcess([string]$processName, [string]$machineIpAddress,[string]$username, [string]$password)
{
    [ScriptBlock]$ProcessIsRunning = 
	{
		Param([string]$prcName)
		Get-Process "$prcName" -ErrorAction SilentlyContinue 
    }
	$validationResult = Execute-RemoteProcess $machineIpAddress $ProcessIsRunning $userName $password @($processName)
	if(!$validationResult) {
    Log-Info "$processName is NOT running"
	} else {
		Log-Info "$processName is running"
	}
	return $output 
}

function Install-AdvertiserMocks([string]$dropBasePath, [string]$machineIpAddress,[string]$username,[string]$password)
{
    [string]$dropFullPath = "$dropBasePath\AdvertiserMocks"
    Log-Info "Copying bits to VM." -isNewTask $true
    [string]$destinationPath = "\\$machineIpAddress\d$\data\AdvertiserMocks\"

    [bool]$newInstall = $true;
    if (Test-Path $destinationPath)
    {
        $newInstall = $false;
        [ScriptBlock]$stopSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:AdvertiserMocks /xml | appcmd  stop site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $stopSite $userName $password
    }

    #copy build drop to d drive
    [string]$dropPath = "$dropFullPath\."
    $output = robocopy $dropPath $destinationPath /s /mt:64 /nfl /ndl /copy:d /XO /log+:robocopyLog.txt  /r:7 /w:10

    $xml = [xml](get-content "$destinationPath\web.config")
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='LogConfigurationPath']").value = "D:\Data\AdvertiserMocks" 
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='MetadataServerName']").value = "." 
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='CampaignMTUrl']").value = "http://localhost:801/CampaignMT/v6/CampaignService.svc"
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='DownloadFileUrl']").value = "http://localhost:1900/DownloadFile.axd?file="
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='DefaultExecuteTaskMTUrl']").value = "http://localhost:801/CampaignMT/v6/ExecuteTaskServiceRest.svc" 
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='DownloadFileUrl']").value = "http://$($machineIpAddress):1900/DownloadFile.axd?file=" 
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='ClientCenterAddress']").value = "https://ClientCenterMT.redmond.corp.microsoft.com:3089/clientcenter/mt" 
    $xml.SelectSingleNode("/configuration/appSettings/add[@key='ReportingShare']").value = "D:\share"
	$xml.SelectSingleNode("/configuration/appSettings/add[@key='EditorialMockDelay']").value = "5000"
    #$xml.SelectSingleNode("/configuration/appSettings/add[@key='MetadataServerName']").value = "." 
    $xml.Save("$destinationPath\web.config")

    # change log location  
    [string]$logConfig = "$($destinationPath)LogConfiguration.config"
    $xml = [xml](get-content $logConfig)
    $nodes = $xml.SelectNodes("/LoggingConfigurationClient/Listeners//Location");
    foreach($n in $nodes){
        $n.InnerText = "d:\Logs\AdverstiserMock"
    }
    $xml.Save($logConfig);

    if ($newInstall)
    {
        [ScriptBlock]$command = {
            $env:path += ";C:\Windows\system32\inetsrv\"
           cd D:\Data\AdvertiserMocks
           
           appcmd add apppool /name:"AdvertiserMocks"
           appcmd set config  -section:system.applicationHost/applicationPools "/[name='AdvertiserMocks'].processModel.identityType:""NetworkService"""  /commit:apphost
           appcmd set config  -section:system.applicationHost/applicationPools "/[name='AdvertiserMocks'].managedRuntimeVersion:""v4.0"""  /commit:apphost
           appcmd set config  -section:system.applicationHost/applicationPools "/[name='AdvertiserMocks'].enable32BitAppOnWin64:""False"""  /commit:apphost
           appcmd add Site /name:"AdvertiserMocks" /bindings:http/*:1900: /physicalPath:D:\Data\AdvertiserMocks
           appcmd set config  -section:system.applicationHost/sites "/+""[name='AdvertiserMocks'].bindings.[protocol='net.tcp',bindingInformation='806:*']""" /commit:apphost
           appcmd set config  -section:system.applicationHost/sites "/[name='AdvertiserMocks'].[path='/'].enabledProtocols:""http,net.tcp"""  /commit:apphost
           appcmd set config  -section:system.applicationHost/sites "/[name='AdvertiserMocks'].applicationDefaults.applicationPool:""AdvertiserMocks"""  /commit:apphost


        }
        $output = Execute-RemoteProcess $machineIpAddress $command $userName $password
    }
    else 
    {
        [ScriptBlock]$startSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:AdvertiserMocks /xml | appcmd start site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $startSite $userName $password

    }
}


function Install-KeyService([string]$dropBasePath, [string]$machineIpAddress,[string]$username,[string]$password)
{
    [string]$dropFullPath = "$dropBasePath\"
    Log-Info "Copying bits to VM." -isNewTask $true
    [string]$destinationPath = "\\$machineIpAddress\d$\data\KeyService\"
    #copy build drop to d drive
    [string]$dropPath = "$dropFullPath\."
    $output = robocopy $dropPath $destinationPath /s /mt:64 /nfl /ndl /copy:d /XO /log+:robocopyLog.txt  /r:7 /w:10

    [ScriptBlock]$command = {
    
       [string]$siteName = "KeyService"
       $env:path += ";C:\Windows\system32\inetsrv\"
       cd D:\Data\$siteName
       
       appcmd add apppool /name:$siteName
       appcmd set config  -section:system.applicationHost/applicationPools "/[name='$siteName'].processModel.identityType:""NetworkService"""  /commit:apphost
       appcmd set config  -section:system.applicationHost/applicationPools "/[name='$siteName'].managedRuntimeVersion:""v4.0"""  /commit:apphost
       appcmd set config  -section:system.applicationHost/applicationPools "/[name='$siteName'].enable32BitAppOnWin64:""True"""  /commit:apphost
       appcmd add Site /name:$siteName /bindings:http/*:9090: /physicalPath:D:\Data\KeyService
       appcmd set config  -section:system.applicationHost/sites "/[name='$siteName'].[path='/'].enabledProtocols:""http,net.tcp"""  /commit:apphost
       appcmd set config  -section:system.applicationHost/sites "/[name='$siteName'].applicationDefaults.applicationPool:""$siteName"""  /commit:apphost
    }
    $output = Execute-RemoteProcess $machineIpAddress $command $userName $password
}

function Install-CRUDService([string]$dropPath, [string]$machineIpAddress, [string]$username, [string]$password)
{
    [dateTime]$timestamp = [DateTime]::Now; Write-Host -BackgroundColor Yellow "[Process:: $timestamp] Copying bits to VM."
    [string]$destinationPath = "\\$machineIpAddress\d$\data\CRUDService\"
    
    #New-Item $destinationPath -ItemType directory -force
    [string]$dropPath = "$dropPath\."

    #Stop Existing Site if is already deployed
    [bool]$newInstall = $true;
    if (Test-Path $destinationPath)
    {
        $newInstall = $false;
        [ScriptBlock]$stopSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:crudservice /xml | appcmd  stop site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $stopSite $userName $password
    }
    
    
    Log-Info "Copy drop folder $dropPath to $destinationPath." -isNewTask $true
    #use robocopy due to better handling of exlclusions
    $output = robocopy.exe $dropPath $destinationPath /MT:64 /s /copy:d /log+:robocopyLog.txt /r:7 /w:10
    
    if ($newInstall)
    {
        #C:\Windows\system32\inetsrv\appcmd add site /name:"CRUDService" /physicalPath:"D:\data\CRUDService"
        $command = { 
            $env:path += ";C:\Windows\system32\inetsrv\"
           cd D:\Data\CRUDService
           
           appcmd add apppool /name:"crudservice"
           appcmd set config  -section:system.applicationHost/applicationPools "/[name='crudservice'].processModel.identityType:""NetworkService"""  /commit:apphost
           appcmd set config  -section:system.applicationHost/applicationPools "/[name='crudservice'].managedRuntimeVersion:""v4.0"""  /commit:apphost
           appcmd add Site /name:"CrudService" /bindings:http/*:8732: /physicalPath:D:\Data\CRUDService
           appcmd set config  -section:system.applicationHost/sites "/+""[name='CrudService'].bindings.[protocol='net.tcp',bindingInformation='8733:*']""" /commit:apphost
           appcmd set config  -section:system.applicationHost/sites "/[name='CrudService'].[path='/'].enabledProtocols:""http,net.tcp"""  /commit:apphost
           appcmd set config  -section:system.applicationHost/sites "/[name='CrudService'].applicationDefaults.applicationPool:""crudservice"""  /commit:apphost
        }
    }
    else 
    {
        [ScriptBlock]$startSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:crudservice /xml | appcmd start site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $startSite $userName $password

    }
    $output = Execute-RemoteProcess $machineIpAddress $command $userName $password   
}

function Install-OnlineUpdateService([string]$dropPath,[string]$machineIpAddress,[string]$username, [string]$password)
{
    Log-Info "Copying Online Update Dump Check Service Bits."
    [string]$destinationPath = "\\$machineIpAddress\d$\data\OnlineUpdateService\"
    
    #New-Item $destinationPath -ItemType directory -Force
    [string]$dropPath = "$dropPath\."   

    #Stop Existing Site if is already deployed
    [bool]$newInstall = $true;
    if (Test-Path $destinationPath)
    {
        $newInstall = $false;
        [ScriptBlock]$stopSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:OnlineUpdateService /xml | appcmd  stop site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $stopSite $userName $password
    }

    Log-info "Copy Drop folder $dropPath to $destinationPath." -isNewTask $true 
    $output = robocopy $dropPath $destinationPath /mt:64 /s /copy:d /log+:robocopyLog.txt /r:7 /w:10

    Copy-Item "$destinationPath\Extractframework\Subscription\EnvironmentPull\EnvPullList_AppsVHD.xml" "$destinationPath\Extractframework\Subscription\EnvironmentPull\EnvPullList.xml" -Force
    Copy-Item "$destinationPath\ExtractFramework\Processes\ConfigOverrides_AppsVHD.xml" "$destinationPath\ExtractFramework\Processes\ConfigOverrides.xml" -Force

    if ($newInstall)
    {
        $command = { 
            $env:path += ";C:\Windows\system32\inetsrv\"
            cd D:\Data\OnlineUpdateService

            appcmd add apppool /name:"OnlineUpdateService" 
            appcmd set config  -section:system.applicationHost/applicationPools "/[name='OnlineUpdateService'].processModel.identityType:""NetworkService"""  /commit:apphost
            appcmd set config  -section:system.applicationHost/applicationPools "/[name='OnlineUpdateService'].managedRuntimeVersion:""v4.0"""  /commit:apphost
            appcmd set config  -section:system.applicationHost/applicationPools "/[name='OnlineUpdateService'].enable32BitAppOnWin64:""True"""  /commit:apphost
            appcmd add Site /name:"OnlineUpdateService" /bindings:http/*:8755: /physicalPath:D:\Data\OnlineUpdateService
            appcmd set config  -section:system.applicationHost/sites "/+""[name='OnlineUpdateService'].bindings.[protocol='net.tcp',bindingInformation='4595:*']""" /commit:apphost
            appcmd set config  -section:system.applicationHost/sites "/[name='OnlineUpdateService'].[path='/'].enabledProtocols:""http,net.tcp""" /commit:apphost
            appcmd set config  -section:system.applicationHost/sites "/[name='OnlineUpdateService'].applicationDefaults.applicationPool:""OnlineUpdateService""" /commit:apphost    

            #Deploy Test Data Bases as part of installation
            cd TestDbs
            cmd /c "DeployTestDBs.cmd"
        }
        $output = Execute-RemoteProcess $machineIpAddress $command $userName $password  
    }
    else 
    {
        [ScriptBlock]$startSite =
        {
            $env:path += ";C:\Windows\system32\inetsrv\"
            appcmd list site /name:OnlineUpdateService /xml | appcmd start site /in       
        }
        $output = Execute-RemoteProcess $machineIpAddress $startSite $userName $password
    }
}
function Get-LatestBuildNumber([string]$dropPathBase){
    [string]$latestFileContent = Get-Content "$dropPathBase\Latest_Release.cmd"
    [string]$version = $latestFileContent.Split("=")[1];
    return "$dropPathBase\$version";
}

function Get-LatestBuildPathFromQBuild([string]$branchName, [string]$logFolder, [boolean]$isAmd64 = $true, [boolean]$getCampaignMTPath = $false){
   
   #TO-D0 make atleast $branchName or $buildPath Mandatory even for CI Runs
   
    if(![String]::IsNullOrEmpty($branchName))
    {
        $qBuildDefinition = $branchName
    }

    # We don't want to modify the global qBuildDefinition
    $_qBuildDefinition = $qBuildDefinition;
    if (!$isAmd64)
    {
        # Transform AdsApps -> AdsApps_x86 for desktop
        $_qBuildDefinition = $qBuildDefinition + "_x86";
    }

    if($getCampaignMTPath -eq $true) 
    {
        if($_qBuildDefinition.ToLower() -eq "adsapps") 
        {
            $_qBuildDefinition = "adsapps~mt_retail_bm"
        }
        elseif ($_qBuildDefinition.ToLower() -eq "adsapps_vnext") 
        {
            $_qBuildDefinition = "adsappsmt_vnext_retail_bm"
        }

    }

    $QBuildUtilityPath = ".\QBuildUtility.exe $_qbuildDefinition"
    $outPut = Invoke-Expression "& $QBuildUtilityPath" 

    [string]$path = $output[1].Split(':')[5] + "\retail";
    if ($isAmd64)
    {
        return $path + "\amd64";
    }
    else
    {
        return $path + "\i386";
    }
}

function Get-LatestCacheV2BuildPathUsingDropService([string]$cacheV2BranchName)
{
	Try
	 {
	   Log-Info "Attempting to call DropService and get the latest cache V2 build"
	   $count =1 
	   $resp = Invoke-WebRequest -UseBasicParsing http://qdrop.binginternal.com/branches/$cacheV2BranchName/drops
	   $path = convertfrom-json $resp.content | ForEach-Object { echo $_.PrimaryLocation.UncPath} | select -First $count	     
	 }
	 catch{
			$dropServiceException = $_.Exception.ToString()
            Log-Info "Attempt to get latest cacheV2 build failed with :: $dropServiceException "            
    }	
	return $path + "\retail\amd64";
}

function Create-SDHistoryHtml([string[]]$output, [string]$logFileFullPath)
{

    $sdHistoryStyle = @{Expression={$_.ChangesetId};;Label="ChangesetId";width="40px"}, `
                @{Expression={$_.Description};Label="Description";width="200px"; Align="Left"}, `
                @{Expression={$_.Author};Label="Owner";width="150px"}

    $maxChangeSetsToDisplay = 10
    $listindex = 0
    $sdchangeSets = New-Object System.Collections.ArrayList
    [bool]$f = $false
    for($index = 2; ($index -lt  $output.Length) -and ($maxChangeSetsToDisplay -gt $listindex) ; $index++)
    { 
      if ($f)
      {
        $splitoutPut =  $outPut[$index] -split ":::"
        $sdchangeSet  | add-member -type NoteProperty -Name Author -Value $splitoutPut[1].Trim()
        $maxChangeSetsToDisplay += 1
        $f = $false
      }
      else
      {
        $splitoutPut =  $outPut[$index] -split ":::"
        $sdchangeSet = new-object PSObject
        $sdchangeSet  | add-member -type NoteProperty -Name ChangesetId -Value $splitoutPut[1].Trim()
        $sdchangeSet  | add-member -type NoteProperty -Name Description -Value $splitoutPut[2].Trim()
        if ($splitoutPut[3])
        {
            $f = $false
            $sdchangeSet  | add-member -type NoteProperty -Name Author -Value $splitoutPut[3].Trim()
        }
        else
        {
            $f = $true
            continue
        }
      } 
      $listindex = $sdchangeSets.Add($sdChangeSet)
     }
    
    $sdHistoryHtml = Get-HtmlTable $sdchangeSets $sdHistoryStyle "Last $maxChangeSetsToDisplay Checkins To SourceDepot (Beta)"  -returnEmptyOnEmptyData "h5"

    $sdHistoryHtml |out-file $logFileFullPath
}

function Log-Info([string]$info, [bool]$emphasize = $false, [bool]$isNewTask = $false){
    [string]$line = $info;
    [dateTime]$timestamp = [DateTime]::Now; 
    
    if($isNewTask) {
        $line = "[Process:: $timestamp] " + $line
    }
    
    $line += [System.Environment]::NewLine;

    if($emphasize) {
        Write-Host -BackgroundColor White -ForegroundColor Black $line        
    }else{
        Write-Host $line
    }

    if($global:commonLogFile) {
        $line|out-file $global:commonLogFile -Append
    }
}

# Parse TRX file and extract 
# <ResultSummary outcome="Error">
#  <Counters total="132" executed="132" passed="86" error="0" failed="37" timeout="0" aborted="0" inconclusive="9" passedButRunAborted="0" notRunnable="0" notExecuted="0" disconnected="0" warning="0" completed="0" inProgress="0" pending="0" />
#
function ParseTrx([string]$filePath){
    # Get the content of the config file and cast it to XML
    $xml = [xml](get-content $filePath)
    #this was the trick I had been looking for
    $root = $xml.get_DocumentElement();
    #Change the Connection String. Add really means "replace" 
    $resultSummary = $root.ResultSummary;
    $timeTaken = [DateTime]::Parse($root.Times.finish) - [DateTime]::Parse($root.Times.start)
    #$timeTaken = $timeTaken.ToString("hh\:mm\:ss") 
    $timeTaken = "{0:D2}:{1:D2}:{2:D2}" -f $timeTaken.hours,$timetaken.Minutes,$timeTaken.Seconds
    
    [string]$outcome = $resultSummary.GetAttribute("outcome");
    [int]$total = $resultSummary.Counters.GetAttribute("total");
    [int]$executed = $resultSummary.Counters.GetAttribute("executed");
    [int]$passed = $resultSummary.Counters.GetAttribute("passed");
    [int]$errors = $resultSummary.Counters.GetAttribute("error");
    [int]$failed = $resultSummary.Counters.GetAttribute("failed");
    [int]$inconclusive = $resultSummary.Counters.GetAttribute("inconclusive");
 
    # dump failures  
    $failures = $root.Results.UnitTestResult | where { $_.GetAttribute("outcome") -ne "Passed" }
    # $failures | fl testName, outcome
    
    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name Status -value $outcome;
    $ret | Add-Member -type NoteProperty -name Failures -value $failures;
    $ret | Add-Member -type NoteProperty -name TrxFile -value $filePath;
    $ret | Add-Member -type NoteProperty -name Total -value $total;
    $ret | Add-Member -type NoteProperty -name Executed -value $executed;
    $ret | Add-Member -type NoteProperty -name Passed -value $passed;
    $ret | Add-Member -type NoteProperty -name Errors -value $errors;
    $ret | Add-Member -type NoteProperty -name Failed -value $failed;
    $ret | Add-Member -type NoteProperty -name Inconclusive -value $inconclusive;
    $ret | Add-Member -type NoteProperty -name TimeTaken -value $timeTaken
    
    return $ret;
}
 
<#
    add host to trusted hosts and  
    Execute replte process with credentials

    .example
    $command = { Get-Process | out-file d:\deploy\logs\process.log }
    $output = Execute-RemoteProcess "galini-ci" $command $userName $password

#>
function Execute-RemoteProcess([string]$computername, [ScriptBlock]$commandScript, [string]$username, [string]$password, [object[]]$argumentList = @(), [switch]$returnJob = $false){
    $output = "";
    [string]$current=(get-item WSMan:\localhost\Client\TrustedHosts -Force).value 
    if(!$current.Contains($computername)){
        if([string]::IsNullOrEmpty){
            $current=$computername
        }else{
            $current+=",$computername"
        }
        $output = set-item WSMan:\localhost\Client\TrustedHosts –value $current -Force
    }

    $secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
    $creds = New-Object System.Management.Automation.PSCredential ($username, $secpasswd)
     
    [bool]$succeeded = $false;
    [int]$counter = 0;
    do{
        Log-Info "Remote Session Attempt #$counter  "
         
        try {
            Log-Info "Executing remote process using session." -isNewTask $true
            #[void]Enable-WSManCredSSP -Role Server -Force
            $output = Connect-WSMan $computername -Credential $creds 
            #[void]Set-Item WSMan:\$computername*\Service\Auth\CredSSP -Value $true -Force
            $s = New-PSSession $computername -Credential $creds -Authentication Credssp

            # $ret = Invoke-Command -ComputerName $computername -ScriptBlock $commandScript -Credential $creds -ArgumentList $argumentList
            $job = Invoke-Command -Session $s -ScriptBlock $commandScript -ArgumentList $argumentList -AsJob
            if($returnJob){
                return $job;
            }

            $waitRes = Wait-Job $job -Timeout 5400 # wait for 30 min

            if($waitRes -eq $null) {
                Log-Info ("Remote Execution timeout reached")
            }

            $ret = Receive-Job $job
            if($job.State -match "Completed"){
                $succeeded = $true;
            }   
                
            Log-Info ("Remote Execution Succeeded. Status is $($succeeded). Job state is $($job.State)") -isNewTask $true
            Log-Info "Output = $ret"
            $output = Remove-PSSession -Session $s
        }catch{
            $error[0]
            Log-Info "Remote Execution Failed. waiting 1 sec and will retry "  -isNewTask $true
            Start-Sleep -Seconds 1
        }
         
        $counter = $counter + 1;
    }while(!$succeeded -and ($counter -le 0))

    #Execute Psexec Fallback if # failures occured
    if (!$succeeded)
    {
        $ret = Execute-RemotePSCommand $computername $commandScript $username $password $argumentList
    }
    
    return $ret;
}

<# 
Execute A Powershell Command Against a Remote Machine. 
#>
function Execute-RemotePSCommand([string]$computername, [ScriptBlock]$commandScript, [string]$username, [string]$password, [object[]]$argumentList = @())
{
    $fallbackLocation = "\\$computerName\d$\Deploy\FallBacks"
    if( !(Test-Path $fallbackLocation) )
    {
       New-Item $fallbackLocation -type directory -Force
    }
    $scriptName = ""
    foreach($i in @(0..1000)) 
    {
        $scriptName = "{0:D4}-fallback.ps1" -f $i 
        if (!(Test-Path $fallbackLocation\$scriptName))
        {
            break
        }
    }

    $command | Out-File $fallbackLocation\$scriptName -width 1000
    Log-Info "Executing psexec fallback $fallbackLocation\$scriptName"  -isNewTask $true
    Set-Alias psexec .\psexec.exe 
    $executeCommand = "powershell -ExecutionPolicy Unrestricted -File $scriptName "
    foreach($argument in $argumentList) 
    {
        $executeCommand = $executeCommand + " $argument"
    }
    Log-Info "Executing Command: cmd /c ""$executeCommand"" via psexec." 
    $ouput = psexec \\$computername -u $username -password $password -h -n 30*60 -w "D:\Deploy\FallBacks" cmd /c ('echo . |' + $executeCommand)
    return $output
}

# recipients should be ";" delimited list 
function Send-Email([string]$domain, [string]$username,[string]$password,[string]$recipients,[string]$htmlBody,[string]$subject )
{
    Write-Host "Inside SendEmail. Domain: $domain. username: $username."
    Write-Host "Inside SendEmail. subject: $subject. recipients: $recipients"
    #Write-Host "Inside SendEmail. htmlBody: $htmlBody"
    
    $smtpServer = "smtphost.redmond.corp.microsoft.com" 
    $smtp = new-object Net.Mail.SmtpClient($smtpServer)        
    $smtp.UseDefaultCredentials = $false
    $smtp.Credentials = new-object Net.NetworkCredential($username, $password, $domain)    
    $message = New-Object System.Net.Mail.MailMessage       
    $message.IsBodyHtml = $true;
    $message.From = "$username@microsoft.com"
    $message.Subject = $subject
    $message.Body = $htmlBody
    
    foreach($recipient in $recipients.split(";", [StringSplitOptions]::RemoveEmptyEntries))
    {
        $message.To.Add($recipient)
    }

    $smtp.Send($message)
}

function Copy-ComponentLogs([string]$componentName,[string]$vmFolder, [string]$logLocation)
{
    $output = robocopy "$logLocation" "$vmFolder\Logs\$componentName" /MT:64 /s /copy:d /log+:robocopyLog.txt /nfl /ndl  /r:7 /w:10
}

#Store Builds to xml file if they do not already exist.
#We do not want to keep adding components to the xml if there is already a build for that component.
function Add-BuildsToXML([string]$buildXmlPath,[string]$component,[string]$componentBuildpath, [string]$componentLocalpath = $null, [bool]$isCacheV2BuildPath = $false)
{
    . .\TfsHelper.ps1
    $xml = [xml](Get-Content "$buildXmlPath")
    $node = $xml.SelectSingleNode("/Summary/Components/Component[@Name='$component']")
    if (!$node)
    {
        $node = $xml.CreateElement("Component")
        [void]$xml.Summary.Components.AppendChild($node)   
    }   
    
    if($isCacheV2BuildPath)
    {
        $qBuildNumber = $componentBuildpath.Split('\')[5]
    }
    else
    {
        $qBuildNumber = $componentBuildpath.Split('\')[6]
    }
	
    $qBuildDefinition = $componentBuildpath.Split('\')[4]
    [void]$node.SetAttribute("Name","$component")
    [void]$node.SetAttribute("Build","$componentBuildpath")
    [void]$node.SetAttribute("BuildDefinition",("$qBuildDefinition"))
    [void]$node.SetAttribute("BuildNumber",("$qBuildNumber"))           

    if(![string]::IsNullOrEmpty($componentLocalpath)){
        [void]$node.SetAttribute("Local","$componentLocalpath")
    }else{
        [void]$node.SetAttribute("Local","$componentBuildpath")
    }
 
    [void]$xml.Save("$buildXmlPath")
}

function Add-RMEUpdatesToXML([string]$buildXmlPath,[string]$componentName, [string]$orderId,[string]$buildPath,[string]$result,[string]$comment)
{
    $xml = [xml](Get-Content -LiteralPath "$buildXmlPath")

    $RMEUpdates = $xml.SelectSingleNode("/Summary/RMEUpdates")
    if (!$RMEUpdates)
    {
        $RMEUpdates = $xml.CreateElement("RMEUpdates")
        [void]$xml.Summary.AppendChild($RMEUpdates)
    }
    
    $RMEUpdate = $xml.CreateElement("RMEUpdate")
    $RMEUpdate.SetAttribute("OrderId",$orderId) 
    $RMEUpdate.SetAttribute("Name",$componentName)
    $RMEUpdate.SetAttribute("BuildPath",$buildPath)
  $RMEUpdate.SetAttribute("UpdateResult", $result)
  $RMEUpdate.SetAttribute("Comment", $comment)
    
    [void]$RMEUpdates.AppendChild($RMEUpdate)
    [void]$xml.Save("$buildXmlPath") 
}

#Store Deployment Status
#This will Serve To initialize  Deployments node. 
function Add-DeploymentResultsToXML([string]$buildXmlPath,[string]$component,[bool]$isGoodDeployment,[string]$copyTime,[string]$deploymentTime, 
    [string]$evtAddress)
{
    $xml = [xml](Get-Content "$buildXmlPath")
    $deployments = $xml.SelectSingleNode("/Summary/Deployments")
    if (!$deployments)
    {
        $deployments = $xml.CreateElement("Deployments")
        [void]$xml.Summary.AppendChild($deployments)
    }
    $deployment = $xml.CreateElement("Deployment")

    [void]$deployment.SetAttribute("Name", "$component")
    if ($isGoodDeployment)
    {
        [void]$deployment.SetAttribute("Status", "Pass")
    }
    else
    {
        [void]$deployment.SetAttribute("Status","Fail") 
    }
    $deployment.SetAttribute("CopyTime",$copyTime)
    $deployment.SetAttribute("DeploymentTime",$deploymentTime)
    $deployment.SetAttribute("EVTEndpoint",$evtAddress) 

    [void]$deployments.AppendChild($deployment)
    [void]$xml.Save("$buildXmlPath") 
}
function Update-XMLWithEvtResults([string]$buildXmlPath)
{
    $xml= [xml](Get-Content "$buildXmlPath")
    foreach ($deployment in $xml.Summary.Deployments.Deployment)
    {
        if (![string]::IsNullOrEmpty($deployment.EVTEndpoint))
        {   
            $result = Get-EvtResults -evtEndpoint $deployment.EVTEndpoint 

            $deployment.SetAttribute("EVTResult","Link")
            <# Commenting out EVT results as most of them fail. 
            if ($result)
            {
                $deployment.SetAttribute("EVTResult","Pass")
            }
            else 
            {
                $deployment.SetAttribute("EVTResult","Fail") 
            }
            #>
        }
        else 
        {
            $deployment.SetAttribute("EVTResult","N\A")
        }
    }
    [void]$xml.Save("$buildXmlPath")
}

function Get-EvtResults([string]$evtEndpoint, [string]$excludeService = $null)
{
    $client = new-object system.Net.WebClient
    Log-Info "Trying EVT check on $evtEndpoint"
    try {
        $responeData = $client.DownloadString($evtEndpoint) 
        $health = [xml]$responeData
        $health = $health.get_DocumentElement()
    } catch {
        $exceptionInfo = $_.Exception.ToString()
        Log-Info "EVT check on $evtEndpoint threw an exception: $exceptionInfo"
        $health = new-object  System.Object | add-member noteproperty Result "false" -passThru 
    }

    if($excludeService) 
    {
        Log-Info "excluding services with $excludeService"
    }
    
    $testResults = $health.TestResults
    foreach ($testResult in $testResults.ChildNodes)
    {
        $serviceName = $testResult.Name.ToLower()
        if(-not($excludeService) -or $serviceName -notlike "*$excludeService*")
        {
            Log-Info "EVT check on service $serviceName"
            if($testResult.Result -eq "false") 
            {
                return $false;
            }
        } 
    }

    return $true

    <#
    if ($health.Result -eq "true"){
        return $true
    } else {
        return $false 
    }
    #>
}
function Add-TestResultsToXML([string]$buildXmlPath,[string]$component,[int]$totalTest,[int]$passedTest,[string]$failedTest,[string]$timeTaken,[string]$mtmId,
                              [string]$teamProject,[string]$TrxFullPath)
{
    $xml = [xml](Get-Content "$buildXmlPath")
    $results = $xml.SelectSingleNode("/Summary/TestResults")
    if (!$results)
    {
        $results = $xml.CreateElement("TestResults")
        [void]$xml.Summary.AppendChild($results)
    }
    $result = $xml.CreateElement("TestResult")
    
    $result.SetAttribute("ComponentName",$component) 
    $result.SetAttribute("Total",$totalTest.ToString()) 
    $result.SetAttribute("Passed",$passedTest.ToString()) 
    $result.SetAttribute("Failed",$failedTest.ToString()) 
    $result.SetAttribute("PassRate",(($passedTest/$totalTest)).ToString("p")) 
    $result.SetAttribute("MTMRunId",$mtmId)
    $result.SetAttribute("TimeTaken",$timeTaken)
    $result.SetAttribute("TeamProject",$teamProject)
    $result.SetAttribute("TrxFullPath",$TrxFullPath)

    [void]$results.AppendChild($result)
    [void]$xml.Save("$buildXmlPath")
}

function Update-TestRerunResultToXML([string]$buildXmlPath,[string]$component,[int]$passedRerun,[string]$failedRerun,[string]$timeTakenRerun,`
                                     [string]$mtmId,[string]$TrxFullPath,[int]$total,[int]$passed,[string]$timeTaken,[string]$teamProject)
{
    $xml = [xml](Get-Content "$buildXmlPath")

    $elementToDelete = $null
    $testResults = $xml.GetElementsByTagName("TestResult")
    foreach ($testResult in $testResults)
    {
        if ($testResult.ComponentName -eq $component)
        {
            $elementToDelete = $testResult

            break
        }
    }

    $results = $xml.SelectSingleNode("/Summary/TestResults")
    if ($results)
    {
        $newPassedNumber = $total - $failedRerun

        $result = $xml.CreateElement("TestResult")
        $result.SetAttribute("ComponentName",$component)
        $result.SetAttribute("Total",$total.ToString())
        $result.SetAttribute("Passed",$newPassedNumber.ToString())
        $result.SetAttribute("Failed",$failedRerun.ToString())
        $result.SetAttribute("PassRate",(($newPassedNumber/$total)).ToString("p"))
        $result.SetAttribute("MTMRunId",$mtmId)
        $result.SetAttribute("TimeTaken",$timeTaken + " + " + $timeTakenRerun)
        $result.SetAttribute("TeamProject",$teamProject)
        $result.SetAttribute("TrxFullPath",$TrxFullPath)

        [void]$results.AppendChild($result)
        #[void]$results.RemoveChild($elementToDelete)
        [void]$xml.Save("$buildXmlPath")
    }
}

function Add-RerunTestResultsToXML([string]$buildXmlPath,[string]$component,[int]$totalTest,[int]$passedTest,[string]$failedTest,[string]$trxFullPath,[string]$timeTaken)
{
    $xml = [xml](Get-Content "$buildXmlPath")
    $rerunResults = $xml.SelectSingleNode("/Summary/RerunTestResults")
    if (!$rerunResults)
    {
        $rerunResults = $xml.CreateElement("RerunTestResults")
        [void]$xml.Summary.AppendChild($rerunResults)
    }
    $result = $xml.CreateElement("RerunTestResult")
    
    $result.SetAttribute("ComponentName",$component)
    $result.SetAttribute("Total",$totalTest.ToString())
    $result.SetAttribute("Passed",$passedTest.ToString())
    $result.SetAttribute("Failed",$failedTest.ToString())
    $result.SetAttribute("TrxFullPath",$trxFullPath)
    $result.SetAttribute("TimeTaken",$timeTaken)

    [void]$rerunResults.AppendChild($result)
    [void]$xml.Save("$buildXmlPath")
}

function Add-ReplicationStatusToXML([string]$server,[string]$buildXmlPath)
{
    $xml = [xml](Get-Content "$buildXmlPath") 
    $repErorrs = $xml.SelectSingleNode("/Summary/ReplicationErrors")
    if (!$repErorrs)
    {
        $repErrors = $xml.CreateElement("ReplicationErrors")
        [void]$xml.Summary.AppendChild($repErrors)
    }
    

    $repErrorArray = Get-ReplicationStatus($server)
    foreach($repError in $repErrorArray)
    {
        $xmlEntry = $xml.CreateElement("ReplicationError")
        $xmlEntry.SetAttribute("Publisher", $repError.PublisherDB)
        $xmlEntry.SetAttribute("Subscriber", $repError.SubscriberDB)
        $xmlEntry.SetAttribute("Publication", $repError.PubName )
        $xmlEntry.SetAttribute("UndistributedCommands", $repError.UndistributedCommands)
        $xmlEntry.SetAttribute("Comments",$repError.Comments ) 
        [void]$repErrors.AppendChild($xmlEntry) 
    }

    [void]$xml.Save("$buildXmlPath")
}

function Get-OverallDeploymentStatus([string]$buildXmlPath)
{
    $xml = [xml](Get-Content "$buildXmlPath")
    foreach($deployment in $xml.Summary.Deployments.Deployment)
    {
        if ($deployment.Status -ne "Pass")
        {
            return $false
        }
    }
    return $true
}
#
# Set-IPAddress "Microsoft Virtual Machine Bus Network Adapter #*" "157.57.109.148"  "255.255.0.0"  "157.57.109.1"  "157.54.14.146"
#
function Set-IPAddress(  
        [string]$networkinterface,    
        [string]$ip,    
        [string]$mask,    
        [string]$gateway,    
        [string]$dns1,    
        [string]$dns2 = $null,    
        [string]$registerDns = "TRUE"    
        )   
{
        #Start writing code here   
        $dns = $dns1   
        if($dns2){$dns ="$dns1,$dns2"}   
        # $index = (gwmi Win32_NetworkAdapter | where {$_.netconnectionid -eq $networkinterface}).InterfaceIndex   
        $index = (gwmi Win32_NetworkAdapter | where {$_.name -like $networkinterface}).InterfaceIndex   
        $NetInterface = (Get-WmiObject Win32_NetworkAdapterConfiguration | where {$_.InterfaceIndex -eq $index})
        $NetInterface.EnableStatic($ip, $mask)   
        $NetInterface.SetGateways($gateway)   
        $NetInterface.SetDNSServerSearchOrder($dns)   
        $NetInterface.SetDynamicDNSRegistration($registerDns)   
}

function Update-RME([string]$buildXmlPath, [string]$release="Apps Continuous Deployment", [string]$environment = "PACE", [string]$buildDropPath, [switch]$updateOnlyCampaign)
{
    
   if($buildDropPath) 
   {
        #build drop path is now supported only for the Campaign Update. 
        $campaignmtdroppath = $buildDropPath
   }   
   else 
   {
    # Overwrite The Builds Just in case a new build has been completed. 
    $xml = [xml](Get-Content "$buildXmlPath")
    $campaignmtdroppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignMT']").Build 
    $campaignapidroppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignAPI']").Build
    $clientcenterdroppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='ClientCenterMT']").Build
    $campaignDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignDB']").Build
    $customerDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CustomerDB']").Build
    $fraudDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='FraudDB']").Build
    $pubCenterDbDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='PublisherDB']").Build
    $campaignUiDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='QBuildCampaignUI']").Build
    $clientCenterUiDropPath = $campaignUiDropPath 
    $clientCenterApiDropPath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CustomerManagementAPI']").Build
   }     
    
   $list = @(
			new-object object | add-member noteproperty ComponentName "AP.AdCore.CampaignMT" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\app\CampaignManagementMT" -passThru	
			#Camgaign MT CDL
			new-object object | add-member noteproperty ComponentName "AP.AdCore.CDL.CampaignMT" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\app\CosmosLogUploader" -passThru
			new-object object | add-member noteproperty ComponentName "AP.AdCore.PPSCosmosLogUploader" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\app\PPSCosmosLogUploader" -passThru
			new-object object | add-member noteproperty ComponentName "AP.AdCore.PhoneProvisioningService" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\app\PhoneProvisioningService" -passThru
			new-object object | add-member noteproperty ComponentName "AP.AdCore.KeywordBISync" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\app\KeywordBISync" -passThru
			new-object object | add-member noteproperty ComponentName "AP.AdCore.CampaignAPIV9Beta" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\v9beta\CampaignManagementAPIV9Beta" -passThru            

            #Reporting API needs to be updated even though it cannot run in CI.
            new-object object | add-member noteproperty ComponentName "ReportingAPIV9" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\App\ReportingAPI\bin" -passThru	
			
            #test update is not required any more as it is updated by Firefly
            #new-object object | add-member noteproperty ComponentName "MTServices.Test" -passThru | add-member noteproperty BuildPath "$campaignMtDropPath\" -passThru
		  )
      
 if(-not $updateOnlyCampaign)  
 {
    $list += @(
                #CCMT
                new-object object | add-member noteproperty ComponentName "ClientCenter MT" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\MT\Service" -passThru
                #Message Center MT
                new-object object | add-member noteproperty ComponentName "AP.Message Center MT" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\MessageManagerMT" -passThru
                
				#NDFS
                new-object object | add-member noteproperty ComponentName "AP.ClientCenter Notification Delivery Service" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\NotificationDeliveryService" -passThru
                #Email Deliver Service
                new-object object | add-member noteproperty ComponentName "AP.ClientCenter Email Delivery Service" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\EmailDeliveryService" -passThru
                #Job Processor
                new-object object | add-member noteproperty ComponentName "AP.ClientCenter Job Processor" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\ClientCenterJobProcessor" -passThru
                #Billing MT
                new-object object | add-member noteproperty ComponentName "AP.ClientCenter Billing MT" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\BillingMT" -passThru
                new-object object | add-member noteproperty ComponentName "AP.ClientCenter BillingMTDog" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\BillingMTDog" -passThru
                #Secure CC API
                new-object object | add-member noteproperty ComponentName "ClientCenter.Api.PCI" -passThru | add-member noteproperty BuildPath "$clientCenterApiDropPath\CCMT\API\v8\Deploy\BranchDeployment\PCI\x64" -passThru
                new-object object | add-member noteproperty ComponentName "ClientCenter.Api.PCI.V9" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\API\v9\Deploy\BranchDeployment\PCI\x64" -passThru
                #ClientCenter API
                new-object object | add-member noteproperty ComponentName "ClientCenter.Api.NonPCI" -passThru | add-member noteproperty BuildPath "$clientCenterApiDropPath\CCMT\API\v8\Deploy\BranchDeployment\NonPCI\x64" -passThru
                new-object object | add-member noteproperty ComponentName "ClientCenter.Api.NonPCI.V9" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\API\v9\Deploy\BranchDeployment\NonPCI\x64" -passThru
                
                #ClientCenter E2E and Component Dogs
                new-object object | add-member noteproperty ComponentName "AP.E2EDog" -passThru | add-member noteproperty BuildPath "$clientCenterApiDropPath\CCMT\App\E2EDog" -passThru
                new-object object | add-member noteproperty ComponentName "AP.ComponentDog" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\CCMT\App\ComponentDog" -passThru
           
				#Client Center test 
				new-object object | add-member noteproperty ComponentName "CustomerServices.Test" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath" -passThru
                                
                #RootUI
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.Root" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\RootUI" -passThru
                #Secure UI
                new-object object | add-member noteproperty ComponentName "ClientCenterUI.Secure" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\SecureUI\OctopusDeployment" -passThru
                #Support UI 
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.Support" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\SupportUI" -passThru
                #Customer UI 
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.Customer" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\CustomerUI" -passThru
                #Old Customer UI 
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.OldCustomer" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\OldCustomerUI" -passThru
                #Static Resources ROOT 
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.StaticResourcesRoot" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\StaticResourcesRoot" -passThru
                #Static Resources ClientCenter 
                new-object object | add-member noteproperty ComponentName "AP.ClientCenterUI.StaticResources" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\ClientCenterResources" -passThru
                ### Campaign UI deployments are promoted by private CI ####
                #CampaignUI
                #new-object object | add-member noteproperty ComponentName "AP.AdCoreUI.Campaign" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\CampaignUI" -passThru
                #Static Resources Campaign 
                #new-object object | add-member noteproperty ComponentName "AP.AdCoreUI.StaticResources" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\CampaignResources" -passThru
                #Tools UI
                #new-object object | add-member noteproperty ComponentName "AP.AdCoreUI.Tools" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\ToolsUI" -passThru
                #Tools UI
                #new-object object | add-member noteproperty ComponentName "AP.AdCoreUI.Research" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\ResearchUI" -passThru

                #AP.AdCoreUI.CampaignWOPIHost  UI
                #new-object object | add-member noteproperty ComponentName "AP.AdCoreUI.CampaignWOPIHost" -passThru | add-member noteproperty BuildPath "$clientCenterDropPath\UI\CampaignUIWopiHost" -passThru
                
                #DB Paths 
                new-object object | add-member noteproperty ComponentName "MetaDataDB_IncrementalAgg.Proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\MetadataDB\Build" -passThru               
                new-object object | add-member noteproperty ComponentName "ClientCenter_IncrementalAgg.proj" -passThru | add-member noteproperty BuildPath "$customerDbDropPath\ClientCenter\DB\Dimensions20\Build" -passThru
                new-object object | add-member noteproperty ComponentName "PartitionedCustomerDB_IncrementalAgg.proj" -passThru | add-member noteproperty BuildPath "$customerDbDropPath\ClientCenter\DB\PartitionedCustomerDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "CustomerDB_IncrementalAgg.proj" -passThru | add-member noteproperty BuildPath "$customerDbDropPath\ClientCenter\DB\CustomerDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "AdvertiserDB_IncrementalAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\CampaignDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "CampaignBulkDBAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\CampaignBulkDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "AdminDBAgg.Proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\StripeAdminDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "AppStagingAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\APPStaging\Build" -passThru
                new-object object | add-member noteproperty ComponentName "ADVPrimaryStagingArea_Agg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\ADVStagingArea\Build" -passThru
                new-object object | add-member noteproperty ComponentName "ADVSecondaryStagingArea_Agg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\ADVStagingArea\Build" -passThru
                new-object object | add-member noteproperty ComponentName "ADVStripedPrimaryStagingArea_Agg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\StripedAdvStagingArea\Build" -passThru
                new-object object | add-member noteproperty ComponentName "ADVStripedSecondaryStagingArea_Agg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\StripedAdvStagingArea\Build" -passThru
                new-object object | add-member noteproperty ComponentName "InstallAdvertiserOptOutService.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\AdvertiserOptOutService\Build" -passThru
                new-object object | add-member noteproperty ComponentName "FraudWorkbenchDB_Agg.proj" -passThru | add-member noteproperty BuildPath "$fraudDbDropPath\Fraud\DB\FraudWorkbenchDb\Build" -passThru
                new-object object | add-member noteproperty ComponentName "NOT_FOR_PRODUCTION_PermittedUserRolesAgg.proj" -passThru | add-member noteproperty BuildPath "$customerDbDropPath\ClientCenter\DB\Dimensions20\Build" -passThru
                new-object object | add-member noteproperty ComponentName "AzurePubDDServiceInstallAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\AzureStagingArea\Build" -passThru
                new-object object | add-member noteproperty ComponentName "MonitoringAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\AutoPilot\Build" -passThru
                new-object object | add-member noteproperty ComponentName "ClientCenter_MonitoringAgg.proj" -passThru | add-member noteproperty BuildPath "$customerDbDropPath\ClientCenter\DB\Dimensions20\Build" -passThru
                new-object object | add-member noteproperty ComponentName "CampaignBulkDB_MonitoringAgg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\CampaignBulkDB\Build" -passThru
                new-object object | add-member noteproperty ComponentName "AzureStagingAreaDB_Agg.proj" -passThru | add-member noteproperty BuildPath "$campaignDbDropPath\Campaign\DB\AzureStagingArea\Build" -passThru
              
            )
	}
    Set-BuildPath $release $environment $list $buildXmlPath
    
}

function Set-BuildsFromRMEToXML([string]$release, [string]$environment,[string]$buildXmlPath)
{
    $rmeAddress = "http://rme/RMEWebService/Service.asmx?WSDL" 
    $rme = New-WebServiceProxy -Uri $rmeAddress -UseDefaultCredential
    $dbComponents = $rme.GetComponents($release,$environment,"Apps-DB")    
    $mtapiComponents = $rme.GetComponents($release,$environment,"Apps-MT") 
    $uiComponents = $rme.GetComponents($release,$environment,"Apps-UI")    
    $rme.Dispose()

    $campaignDb = [string]::Join("\",($dbComponents | where { $_.Name -eq "AdvertiserDB_IncrementalAgg.proj" } ).BuildPath.Split("\")[0..8])
    $customerDb = [string]::Join("\",($dbComponents | where { $_.Name -eq "CustomerDB_IncrementalAgg.proj" } ).BuildPath.Split("\")[0..8])
    $publisherDb = [string]::Join("\",($dbComponents | where { $_.Name -eq "PubCenterDB_IncrementalAgg.proj"} ).BuildPath.Split("\")[0..8])

    $ccmt = [string]::Join("\",($mtapiComponents        | where { $_.Name -eq "ClientCenter MT"} ).BuildPath.Split("\")[0..8])
    $ccapi = [string]::Join("\",($mtapiComponents       | where { $_.Name -eq "ClientCenter.Api.NonPCI"} ).BuildPath.Split("\")[0..8])
    $campaignmt = [string]::Join("\",($mtapiComponents  | where { $_.Name -eq "AP.AdCore.CampaignMT"} ).BuildPath.Split("\")[0..8])
    $campaignapi = [string]::Join("\",($mtapiComponents | where { $_.Name -eq "AP.AdCore.CampaignAPIV9Beta"} ).BuildPath.Split("\")[0..8])

    $ccui = [string]::Join("\",($uiComponents       | where { $_.Name -eq "AP.ClientCenterUI.Customer" } ).BuildPath.Split("\")[0..8])
    $campaignui = [string]::Join("\",($uiComponents | where { $_.Name -eq "AP.AdCoreUI.Campaign"} ).BuildPath.Split("\")[0..8])
    $researchui = [string]::Join("\",($uiComponents | where { $_.Name -eq "AP.AdCoreUI.Research"} ).BuildPath.Split("\")[0..8])

    
    Add-BuildsToXML $buildXmlPath "CustomerDB" $customerDb 
    Add-BuildsToXML $buildXmlPath "CampaignDB" $campaignDb 
    Add-BuildsToXML $buildXmlPath "PublisherDB" $publisherDb
    
    Add-BuildsToXML $buildXmlPath "ClientCenterMT" $ccmt
    Add-BuildsToXML $buildXmlPath "CampaignMT" $campaignmt
    Add-BuildsToXML $buildXmlPath "CampaignAPI" $campaignapi
    Add-BuildsToXML $buildXmlPath "CustomerManagementAPI" $ccapi

    Add-BuildsToXML $buildXmlPath "ClientCenterUI" $ccui
    Add-BuildsToXML $buildXmlPath "CampaignUI" $campaignui
    Add-BuildsToXML $buildXmlPath "ResearchUI" $researchui
}

function CompareBuildPath([string]$path1, [string]$path2)
{
  try
  {
    $p1 = $path1.Split('\')[6].Split('.')[4]
    $p2 = $path2.Split('\')[6].Split('.')[4]
    return $p1.CompareTo($p2)
  }
  catch
  {
    return -1
  }
}

function Set-BuildPath([string]$release, [string]$environment, [object[]] $components,[string]$buildXmlPath)
{
        $rmeAddress = "http://rme/RMEWebService/Service.asmx?WSDL" 
        $rme = New-WebServiceProxy -Uri $rmeAddress -UseDefaultCredential

        if ($rme)
        {
          foreach($component in $components){
            try
            {
              [string]$cName = $component.ComponentName
              $RMEcomponent = $rme.GetComponent($release, $environment, $component.ComponentName)

              if (!$RMEcomponent)
              {
                $result = "Component: $cName was not found in release: $release. $nl"
                write-host $result
                Add-RMEUpdatesToXML $buildXmlPath "N/A" "N/A" "N/A" "False" $result
                continue
              }

              $res = CompareBuildPath $RMEcomponent.BuildPath $component.BuildPath

              if ($res -ge 0)
              {
                $result = "Component: $cName was not updated in RME since it is already up to date. $nl"
                write-host $result
                Add-RMEUpdatesToXML $buildXmlPath $RMEcomponent.Name $RMEcomponent.OrderId $RMEcomponent.BuildPath "False" $result
              }
              else
              {
                $RMEcomponent.BuildPath = $component.BuildPath
                $rme.UpdateComponent($release, $environment, $RMEcomponent.Name, $RMEcomponent)
                $result = [string]::Concat("Component '$cName' was updated to: ", $component.BuildPath, $nl)
                write-host $result
                Add-RMEUpdatesToXML $buildXmlPath $RMEcomponent.Name $RMEcomponent.OrderId $RMEcomponent.BuildPath "True" $result
              }
            }
            catch
            {
              Add-RMEUpdatesToXML $buildXmlPath "N/A" "N/A" "N/A" "False" $error[0]
            }
          }
        }
        else
        {
            try
            {
                write-host "RME object is not valid: $rme"
            }
            catch
            {}
        }

        $rme.Dispose()
}
function Start-RemoteStoppedSites([string]$machineIpAddress,[string]$username, [string]$password)
{
    [ScriptBlock]$command = 
    {
        $env:path += ";C:\Windows\system32\inetsrv\"
        appcmd list site /state:Stopped /xml | appcmd start site /in
        appcmd list apppool /state:Stopped /xml | appcmd start apppool /in 
        Get-Website | Start-Website

        net start Microsoft.Advertising.MessageCenter.MessageManager.MiddleTierService
        net start Microsoft.AdCenter.ClientCenter.Billing.MiddleTierService   
        net start Microsoft.Advertising.ClientCenter.JobProcessor 
        net start Microsoft.AdCenter.ClientCenter.MiddleTierService   
    }

    Execute-RemoteProcess $machineIpAddress $command $userName $password 
}

function Execute-CommandWithRetry([ScriptBlock]$mainScript, [ScriptBlock]$fallbackScript={}, [int]$numberOfRetries=3, [int]$waitInSecondsBeforeRetry=0){
    [bool]$suceeded = $false;
    
    for ($i=1; $i -le $numberOfRetries; $i++){  # not last attempt
        if($i -lt $numberOfRetries){
            try{
                Log-Info "Excute-CommandWithRetry attempt #$i."
                $output = & $mainScript;
                $suceeded = $true;
                Log-Info "Excute-CommandWithRetry attempt #$i suceeded."
                return $suceeded;
            }catch{
                Log-Info "Excute-CommandWithRetry attempt #$i failed."
                $suceeded = $false;
                Start-Sleep -Seconds $waitInSecondsBeforeRetry;
            }

        }else{
            Log-Info "Excute-CommandWithRetry Main sciript didn't succeed. Executing fallback."
            $output = & $fallbackScript;
            $suceeded = $true # assume fallback always works
        }
    }

    return $suceeded;
}

#Process Trx File
#
function Process-TrxFile([string]$baseTrxPath,[string]$component,[string]$teamProject,
    [string]$suiteId,[int]$configId,[string]$envType,[string]$testType,[string]$buildPath,[bool]$officialRun,[bool]$isRerun,[string]$rerunTrxFilePath)
{
    if ($isRerun)
    {
        Log-Info "Process rerun test result $($rerunTrxFilePath) for $($component)" -isNewTask $true
        $trxFilePath = $rerunTrxFilePath
    }
    else
    {
        Log-Info "Searching For Trx in $($baseTrxPath) for $($component)" -isNewTask $true
        $trxFilePath = (Get-ChildItem $baseTrxPath -Filter *.trx -Recurse).FullName
    }

    if ($trxFilePath)
    {
        Log-Info "Beginning to process $($trxFilePath) for $($component)" -isNewTask $true
        $trxResults = ParseTrx $trxFilePath  
        Log-Info "Processed $($trxFilePath)" -isNewTask $true

        if ($officialRun)
        {
            Log-Info "Publishing $($component) results to TFS and Uploading Failed Test to AFA" -isNewTask $true
            [string]$runTitle = "[VHD][$testType][$envType] $component"
            [string]$mtmRunId = Publish-TrxResults $trxFilePath $teamProject $suiteId $configId $runTitle $buildPath $envType $isRerun $rerunTrxFilePath
            Log-Info "Published $($component) results to TFS and RunId is $($mtmRunId)" -isNewTask $true
        }
    }
    else 
    {
        [object]$trxResults = New-Object System.Object
        $trxResults | Add-Member -type NoteProperty -name Status -value "";
        $trxResults | Add-Member -type NoteProperty -name Failures -value "";
        $trxResults | Add-Member -type NoteProperty -name TrxFile -value "";
        $trxResults | Add-Member -type NoteProperty -name Total -value 0;
        $trxResults | Add-Member -type NoteProperty -name Executed -value 0;
        $trxResults | Add-Member -type NoteProperty -name Passed -value -1;
        $trxResults | Add-Member -type NoteProperty -name Errors -value 0;
        $trxResults | Add-Member -type NoteProperty -name Failed -value 0;
        $trxResults | Add-Member -type NoteProperty -name Inconclusive -value 0;
        $trxResults | Add-Member -type NoteProperty -name TimeTaken -value ([dateTime]::Now - [dateTime]::Now)
    }
    [int]$failedTest = ($trxResults.Total - $trxResults.Passed)
    
    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name Failures -value $failedTest;
    $ret | Add-Member -type NoteProperty -name Passed -value $trxResults.Passed;
    $ret | Add-Member -type NoteProperty -name Total -value $trxResults.Total;
    $ret | Add-Member -type NoteProperty -name Component -value $component;
    $ret | Add-Member -type NoteProperty -name MTMRunID -value $mtmRunId;
    $ret | Add-Member -type NoteProperty -name TimeTaken -value $trxResults.TimeTaken;
    $ret | Add-Member -type NoteProperty -name TeamProject -value $teamProject;
    $ret | Add-Member -type NoteProperty -Name TrxFullPath -Value $trxFilePath; 

    return $ret
}
#Publish Trx Results to MTM and AFA
function Publish-TrxResults([string]$baseTrxPath,[string]$teamProject,[int]$suiteId,[int]$configid,[string]$title,[string]$buildPath,[string]$envType,[bool]$isRerun,[string]$rerunTrxFilePath)
{
    #. .\TFSHelper.ps1
    $env:path += ";c:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\;."
    if ($isRerun)
    {
        $trxFilePath = $rerunTrxFilePath
    }
    else
    {
        $trxFilePath = (Get-ChildItem $baseTrxPath -Filter *.trx -Recurse).FullName
    }
    
    #$bld = Get-Build($buildPath); 
    #$buildDefinition = $bld.BuildDefinition.Name
    #$buildNumber = $bld.BuildNumber
    
    $xml = [xml](Get-Content ".\builds.xml")
    $buildNumber = $xml.SelectSingleNode("/Summary/Components/Component").BuildNumber
    if($configid -eq 339)
    {
     $buildDefinition = "AdvertiserServices" + $envType
    }
    else
    {
      $buildDefinition = "AdsAppsFakeBuildDefinition-" + $envType
    }
    
    
    Log-info "Calling TCM Run /Publish /Suiteid:$suiteId /configid:$configid /resultowner:'AdCenter Apps Services Manager' /resultsfile:'$trxFilePath'  /collection:'http://adsgroupvstf:8080/tfs/adsgroup' /teamproject:$teamProject /title:'$title' /build:'$buildNumber' /builddefinition:'$buildDefinition'" -isNewTask $true
    [string]$output = TCM.exe Run /Publish /Suiteid:$suiteId /configid:$configid /resultowner:"AdCenter Apps Services Manager" /resultsfile:"$trxFilePath"  /collection:"http://adsgroupvstf:8080/tfs/adsgroup" /teamproject:$teamProject /title:"$title" /build:"$buildNumber" /builddefinition:"$buildDefinition"
    
    Log-info "buildPath: $buildPath"
    Log-info "Error after TCM: $error[0]"
    Log-info "Output from TCM: $output" 
    $runId = $output.split(":")[1].split(".")[0].Trim()
    Log-info $runId
    
    return $runId
}

function Execute-DBScript([string]$server,[string]$database,[string]$SqlCommandText)
{
    $connection = New-Object System.Data.SqlClient.SqlConnection("Server=$server;Database=$database;Integrated Security=True")
    $connection.Open()
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand ($SqlCommandText, $connection) 
    $datareader = $sqlCmd.ExecuteReader()
    $dt = New-Object System.Data.DataTable
    $dt.Load($datareader)
    $connection.Close()
    return $dt
}

function Execute-DBScriptDataSet([string]$server,[string]$database,[string]$SqlCommandText)
{
    $connection = New-Object System.Data.SqlClient.SqlConnection("Server=$server;Database=$database;Integrated Security=True")
    $connection.Open()
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand ($SqlCommandText, $connection) 
    

    $SqlAdapter = New-object System.Data.SqlClient.SqlDataAdapter 
    $SqlAdapter.SelectCommand = $sqlCmd 
    $DataSet = New-object System.Data.DataSet 
    [void]$SqlAdapter.Fill($DataSet) 

    $connection.Close()
    return $DataSet
}

function Get-ReplicationStatus([string]$server)
{
    return Execute-DBScript -server $server -database "master" -SqlCommandText (get-content .\DBInstall\CheckReplicationStatus.sql)
}

function Get-CustomerUserAccountId([string]$server,[string]$username)
{
    $command=@"
        select TOP 1 u.CustomerId, a.AccountId, u.UserId 
        from [user] u 
        join Account a on u.CustomerId = a.advertisercustomerid and a.LifeCycleStatusId in (29, 30, 31, 34)
        join Customer c on a.AdvertiserCustomerId = c.CustomerId and c.LifeCycleStatusId = 11
        where u.username='$username'
"@
    $result = Execute-DBScript -server $server -database "CustomerDB" -SqlCommandText $command
    
    return $result
    
}


#@{TestPath={"$baseTrxPath\bvt-campaigndb"};Component={"CampaignDB"};TeamProject={"Advertiser"};SuiteId={46308};ConfigId={42};DropPath={$campaignDbDropPath}}
function Get-TrxJobObject([string]$baseTrxPath,[string]$component,[string]$teamProject,
    [string]$suiteId,[int]$configId,[string]$buildPath)
{
    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name TestPath -value $baseTrxPath
    $ret | Add-Member -type NoteProperty -name Component -value $component
    $ret | Add-Member -type NoteProperty -name TeamProject -value $teamProject
    $ret | Add-Member -type NoteProperty -name SuiteId -value $suiteId
    $ret | Add-Member -type NoteProperty -name ConfigId -value $configId
    $ret | Add-Member -type NoteProperty -name DropPath -value $buildPath
    return $ret
}

function Get-NebulaMachineObject([int]$hour,[string]$machineName)
{
    [object]$ret = New-Object System.Object
    $ret | Add-Member -type NoteProperty -name Hour -value $hour
    $ret | Add-Member -type NoteProperty -name MachineName -value $machineName
    return $ret
}

function Check-IsAdrelOnline([string]$vmBuildsXml)
{
    $xml = [xml](Get-Content "$vmBuildsXml") 
    $AdrelAccessible = $false

    $dropPath  = $xml.SelectSingleNode("/Summary/Components/Component[@Name='CampaignDB']").Local
    $node = $xml.SelectSingleNode("/Summary/Components").AdrelAccessible    
   
    if($node)
    {
        $AdrelAccessible = [bool]::Parse($node)
        if($AdrelAccessible -eq $false) 
        {
          return $AdrelAccessible
        }
    }

    
    $AdrelAccessible = Test-Path($dropPath)
    $components = $xml.SelectSingleNode("/Summary/Components")
    if($AdrelAccessible -eq $true)
    {        
        [void]$components.SetAttribute("AdrelAccessible","true")
    }
    else
    {     
        [void]$components.SetAttribute("AdrelAccessible","false")
    }

    [void]$xml.Save("$vmBuildsXml")

    return $AdrelAccessible    
}

function Check-IsMachineAccessible($vmBuildsXml)
{
    $xml = [xml](Get-Content "$vmBuildsXml")
    $vmName = $xml.SelectSingleNode("/Summary/MachineInfo").IpAddress

    Log-Info "Check-MachineAccessibility $($vmName)" -isNewTask $true 
  
    $node = $xml.SelectSingleNode("/Summary/Components").MachineAccessible
    $components = $xml.SelectSingleNode("/Summary/Components")
  
    if($node)
    {
        $MachineAccessible = [bool]::Parse($node)
        if($MachineAccessible -eq $false) 
        {
          return $MachineAccessible
        }
    }
  
#Check Machine Accessibility
       
    try{
        [string]$fileToPing = "\\$($vmName)\d$\testAccess" + (Get-Date -Format "yyyyMMddHHmmssfffff") + ".txt"
        "Check if machine lost trust relationship with the domain." | Out-File $fileToPing   
        $MachineAccessible = $true;
        } 
    catch 
        {
            if($error[0].Exception.Message.Contains("account name is incorrect"))
            {
                Log-Info "Machine $($vmName) lost trust relationship with the domain." -isNewTask $true 
        
            }
            else
            {
              Log-Info $error[0]
            }
        $MachineAccessible = $false;
        }         
    
    if($MachineAccessible -eq $true)
    {        
        [void]$components.SetAttribute("MachineAccessible","true")
    }
    else
    {     
        [void]$components.SetAttribute("MachineAccessible","false")
    }

    [void]$xml.Save("$vmBuildsXml")

    return $MachineAccessible        
}


function Check-ExitDueToEnviromentIssues([string]$vmBuildsXml)
{    
    $isAdrelOnline = Check-IsAdrelOnline "$vmBuildsXml"
    $isMAchineOnline = Check-IsMachineAccessible "$vmBuildsXml"

    return ($isAdrelOnline -and $isMAchineOnline)

}

function UpdateCIDatabase([string]$buildXMLPath)
{
   
    $CIXMLParserCommand = ".\CIXMLParser\CIXmlParser.exe $buildXMLPath"
    $outPut = Invoke-Expression "& $CIXMLParserCommand" 
    $outPut

}

function Get-ScriptDirectory
{
    $Invocation = (Get-Variable MyInvocation -Scope 1).Value;
    if($Invocation.PSScriptRoot)
    {
        $Invocation.PSScriptRoot;
    }
    Elseif($Invocation.MyCommand.Path)
    {
        Split-Path $Invocation.MyCommand.Path
    }
    else
    {
        $Invocation.InvocationName.Substring(0,$Invocation.InvocationName.LastIndexOf("\"));
    }
}

function InstallCert
{
	param([String]$certPath,[String]$certRootStore,[String]$certStore, $pfxPass = $null)
	Write-Host "InstallCert - Enter"
	Try {
		$pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2
		$pfx.import($certPath, $pfxPass, "Exportable,PersistKeySet,MachineKeySet")
	
		$store = new-object System.Security.Cryptography.X509Certificates.X509Store($certStore,$certRootStore)
		$store.open("ReadWrite")
		$store.add($pfx)
		$store.close()
		Write-Host "InstallCert - Success"
	} Catch [system.exception]
	{
		Write-Host "InstallCert - Exception encountered - " + $_
	}
}

function SetNodeAttributeInXML([String]$xmlFilePath, [String]$nodePath, [String]$attributeName, [String]$attributeValue)
{
	try{
		# Load the XML file
		$xml = New-Object System.Xml.XmlDocument
		$xml.Load($xmlFilePath)

        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("ns", $xml.DocumentElement.NamespaceURI)
		
		# Select and get the node
		$node = $xml.DocumentElement.SelectSingleNode($nodePath, $ns)
		
		# Set attribute
		$node.SetAttribute($attributeName, $attributeValue)
		
		# Save XML
		$xml.Save($xmlFilePath)
	}
	catch
	{
		Write-Host "XML change - Exception encountered" 
	}
}
