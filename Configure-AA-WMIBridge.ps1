$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

Set-Location $dir

function EnableKiosk {

$nameSpaceName="root\cimv2\mdm\dmmap"
$className="MDM_AssignedAccess"
$obj = Get-CimInstance -Namespace $namespaceName -ClassName $className
$obj.Configuration = Get-Content -Path "lockdownprofile.xml" -Raw

$obj.Configuration = $obj.Configuration -replace "<", "&lt;"
$obj.Configuration = $obj.Configuration -replace ">", "&gt;"

Set-CimInstance -CimInstance $obj

}


#Logic
EnableKiosk

