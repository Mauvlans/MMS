# MMS AVD Hybrid demo lab — temporary access exception

**Granted:** 2026-10-17 UTC
**Purpose:** Allow demo user `AD\user2` to perform elevation steps on the three self-created AVD Hybrid demonstration hosts. This is **not** an AVD Hybrid prerequisite or a recommended production baseline.
**Scope:** Local Administrators (`S-1-5-32-544`) on `HYBRID-DEMO-01`, `HYBRID-DEMO-02`, and `HYBRID-DEMO-03` only; direct member `AD\user2` (`S-1-5-21-931868896-1911896597-649028394-1645`). No domain-wide or Entra role was granted.
**Verification:** Each host's local Administrators group was read back and showed exactly one direct member with this SID. The existing `AD\Domain Admins`, built-in Administrator, and local bootstrap admin entries were left untouched.
**Expiry/owner:** Remove after the MMS demo; Adam to confirm when the elevation portion is finished. Until then, treat this as an explicit temporary exception. A user already signed in before the grant must fully sign out and back in to receive a new local-admin token; disconnect/reconnect does not suffice.

## Revert on each named host

Run elevated PowerShell on **each of the three exact hosts** (not on a domain controller):

```powershell
$expected = @('HYBRID-DEMO-01','HYBRID-DEMO-02','HYBRID-DEMO-03')
if ($env:COMPUTERNAME -notin $expected) { throw 'Not an MMS AVD Hybrid demo host' }
$group = Get-LocalGroup -SID 'S-1-5-32-544'
$sid = 'S-1-5-21-931868896-1911896597-649028394-1645'
$member = @(Get-LocalGroupMember -Group $group.Name | Where-Object { $_.SID.Value -eq $sid })
if ($member.Count -ne 1 -or $member[0].Name -ne 'AD\user2') { throw 'Exact principal not present; inspect before removing anything' }
Remove-LocalGroupMember -Group $group.Name -Member 'AD\user2'
if (@(Get-LocalGroupMember -Group $group.Name | Where-Object { $_.SID.Value -eq $sid }).Count -ne 0) {
    throw 'Membership still present; inspect host'
}
```

Do not remove by name pattern or touch any other Administrators member. Verify against the local SAM after removal, and update this exception record with the result.
