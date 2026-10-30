#requires -Version 5.1
<#
.SYNOPSIS
  Opt-in kiosk auto-logon setup for a disposable Windows demo VM only.
.DESCRIPTION
  This intentionally stores the generated local account password as plaintext
  in the Winlogon registry, as Windows AutoAdminLogon requires. Anyone with
  sufficient local access can retrieve it. Never use on a production or
  shared machine; disable auto-logon and remove the lab account afterward.
.EXAMPLE
  .\PrepScript.ps1 -EnableInsecureAutoLogon -WhatIf
.EXAMPLE
  .\PrepScript.ps1 -EnableInsecureAutoLogon -Confirm
#>
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param([switch]$EnableInsecureAutoLogon)

$ErrorActionPreference = 'Stop'
if (-not $EnableInsecureAutoLogon) {
    throw 'Lab-only opt-in required: -EnableInsecureAutoLogon. Plaintext Winlogon storage is not production-safe.'
}
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$user = 'MMSKiosk'
$current = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
if ($current.DefaultUsername -and $current.DefaultUsername -ne $user) {
    throw 'Another auto-logon user is configured. Refusing to overwrite that account.'
}
if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
    throw 'MMSKiosk already exists. Inspect it before changing this machine.'
}
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Create lab-only MMSKiosk account and enable plaintext Windows auto-logon')) { return }

Add-Type -AssemblyName System.Web
$plain = 'MMS' + [System.Web.Security.Membership]::GeneratePassword(8,2)
try {
    $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
    New-LocalUser -Name $user -Password $secure -Description 'Disposable kiosk demo account' -AccountNeverExpires | Out-Null
    Set-ItemProperty -LiteralPath $regPath -Name 'DefaultUsername' -Value $user -Type String
    Set-ItemProperty -LiteralPath $regPath -Name 'DefaultPassword' -Value $plain -Type String
    Set-ItemProperty -LiteralPath $regPath -Name 'AutoAdminLogon' -Value '1' -Type String
    if ((Get-ItemProperty -LiteralPath $regPath).DefaultUsername -ne $user) {
        throw 'Auto-logon readback did not match the demo account; inspect the lab VM.'
    }
    Write-Output 'Lab-only kiosk account created and auto-logon configured. Disable it after the demo.'
} finally {
    $plain = $null
    $secure = $null
}
