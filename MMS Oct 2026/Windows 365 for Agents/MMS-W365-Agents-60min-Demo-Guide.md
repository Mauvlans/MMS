# Demo Guide — Windows 365 for Agents: The Cloud PC as the Secure Runtime for AI + Human Workloads

**Session length:** 60 minutes (MMS format), followed by extended Q&A
**Demos:** 3 · **Total demo time:** ~26 minutes
**Companion deck:** `MMS-W365-Agents-60min.pptx`

> All product behaviour below is drawn from Microsoft Learn — *Windows 365 for Agents* (Introduction, Architecture overview, Agent session lifecycle, Cloud PC agent pools, Create a provisioning policy (agents), Identity and security, Agent authentication model, MCP tool overview). Verify against the current docs before you present; this space moves fast.

---

## 0. Before the room fills — global prerequisites

Complete these **at least 48 hours ahead**. Several steps are slow and cannot be rushed live.

| # | Prerequisite | Where | Notes |
|---|---|---|---|
| 1 | Microsoft Intune license | Tenant | Required to create a provisioning policy (agents) |
| 2 | Agent 365 license in the tenant | Tenant | Required for the Intune-created pool path |
| 3 | Active Windows 365 for Agents billing plan | Microsoft Admin Center | Pools are consumption-billed against this plan |
| 4 | At least one agent created in Agent 365 | Agent 365 | You assign agents to the pool in Step 2 of the policy wizard |
| 5 | **A pre-provisioned pool in `Available` state** | Intune admin center | Provisioning takes ~20–30 minutes — you will create one live *and* cut to this one |
| 6 | An agent user identity in Microsoft Entra | Entra admin center | Used for the Conditional Access demo |
| 7 | A partner app or script that can call checkout / MCP | Your laptop | Copilot Studio computer use, Project Opal, or your own client |
| 8 | Entra sign-in logs pre-filtered to the agent identity | Entra admin center | Used to close Demo 2 |

**Speaker rig**
- Two browser profiles side by side: **Admin** (Intune, Entra) and **Maker/Agent** (Copilot Studio or your client app).
- Sign in to every portal in advance; park each on the exact blade you will open.
- ZoomIt installed and tested. The MMS crowd will ask you to use it — use it before they ask.
- Screen resolution 1920×1080. Browser zoom 125% for portal blades, 150% for anything JSON.
- Network fallback: phone hotspot paired and tested.

**Recording insurance (do this — it is the difference between a good session and a bad one)**
Record a clean run of every demo the day before, as a full-screen MP4 with no audio. If any live step stalls, narrate over the recording and keep moving. Announce it plainly if you switch — the audience respects it.

**Safety and hygiene**
- Use a demo tenant, never production.
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
**Deck slide:** "Demo 1 – Stand Up a Cloud PC Agent Pool" · **Time budget:** 8 minutes live + 2 minute debrief
**Proves:** Takeaway 1 — a Cloud PC gives agents a managed, Entra-joined, Intune-enrolled execution environment, provisioned by policy rather than by hand.

### Setup checklist
- [ ] Intune admin center open at **Devices → Provision Cloud PCs**
- [ ] At least one Agent 365 agent exists and is ready to assign
- [ ] Second tab already showing the **pre-provisioned pool** in `Available` state
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
8. **Review + create** → **Create**.
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
**Deck slide:** "Demo 2 – Govern the Agent Identity" · **Time budget:** 10 minutes live + 2 minute debrief
**Proves:** Takeaway 2 — identity, isolation, governance, and policy enforcement are design decisions you make before you scale.

### Setup checklist
- [ ] Entra admin center open, agent user identity located in advance
- [ ] A Conditional Access policy drafted in **Report-only** mode, ready to flip
- [ ] A sign-in log filter saved or bookmarked for the agent identity
- [ ] Your client app ready to attempt a checkout on demand

### Steps

1. **Show the identity (3 min).** In the Entra admin center, open the **agent user identity**.
   - *Talk track:* "This is not a service account someone shared. Each agent uses a dedicated Microsoft Entra agent user identity, separate from human users. Agents never reuse or impersonate user credentials."
   - Show that resource access is **explicitly assigned to the agent identity**, and that lifecycle — creation, disablement, auditing — is managed centrally in Agent 365.
2. **Show the four enforcement gates (2 min).** Narrate against the deck's "Four Enforcement Gates" diagram while you click:
   - Identity control (Entra) → Pool assignment (Intune) → Session establishment (Conditional Access) → Resource access (downstream policy).
3. **Conditional Access on an agent (5 min).** Open **Protection → Conditional Access** and walk your policy scoped to the agent identity:
   - **Users:** the agent user identity.
   - **Grant:** require device compliance.
   - *Talk track:* "Conditional Access treats the agent user identity just like a human user. Access is evaluated in real time on identity and contextual signals, and can be allowed, restricted, or blocked based on risk."
4. **Demonstrate a block (3 min).** With the policy in enforce mode and a deliberately non-compliant condition, trigger a checkout from your client app. Show the failure.
   - *Talk track:* "You can explicitly block risky or unapproved agents. That is the control most agent platforms simply do not have."
5. **Demonstrate the allowed path (2 min).** Correct the condition (or scope the policy back), retry, and show a successful checkout.
6. **Close on the sign-in log.** Filter Entra sign-in logs to the agent identity and show both the block and the success.
   - *Talk track:* "Authentication is re-established on every connection. Identity is bound to the session, not the device — and session tokens are cryptographically bound to the device, so they cannot be replayed elsewhere."

### Landing line
"Nothing you just saw is a new security product. It is Conditional Access, Intune, and Entra — pointed at a non-human actor."

### Failure modes and fallbacks
| If this happens | Do this |
|---|---|
| CA policy takes time to take effect | Have the block pre-triggered and shown from the sign-in log instead of live |
| Sign-in log lag | Logs can take minutes; use a pre-filtered view captured earlier and say so |
| You cannot show a real block safely | Walk the policy config and show a prior log entry — the config is the teaching moment |

---

## Demo 3 — Watch an agent work, then take control
**Deck slide:** "Demo 3 – Watch an Agent Work, Then Take Control" · **Time budget:** 8 minutes live + 2 minute debrief
**Proves:** Takeaways 1 and 3 — the Cloud PC is a real, driveable desktop, and human supervision happens inside the same session.

This is the emotional centre of the session. Do not rush it, and do not talk over the moment the agent starts clicking.

### Setup checklist
- [ ] Pool in `Available` state with at least one free session
- [ ] Client app (Copilot Studio computer use, Project Opal, or your own MCP client) authenticated and ready
- [ ] A scripted task that is visual, deterministic, and finishes in under 3 minutes — e.g. open a browser, sign in to an internal web app with SSO, pull a record, save a file
- [ ] Screen-share viewer page loaded and ready to connect
- [ ] Session token acquired and **not** visible on screen

### Steps

1. **Acquire (1 min).** Trigger checkout from your client app.
   - Endpoint: `POST /api/pools/{poolId}/sessions?api-version=2.0`
   - Pass the **`x-ms-sessionId`** header (a UUID v4) as an **idempotency key** so a retry does not allocate a second session.
   - For an agent-driven session, pass `x-ms-authorization-auxiliary` (the agent identity token) plus `user-object-id` (the agent user ID). Without the auxiliary token you get a `HumanUser` session instead.
   - Show the response fields: **`sessionId`**, **`status`**, **`computerUrl`**, **`screenshareUrl`**. Note `connectivityUrl` may be null — do not depend on it.
   - *Talk track:* "Checkout can take up to 30 seconds while a device is assigned. Design your orchestrator to wait, not to retry aggressively."
2. **Connect (1 min).** Point the MCP client at `{computerUrl}/mcp?api-version=1.0`, including the **`x-ms-computerId`** header.
   - Complete the MCP handshake: `initialize` → `initialized` notification → `tools/list`.
   - Show the returned tool catalogue on screen — desktop interaction (mouse, keyboard, screenshot), window management, command execution, browser automation, UI accessibility.
   - *Talk track:* "This is open Model Context Protocol. Any MCP-capable agent can discover and drive this Cloud PC with no custom integration."
3. **Observe (1 min).** Mount the screen-share viewer against `screenshareUrl` and connect.
   ```
   viewer = new ScreenShareViewer({ container, baseUrl: computerUrl, computerId });
   viewer.connect(bearerToken);
   ```
   - *Talk track:* "Same Cloud PC, same session. The human channel is parallel to the agent channel — there is no second environment to provision."
4. **Act (3 min).** Let the agent run the scripted task. **Stop talking and let the room watch.**
   - Then narrate the loop: observe → act → observe. Point out that the platform mediates each action, enforces the session identity, applies guardrails, and records what happened.
5. **Take control (1 min).** Call `viewer.takeControl()` mid-task, do something obviously human — type a correction, close a dialog — then `viewer.releaseControl()` and let the agent resume.
   - *Talk track:* "The most recent caller always wins. That is your break-glass path when an agent hits something it should not decide alone."
6. **Release (1 min).** Check in explicitly: `DELETE /api/sessions/{sessionId}?api-version=2.0` with the matching `x-ms-sessionId` header. A **204 No Content** means the release was accepted; cleanup completes asynchronously.
   - *Talk track:* "Channels close, the Cloud PC resets, billing finalises, capacity returns. If the Cloud PC failed a health check during the session, it is quarantined and replaced rather than reused."

### Points to make out loud while it runs
- **No maximum runtime.** Sessions can last seconds or days.
- **Idle timeout is 30 minutes** of no MCP activity. Any MCP call resets the clock — there is no separate lease-renewal API. `get_screen_size` is the minimal reliable heartbeat when the agent is waiting on external work.
- **Checkpoint externally.** In-session state does not survive an unexpected loss. Build the agent to handle a `404` by re-acquiring a fresh Cloud PC and resuming from the last checkpoint.
- **Tokens expire on their own schedule** regardless of session activity — renew transparently.

### Failure modes and fallbacks
| If this happens | Do this |
|---|---|
| `TOKEN_EXPIRED` in the viewer | Call `viewer.updateToken(newToken)` — do it live, it is a good teaching moment |
| `START_FAILED` | Check `computerId` and pool registration; cut to the recording |
| `JOIN_FAILED` | Retry with a fresh token |
| `RECONNECT_FAILED` | `viewer.stop()`, create a new viewer, reconnect with a fresh token |
| `MODE_RESTRICTED` on takeControl | The viewer was created in `viewOnly` mode — recreate with `mode: 'interactive'` |
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

## Reference links

- Microsoft Learn — What is Windows 365 for Agents
- Microsoft Learn — Architecture overview
- Microsoft Learn — Agent session lifecycle
- Microsoft Learn — Cloud PC agent pools
- Microsoft Learn — Create a provisioning policy (agents)
- Microsoft Learn — Identity and security in Windows 365 for Agents
- Microsoft Learn — Agent authentication model
- Microsoft Learn — MCP tool overview for Windows 365 for Agents

All live under `learn.microsoft.com/windows-365/agents`.
