param([String]$vmHyperVName, [String]$baseFolderPath)

. .\Tools.ps1
. .\Configuration.ps1

[string]$vmBaseFolder = "$baseFolderPath\$vmHyperVName";
[string]$vmBuildsXml = "$vmBaseFolder\Builds.xml"
$xml = [xml](Get-Content "$vmBuildsXml")

function Install-FakeAP-SimpleService([string]$componentName, [string]$machineIpAddress, [string]$dropSubPath)
{
	
	$droppath = $xml.SelectSingleNode("/Summary/Components/Component[@Name='$componentName']").Local 
    
    $fullPath = $droppath + $dropSubPath
    $componentPath = "D:\app\$componentName"
    $flattening = "D:\app\APTools.standalone\XMLConfigFlattener.exe -dir $componentPath -setenv environment=Redmond-CI"
    
    [ScriptBlock]$command = {}
    $result = Install-FakeAP-RichOutput "$fullPath" "$componentName" $flattening $machineIpAddress $userName $password $command

    Log-Info "AP serice deployment Results: $($result.DeploymentDetails)" -isNewTask $true
}

Install-FakeAP-SimpleService "RulesEngine" $vmHyperVName "\App\RulesEngine"
Install-FakeAP-SimpleService "MapOffersTreeNodesService" $vmHyperVName "\App\MapOffersTreeNodesService"