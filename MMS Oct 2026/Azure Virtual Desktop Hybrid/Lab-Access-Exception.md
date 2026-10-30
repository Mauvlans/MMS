# Historical demo access exception — sanitized record

A retired lab once granted a single demo principal direct membership in local
Administrators on three explicitly scoped guests. This was an authorized,
temporary elevation exception, **not** an AVD Hybrid prerequisite or a production
baseline. Those retired identities are not the public template's sample hosts.
No grant or removal is authorized by this document for any replacement environment.

Live hostnames, user/domain names and the principal's domain SID have been removed.
The well-known local Administrators SID `S-1-5-32-544` is public Windows metadata,
not a private identity. There is deliberately **no executable revert snippet**:
without the original private approval and exact principal evidence, a generic
removal could revoke the wrong account's access.

## Reuse the process, not the historical grant

Keep a separate private exception record with approver, purpose, expiry, exact
hostname **and** hardware UUID for each guest, the exact principal name/SID, direct
membership evidence, and a rollback owner. Do not put that inventory in this repo.

For an authorized revert, on each independently verified exact guest (never by
name pattern and never on a domain controller), resolve the local group by the
well-known SID. Require exactly one direct member matching **both** the approved
principal name and SID before removing only that member. Read the local SAM back
and record the absence of that exact SID. Stop on any mismatch or ambiguous result;
leave all other Administrators members untouched. Require a fresh sign-out/in when
validating a changed elevation token; disconnect/reconnect does not refresh it.

This sanitized record does not attest that any grant still exists or was revoked.
