

Write-Output "Creating Local User Account"
Add-Type -AssemblyName System.Web
$Secure = "MMS" + ([System.Web.Security.Membership]::GeneratePassword(8,2))
$Password = ConvertTo-SecureString -AsPlainText $Secure -force
$User = "MMSKiosk"
New-LocalUser -Name "MMSKiosk" -Password $Password -Description "Kiosk account for autologin" -AccountNeverExpires

Write-Output "Setting user account to Auto Login"
$RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String 
Set-ItemProperty $RegPath "DefaultUsername" -Value "$User" -type String 
Set-ItemProperty $RegPath "DefaultPassword" -Value "$Secure" -type String

#Write-Output "Applying Assigned Access XML"
#Start-Process -Wait -FilePath "c:\PsExec.exe -accepteula -i -d -s PowerShell.exe -noexit -executionpolicy bypass -file .\Configure-AA-WMIBridge.ps1" 

