# Single-app Edge kiosk (MMS May 2024)

Sample Assigned Access profile for an isolated Windows demo VM. The original conference URL is **not** a default; provide your own absolute HTTPS kiosk URL. The PowerShell script validates it and XML-escapes it before updating the MDM bridge. Review Edge location, profile GUID references, account behavior, and breakout keys for your Windows version before applying.

From an elevated Windows Command Prompt on the disposable VM:

```cmd
set "MMS_KIOSK_URL=https://your-own-event.example/"
ApplyAAProfile-V2.cmd
```

The launcher requires **your own** `PsExec.exe` beside it: [download PsTools from Microsoft](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec), verify the publisher/signature and follow Microsoft's terms. PsExec is **not bundled** here. The launcher starts PowerShell as SYSTEM and returns asynchronously; read back the Assigned Access policy before calling it successful. Use `RemoveAAProfile.cmd` and verify on the same lab VM when finished; do not run either against a production endpoint.

[License](../../LICENSE.md): original script code MIT, this original guide CC BY 4.0; Microsoft utilities and third-party imagery are excluded.
