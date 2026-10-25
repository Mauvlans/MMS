# Demo Guide — Windows 365 for Agents: The Cloud PC as the Secure Runtime for AI + Human Workloads

**Session length:** 60 minutes (MMS format), followed by extended Q&A
**Demos:** 3 · **Total agenda time:** 28 minutes (23 live + 5 debrief)
**Companion deck:** `MMS-W365-Agents-60min.pptx` — **not in this repository; obtain and verify before MMS**

> All product behaviour below is drawn from Microsoft Learn — *Windows 365 for Agents* (Introduction, Architecture overview, Agent session lifecycle, Cloud PC agent pools, Create a provisioning policy (agents), Identity and security, Agent authentication model, MCP tool overview). Verify against the current docs before you present; this space moves fast.

> **Readiness: NO-GO for a live three-demo delivery until the gate below passes.**
>
> - **Verified:** The separate private [MMS agent repository](https://github.com/Mauvlans/MMS-W365A-Agent/tree/mms-demo) contains the deployed client, scripted Notepad task and screen-share viewer. The MMS billing plan and pre-provisioned pool are active with two free sessions; the agent user is assigned. Teams replied and a real `START MMS` acquired a Cloud PC.
> - **Blocked:** The first rehearsal stopped safely at an unexpected Edge profile sign-in prompt before Notepad. Watch live human sign-in failed `AADSTS82018` because the viewer used the agent blueprint as an interactive OIDC client. `CANCEL MMS` invoked EndSession and revoked the viewer ticket; the presenter reports two available sessions again. Takeover and Demo 2's Conditional Access denial/allow remain unverified. The deck and offline recordings are still absent.
> - **Integration:** The partner-session REST contract on [Microsoft Learn](https://learn.microsoft.com/en-us/windows-365/agents/mcp-tool-overview) and the Agent 365 tooling-gateway (ATG) contract in [Microsoft's developer repository](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/api-reference.md) are different paths. This script uses **ATG**; do not mix it with partner REST checkout headers. If the actual client changes to partner REST, replace and rehearse Demo 3 as a unit.

### Go / no-go gate (presenter signs off after a full rehearsal)

- [ ] Put the actual deck at the referenced path; compare slide order, titles, and durations with the run-of-show.
- [ ] Identify the real demo tenant and confirm licenses (Agent 365, Windows Enterprise E3+, Intune, Entra ID P1), billing enabled, agent user, blueprint permissions/consent/inheritance, and a **separate** healthy pre-provisioned pool with free sessions. Do not use the new live-created pool as the fallback.
- [ ] Verify the deployed [MMS Agent 365 client](https://github.com/Mauvlans/MMS-W365A-Agent/blob/mms-demo/MMS-DEMO.md) on a new live turn: Teams reply and MCP `StartSession`/native desktop actions already worked, but the fixed Notepad task and presenter viewer still need a successful rehearsal. Keep the owner and token-refresh method in a private presenter handoff (no secrets in Git).
- [ ] Confirm `Computer.See` and `Computer.Control` are declared, consented, and inherited by the blueprint; connect the viewer and successfully take/release control on a real session.
- [ ] Capture a real denial **and** success from a fresh agent-user token acquisition/resource access in an isolated test condition, with matching sign-in-log evidence; do not assume a checkout attempt alone proves Conditional Access.
- [ ] Run all three demos end-to-end on the presenter rig inside the agenda slots, check in the session, then verify capacity returns. The first Demo 3 attempt was cancelled after Edge sign-in interrupted it; do not use that as a completed run. Record local, token-free MP4 fallbacks and test playback offline.

---

## 0. Before the room fills — global prerequisites

Complete these **at least 48 hours ahead**. Several steps are slow and cannot be rushed live.

| # | Prerequisite | Where | Notes |
|---|---|---|---|
| 1 | Microsoft Intune license | Tenant | Required to create a provisioning policy (agents) |
| 2 | Agent 365 license in the tenant | Tenant | Required for the Intune-created pool path |
| 3 | Active Windows 365 for Agents billing plan | Microsoft Admin Center | Pools are consumption-billed against this plan |
| 4 | Deployed Agent 365 app, blueprint, agent identity, and agent user | Agent 365 / Entra | Assign the agent user to the pool; verify its runtime can invoke `mcp_W365ComputerUse` before the event |
| 5 | **A separate pre-provisioned pool in `Available` state, with free sessions** | Intune admin center | Provisioning takes ~20–30 minutes — create a different pool live and cut to this one |
| 6 | Agent user and isolated CA test condition | Entra / Intune | Pre-capture a real denial/success and verify the log shows the targeted agent user and resource |
| 7 | Working Agent 365 app and screen-share viewer | Your laptop / deployed app | The official [Playground sample](https://github.com/microsoft/windows-365-for-agents/tree/main/W365A-Playground-Agent) is a starting point, **not** an already-running demo; supply a launchable instance and scripted task |
| 8 | Blueprint MCP and ARI permissions | Agent 365 / Entra | `Tools.ListInvoke.All` for the W365 MCP server, plus separate `Computer.See` and `Computer.Control` grants/inheritance for viewing and takeover |
| 9 | Entra sign-in logs pre-filtered to the agent user | Entra admin center | Used to close Demo 2 |

**Speaker rig**
- Two browser profiles side by side: **Admin** (Intune, Entra) and **Agent** (your deployed Agent 365 client and viewer). Copilot Studio/Opal pool creation is a different product path; do not substitute it mid-demo.
- Sign in to every portal in advance; park each on the exact blade you will open.
- ZoomIt installed and tested. The MMS crowd will ask you to use it — use it before they ask.
- Screen resolution 1920×1080. Browser zoom 125% for portal blades, 150% for anything JSON.
- Network fallback: phone hotspot paired and tested.

**Recording insurance (do this — it is the difference between a good session and a bad one)**
Record a clean run of every demo the day before, as a full-screen MP4 with no audio and no visible tokens. Test local playback without conference Wi-Fi. If any live step stalls, narrate over the recording and keep moving. Announce it plainly if you switch — the audience respects it.

**Safety and hygiene**
- Use dedicated MMS identities, pool and app in this shared tenant; never alter the existing Ignite HOL pool or shared billing plan to make an MMS step pass. Treat every live-created pool as additional billable capacity and retire only the exact MMS-created pool after the event.
- Redact tenant IDs, object IDs, and bearer tokens on screen. Blur or use a scratch tenant.
- Never paste a real token into a slide, a chat, or a shared doc.

---

## Run-of-show at a glance

Mirrors the **"60-Minute Agenda"** table slide in the deck.

| Minutes | Segment | Deck slides |
|---|---|---|
| 0–3 | Welcome, attention, speakers | Title, Attention, Speakers |
| 3–8 | Takeaways and demo map | "What You'll Walk Away With," "60-Minute Agenda" |
| 8–18 | Why agents need a computer, architecture, session lifecycle | Section header through "Five Phases of Every Agent Session" |
| 18–28 | **Demo 1 — stand up an agent pool** | Demo 1 header + debrief |
| 28–36 | Design considerations: identity, isolation, governance | Section header through "Isolation and Session Hygiene" |
| 36–46 | **Demo 2 — govern the agent identity** | Demo 2 header + debrief |
| 46–54 | **Demo 3 — watch it work, then take control** | Demo 3 header + debrief |
| 54–58 | Why Cloud PC is the default model, lessons, getting started | Section header through "Getting Started" |
| 58–60 | Transition to Q&A | Q&A |

**If you are running long:** compress the "Getting Started" slide to one callback line and cut straight to Q&A. Never cut Demo 3 — it's the emotional centre of the talk.
**If you are running short:** extend Demo 3 with a second scripted task, or open the MCP `tools/list` output and walk the tool catalogue in more detail.

---

## Demo 1 — Stand up a Cloud PC agent pool
**Deck slide:** "Demo 1 – Stand Up a Cloud PC Agent Pool" · **Time budget:** 8 minutes live + 2 minute debrief (18–28)
**Proves:** Takeaway 1 — a Cloud PC gives agents a managed, Entra-joined, Intune-enrolled execution environment, provisioned by policy rather than by hand.

### Setup checklist
- [ ] Intune admin center open at **Devices → Provision Cloud PCs**
- [ ] At least one Agent 365 agent exists and is ready to assign
- [ ] Second tab already showing a **separate pre-provisioned pool** in `Available` state with at least one free session
- [ ] Billing plan and geography chosen in advance so you do not hunt for them live

### Steps

1. **Frame it (20 sec).** "I am not going to build a VM. I am going to define capacity and let the platform build it."
2. In the Intune admin center, go to **Devices → Provision Cloud PCs → Provisioning policies (Agents) → Create policy**.
3. **General page.** Enter a **Name** (`MMS-Demo-AgentPool`) and an optional **Description**.
   - Choose the **Billing plan**.
   - Set **Always available Cloud PCs count** — valid range is **1 to 200**. Use `2` for the demo.
   - Select a **Geography**.
   - *Talk track:* "Count, region, image, and billing plan are the four properties that define a pool. That is the whole shape of the resource."
   - Select **Next**.
4. **Agents page.** Select **Add Agents**, choose the agent(s) this policy applies to, **Save**, then **Next**.
   - *Talk track:* "This is the first governance gate — Intune decides which agent identities are even allowed to acquire a Cloud PC from this pool."
5. **Image page.** Choose **Gallery image** (or **Custom image** if you have uploaded one via Add device images) → **Select** → **Next**.
   - *Talk track:* "Same image pipeline as Windows 365 Enterprise. Your golden image, your line-of-business apps."
6. **Configuration page.** Choose **Language & region** → **Next**.
7. **Scope tags page.** Add a scope tag if you use delegated admin → **Next**.
   - *Talk track:* "Scope tags are how you keep the finance agent pool out of the hands of the HR admin."
8. **Review + create.** Creating this **second** pool adds billable always-available Cloud PCs on top of `MMS-W365A-Ready`. Only select **Create** if the additional cost and exact-ID cleanup owner have been approved; otherwise stop on the review screen, explain the shape, and cut to the ready pool without creating another one.
9. **Cut to the pre-provisioned pool.** Say it out loud: "Provisioning takes 20 to 30 minutes, so here is one I made earlier."
10. Open the pre-provisioned policy and show:
    - **Pool status** — `Available` (mention the other values: Creating, Updating, Available with warning, Failed, Deleting — status is evaluated **at pool level, not per Cloud PC**).
    - **Session Usage → Available sessions** — the number that actually tells you whether an agent can get a machine right now.
11. Go to **Devices → All devices** and show the provisioned Cloud PCs. Point out that the **device enrollment profile name matches the provisioning policy name**.
    - *Talk track:* "These are Entra-joined and Intune-enrolled from the moment they exist. Every device policy you already wrote applies here."

### Landing line
"You did not manage a device. You managed capacity — and every unit of that capacity arrived already governed."

### Failure modes and fallbacks
| If this happens | Do this |
|---|---|
| Policy creation errors on billing plan | You are missing an active Windows 365 for Agents billing plan — switch to the pre-provisioned pool and say so |
| Pool shows `Failed` | Show the status list on screen and explain remediation; cut to the healthy pool |
| Portal is slow | Switch to the recording; narrate live |

---

## Demo 2 — Govern the agent identity
**Deck slide:** "Demo 2 – Govern the Agent Identity" · **Time budget:** 8 minutes live + 2 minute debrief (36–46)
**Proves:** Takeaway 2 — identity, isolation, governance, and policy enforcement are design decisions you make before you scale.

### Setup checklist
- [ ] Entra admin center open, agent user identity located in advance
- [ ] An isolated agent-user Conditional Access policy in **Report-only** mode, with the targeted resource and endpoint condition already verified
- [ ] A real blocked **and** allowed resource-access/token event recorded during rehearsal, with sign-in logs filtered to the agent **user** and application/resource
- [ ] Healthy demo agent and pool are out of scope of any live policy changes

### Steps

1. **Show the identity (2 min).** In the Entra admin center, open the **agent user identity**.
   - *Talk track:* "This is not a service account someone shared. Each agent uses a dedicated Microsoft Entra agent user identity, separate from human users. Agents never reuse or impersonate user credentials."
   - Show that resource access is **explicitly assigned to the agent identity**, and that lifecycle — creation, disablement, auditing — is managed centrally in Agent 365.
2. **Show the four enforcement gates (1 min).** Narrate against the deck's "Four Enforcement Gates" diagram while you click:
   - Identity control (Entra) → Pool assignment (Intune) → Session establishment (Conditional Access) → Resource access (downstream policy).
3. **Conditional Access on an agent user (2 min).** Open **Entra ID → Conditional Access → Policies** and walk the pre-staged policy. The agent identity and the agent user are *different token subjects*; a policy targeting one does not automatically cover the other.
   - **Assignments → Users, agents, or workload identities → Agents:** select the isolated **agent user (Preview)**, not the ordinary Users picker.
   - **Target resources:** name the actual app/resource whose token request you measured.
   - **Conditions → Agent execution environments (Preview):** include agent-user sessions initiated from endpoints.
   - **Grant:** require device marked compliant; assign a real Intune compliance policy to the test Cloud PC group and verify its evaluated state first.
   - *Talk track:* "The policy is applied to the agent user's token for this resource. The agent identity's own tokens need a separately scoped policy."
4. **Show the rehearsed block (1 min).** Show the saved failed token/resource-access event and the corresponding sign-in-log entry. Do not flip the live policy or claim that replaying an already-issued token/checkout must fail; CA evaluates on token issuance or refresh.
   - *Talk track:* "This specific agent-user request was denied by the policy; the log shows which resource and condition were evaluated."
5. **Show the rehearsed allowed path (1 min).** Show the matched successful event on a compliant Cloud PC or an explicitly excluded test condition; explain the difference.
6. **Close on the sign-in log (1 min).** Show both correlated events and their policy evaluations; do not describe a report-only result as an enforced block.
   - *Talk track:* "Authentication is re-established on every connection. Identity is bound to the session, not the device — and session tokens are cryptographically bound to the device, so they cannot be replayed elsewhere."

### Landing line
"Nothing you just saw is a new security product. It is Conditional Access, Intune, and Entra — pointed at a non-human actor."

### Failure modes and fallbacks
| If this happens | Do this |
|---|---|
| CA policy or token propagation takes time | Use the *previously verified* enforced block and matching sign-in-log entry; never call a report-only evaluation a block |
| Sign-in log lag | Logs can take minutes; use a pre-filtered view captured earlier and say so |
| You cannot show a real block safely | Walk the policy config and show a prior log entry — the config is the teaching moment |

---

## Demo 3 — Watch an agent work, then take control
**Deck slide:** "Demo 3 – Watch an Agent Work, Then Take Control" · **Time budget:** 7 minutes live + 1 minute debrief (46–54)
**Proves:** Takeaways 1 and 3 — the Cloud PC is a real, driveable desktop, and human supervision happens inside the same session.

This is the emotional centre of the session. Do not rush it, and do not talk over the moment the agent starts clicking.

### Setup checklist
- [ ] Pool in `Available` state with at least one free session
- [ ] The deployed Agent 365 app/client is authenticated with an **agent-user bearer token** for the W365 MCP server; its actual `StartSession`, `GetSessionDetails`, `EndSession` tools were discovered and rehearsed
- [ ] A scripted task that is visual and deterministic, with a deliberate pause for the human takeover before completion; the post-handoff finish fits inside 2 minutes
- [ ] The pinned Playground Agent's `/screenshare` viewer works from its **Watch live** Teams card; configure public HTTPS origin, viewer OIDC sign-in, allowed tenant, and a resolvable human owner of the agent instance
- [ ] Separate screen-share token has `Computer.See` and `Computer.Control`; the blueprint has ARI grants and inheritance; neither token is visible on screen

### Steps

1. **Acquire and wait for Ready (up to 1 min, rehearsed).** Have the deployed Agent 365 app call `StartSession` through the `mcp_W365ComputerUse` server on the A365 tooling gateway. Reuse the **same idempotency key** on a timed-out retry, not a new allocation. Poll `GetSessionDetails` every 2–5 seconds until `Ready` (or cut to recording if it fails the rehearsed timeout). The Playground sample captures `screenShareUrl` from the result; confirm its viewer offer actually arrives. Its initial screenshot is best-effort, **not** a substitute for a Ready gate.
   - *Talk track:* "Allocation can take up to 30 seconds. Acquired is not ready; the agent waits before sending input."
2. **Connect (1 min).** Show the actual `mcp_W365ComputerUse` tools from the live A365 SDK client (`initialize` → `tools/list` → `tools/call` is handled by the SDK). The gateway URL and the `Mcp-Session-Id` are client/SDK concerns, not the partner REST `/api/pools/...` and `x-ms-sessionId` headers.
   - *Talk track:* "This is MCP behind Agent 365 identity, blueprint authorization, and the tooling gateway — not an anonymous MCP endpoint any client can simply point at."
3. **Observe (1 min).** Click the sample's **Watch live** card, sign in as the human owner, and open its built-in `/screenshare` page. It redeems a short-lived ticket and connects with an ARI token. The sample's pinned `screenshare-sdk/1.0.0` uses `new ScreenShareViewer({ container, computerUrl, viewerUrl, mode: 'interactive' })`, with a non-empty `api-version` on `computerUrl`. **Do not use the `sessionLink` constructor shown in the generic developer doc with this pinned bundle**; the bundle rejects it.
   - *Talk track:* "Same Cloud PC, same session. The human channel is parallel to the agent channel — there is no second environment to provision."
4. **Act and pause (2 min).** Let the agent start the scripted task, then pause it at the prearranged correction point while it is still running. **Stop talking and let the room watch.**
   - Then narrate the loop: observe → act → observe. Point out that the platform mediates each action, enforces the session identity, applies guardrails, and records what happened.
5. **Take control and finish (1 min).** Call `viewer.takeControl()` at the pause, do something obviously human — type a correction, close a dialog — then `viewer.releaseControl()` and let the agent finish.
   - *Talk track:* "The most recent caller always wins. That is your break-glass path when an agent hits something it should not decide alone."
6. **Release (1 min).** Have the client call `EndSession` through the same A365 MCP server. The release is accepted before asynchronous reset finishes; verify session capacity later rather than promising it returned instantly.
   - *Talk track:* "Channels close, the Cloud PC resets, billing finalises, capacity returns. If the Cloud PC failed a health check during the session, it is quarantined and replaced rather than reused."

### Points to make out loud while it runs
- **No maximum runtime.** Sessions can last seconds or days.
- **Idle timeout is 30 minutes** of no MCP activity. Any MCP call resets the clock — there is no separate lease-renewal API. `get_screen_size` is the minimal reliable heartbeat when the agent is waiting on external work.
- **Checkpoint externally.** In-session state does not survive an unexpected loss. Build the agent to handle a `404` by re-acquiring a fresh Cloud PC and resuming from the last checkpoint.
- **Tokens expire on their own schedule** regardless of session activity — renew transparently.

### Failure modes and fallbacks
| If this happens | Do this |
|---|---|
| `TOKEN_EXPIRED` in the sample viewer | Its current UI ends the view; return to Teams and ask the agent to offer a fresh share. Do not promise a live `updateToken` path that this page does not expose |
| `START_FAILED` | Check the versioned `computerUrl`, viewer CDN, and that the Cloud PC is still acquired; cut to the recording |
| `JOIN_FAILED` | Retry with a fresh token |
| `RECONNECT_FAILED` | `viewer.stop()`, create a new viewer, reconnect with a fresh token |
| `MODE_RESTRICTED` on takeControl | Recreate the viewer in `interactive` mode; also verify `Computer.Control` consent/inheritance if authorization fails |
| Checkout returns no capacity | Show `Available sessions` in Intune and turn it into the capacity-planning point |
| Agent task goes off the rails | Take control live. This is a feature, not a failure — say so |

---

## If time allows — bonus audit walkthrough

Not scripted into the 60-minute run, but keep this ready as a Q&A answer or a bonus close if Demo 3 finishes early. Trace **the exact session from Demo 3** — concrete beats theoretical.

1. **Entra sign-in logs.** Show authentication events for both the human user and the agent user identity — two identities, two log entries, one traceable chain.
2. **Back to Intune.** Open the pool and review **Available sessions** (current headroom) and pool status.
3. **Close on cost.** Consumption-based billing tracks session time rather than provisioned seats; one pool per workload makes chargeback trivial.

*Talk track:* "Who asked, which agent acted, what it did, and what it cost — four questions, one coherent record."

---

## Questions this room will ask — have the answer ready

- **"Can a human sign in to one of these Cloud PCs?"** No. Windows 365 for Agents virtual machines are agent-only and strictly reserved for programmatic agent workloads. Humans observe and co-drive through the screen-share plane, inside the agent's session.
- **"What happens to data left on the machine?"** The Cloud PC is reset after every session. No state carries forward, no credentials persist, no trust carries across workloads.
- **"How is this different from a Windows 365 Enterprise Cloud PC?"** Pool-focused instead of device-focused; shared across agents instead of assigned to a primary user; reset after use instead of persistent; API access instead of the Windows App; consumption-based instead of license-based billing.
- **"Do I have to use Intune?"** For Agent 365 you create a provisioning policy (agents) in Intune. For Copilot Studio computer use, Project Opal, and Researcher you create pools in those portals, and no Intune setup is required.
- **"How long can a session run?"** There is no maximum runtime. Thirty minutes without an MCP call evicts it.
- **"What is the blast radius if an agent is compromised?"** One session on one stateless, reset-on-release Cloud PC, under an identity you can disable centrally in Agent 365 and block with Conditional Access.
- **"What if two demos need the pool at once?"** Pools serve concurrent sessions up to capacity; keep headroom above peak, since a new Cloud PC takes 20–30 minutes to provision on demand.

---

## Reference links and contract boundary

- [What is Windows 365 for Agents](https://learn.microsoft.com/en-us/windows-365/agents/introduction-windows-365-for-agents) · [Agent session lifecycle](https://learn.microsoft.com/en-us/windows-365/agents/agent-session-lifecycle) · [Cloud PC agent pools](https://learn.microsoft.com/en-us/windows-365/agents/cloud-pc-agent-pools) · [Create a provisioning policy (agents)](https://learn.microsoft.com/en-us/windows-365/agents/create-provisioning-policy-agents)
- [Conditional Access for agent users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-agent-user) — distinct from policies targeting agent identities; agent-user targeting and execution-environment condition are Preview.
- [A365 developer getting started](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/getting-started.md) · [ATG API reference](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/api-reference.md) · [ATG authentication](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/authentication.md) · [Playground viewer source](https://github.com/microsoft/windows-365-for-agents/blob/main/W365A-Playground-Agent/src/Screenshare/ScreenshareViewerPage.cs). The generic [screen-sharing guide](https://github.com/microsoft/windows-365-for-agents/blob/main/docs/screen-sharing.md) describes a different constructor: trust the versioned CDN bundle actually loaded by the sample and validate its API before stage use.
- [Microsoft Learn partner-session API overview](https://learn.microsoft.com/en-us/windows-365/agents/mcp-tool-overview) documents **another** checkout/MCP/check-in surface (`/api/pools/...`, `x-ms-sessionId`, `{computerUrl}/mcp`, `baseUrl`/`computerId`). It is **not** the A365 ATG flow scripted above. If your actual client implements this path, verify its availability, token exchange, viewer bundle, and full session on the demo tenant and revise Demo 3 coherently.
- [What's new](https://learn.microsoft.com/en-us/windows-365/agents/whats-new): W365 for Agents GA; compliance CA shipped, while agent-user targeting and endpoint condition remain documented as Preview on the Entra page above.
