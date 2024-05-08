﻿$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

Set-Location $dir
function EnableRSAT {

    Get-WindowsCapability -Name RSAT* -Online | Where-Object State -EQ NotPresent | Add-WindowsCapability –Online
    
}


function EnableKiosk {

$nameSpaceName="root\cimv2\mdm\dmmap"
$className="MDM_AssignedAccess"
$obj = Get-CimInstance -Namespace $namespaceName -ClassName $className
$obj.Configuration = Get-Content -Path "lockdownprofileW11.xml" -Raw

$obj.Configuration = $obj.Configuration -replace "<", "&lt;"
$obj.Configuration = $obj.Configuration -replace ">", "&gt;"

Set-CimInstance -CimInstance $obj

}

#Set Registry 
function SetReg {

$regpath = "HKLM:Software"
$regname = "KioskProfile"
$regvalue = "Enabled"
New-itemproperty –path $regpath –name $regname –PropertyType String –value $regvalue
$verifyValue = Get-itemproperty –path $regpath –name $regname
Write-Host "The $regName named value is set to: " $verifyValue.$regname
}

#Logic
#EnableRSAT
EnableKiosk
#SetReg