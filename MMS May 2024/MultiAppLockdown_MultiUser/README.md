# Assigned Access multi-app kiosk (MMS May 2024)

**Disposable Windows lab only.** Review the XML and PowerShell scripts for app paths and policy version before running them. `PrepScript.ps1` creates a local account and enables Windows AutoAdminLogon. That feature stores the generated password **as plaintext in the Winlogon registry**; it is not a production security pattern and may expose the password to anyone with sufficient local access. Do not use a real user's password or run it on a shared/production workstation.

1. In elevated Windows PowerShell, preview the intentional risk: `./PrepScript.ps1 -EnableInsecureAutoLogon -WhatIf`. A plain `./PrepScript.ps1` refuses to change anything.
2. Only on the disposable VM, run `./PrepScript.ps1 -EnableInsecureAutoLogon -Confirm`. Record the VM snapshot so you can roll back after the demo. This does **not** make the password safe.
3. For the `.cmd` Assigned Access launchers, [download PsTools from Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec), inspect the publisher/signature and Microsoft license, and place your own `PsExec.exe` beside the `.cmd` file. No Microsoft binary is redistributed here. The launcher fails if it is missing and starts PowerShell as SYSTEM; its asynchronous return does not prove the policy applied.
4. After the demo, revert the VM snapshot or disable AutoAdminLogon **and** remove `DefaultPassword` from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` on the exact lab VM. Verify the values are gone and review/remove the `MMSKiosk` local account only if this demo created it. Do not run a broad account or registry cleanup on another machine.

The sample profile GUIDs in the XML are Assigned Access profile identifiers, **not** Azure tenant IDs. Replace them only if you deliberately create distinct profiles and update every matching reference. [License](../../LICENSE.md): original scripts MIT, this original guide CC BY 4.0; Microsoft PsExec is excluded.
