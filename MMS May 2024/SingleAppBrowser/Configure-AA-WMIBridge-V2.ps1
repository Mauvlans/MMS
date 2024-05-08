$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath

$assignedAccessConfiguration = @"
<?xml version="1.0" encoding="utf-8"?>
<AssignedAccessConfiguration xmlns="http://schemas.microsoft.com/AssignedAccess/2017/config" xmlns:rs5="http://schemas.microsoft.com/AssignedAccess/201810/config" xmlns:v4="http://schemas.microsoft.com/AssignedAccess/2021/config">
  <Profiles>
    <Profile Id="{EDB3036B-780D-487D-A375-69369D8A8F78}">
      <KioskModeApp v4:ClassicAppPath="%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" v4:ClassicAppArguments="--kiosk https://mms2024atmoa.sched.com/ --edge-kiosk-type=fullscreen --kiosk-idle-timeout-minutes=2" />
      <v4:BreakoutSequence Key="Ctrl+A" />
    </Profile>
  </Profiles>
  <Configs>
    <Config>
      <AutoLogonAccount rs5:DisplayName="Love Me Some MMS" />
      <DefaultProfile Id="{EDB3036B-780D-487D-A375-69369D8A8F78}" />
    </Config>
  </Configs>
</AssignedAccessConfiguration>
"@

Set-Location $dir
function EnableRSAT {

    Get-WindowsCapability -Name RSAT* -Online | Where-Object State -EQ NotPresent | Add-WindowsCapability –Online
    
}


function EnableKiosk {

$namespaceName="root\cimv2\mdm\dmmap"
$className="MDM_AssignedAccess"
$obj = Get-CimInstance -Namespace $namespaceName -ClassName $className
$obj.Configuration = [System.Net.WebUtility]::HtmlEncode($assignedAccessConfiguration)
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
