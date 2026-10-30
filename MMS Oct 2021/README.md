# Assigned Access multi-app sample (MMS October 2021)

Historical Windows kiosk profile and MDM-bridge PowerShell script. `Configure-AA-WMIBridge.ps1` loads the **included** `MMS_PS_MultiApp_AssignedAccess.xml`; adjust allowed app paths, profile associations, and Windows policy schema for your own disposable test VM before applying. The GUIDs in the XML are profile identifiers, not Azure tenant IDs. Keep matching references consistent if you regenerate them.

To use the `.cmd` launchers, [download PsTools directly from Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec), verify the publisher/signature and follow its license, then place your own `PsExec.exe` beside these scripts. Microsoft does not permit third-party redistribution, so no binary is bundled here. The launcher invokes PowerShell as SYSTEM and does not wait for policy completion; read the actual MDM-bridge state back. `RemoveAAProfile.cmd` is intended only for the same disposable lab VM.

[License](../LICENSE.md): original script code MIT, this original guide CC BY 4.0; Microsoft utilities excluded.
