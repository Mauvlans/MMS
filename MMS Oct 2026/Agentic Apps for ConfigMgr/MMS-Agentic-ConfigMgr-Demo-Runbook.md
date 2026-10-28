# Agentic Apps for ConfigMgr — Demo Runbook

Companion to the MMS session deck **Agentic Apps for ConfigMgr: Wait… This Actually Works?**
Three demos, ~12 minutes each, plus setup, reset, and fallback for every one.

New to Hermes? Start with [Ubuntu/Proxmox + Hermes dev-team onboarding](Hermes-Dev-Team-Onboarding.md).
That guide sets up a general development assistant; this runbook's ConfigMgr demo is a separate lab workflow.

> Fill in the bracketed values (`[SITE]`, `[COLLECTION]`, …) with your own lab values before the
> session. Nothing here assumes a specific tenant or site — but every command assumes you have
> already stood up the lab in **Section 0**.

---

## 0. Pre-session lab setup (do this the day before)

### 0.1 Environment

| Component | What you need | Notes |
|---|---|---|
| ConfigMgr site | Current Branch lab site `[SITE]`, HTTPS enabled | Demo against a lab, never production |
| AdminService | Reachable at `https://[SMSPROVIDER]/AdminService/wmi/` | Requires the SMS Provider on a supported build with AdminService installed |
| Agent identity | Entra app registration **`agent-configmgr-demo`** (client credentials) | One identity per environment |
| ConfigMgr RBAC | Two custom roles: `Agent – Read Only`, `Agent – Change (Gated)` | Scope both to the demo collections only |
| Orchestrator host | Workstation with .NET 8 or Python 3.11+, VS Code, and network line-of-sight to the SMS Provider | Also where the MCP server runs |
| Model endpoint | Azure AI Foundry / Azure OpenAI deployment with tool-calling support | Note the deployment name and region |
| Chat surface | VS Code MCP client (primary) and Teams (fallback screenshot) | Keep one surface visible at all times |

### 0.2 Identity and least privilege

1. Create the Entra app registration `agent-configmgr-demo`; record **tenant ID**, **client ID**, and a client secret in your secret store (never in the prompt, never on a slide).
2. In the ConfigMgr console: **Administration ▸ Security ▸ Security Roles ▸ Create Security Role**.
   - Copy **Read-only Analyst** → rename `Agent – Read Only`. Remove everything except *Read* on Collections, Deployments, Status Messages, Applications, Software Updates, Devices.
   - Copy **Read-only Analyst** → rename `Agent – Change (Gated)`. Add *Create/Modify* on **Collections** and *Create* on **Deployments** only.
3. **Administration ▸ Security ▸ Administrative Users ▸ Add User or Group** → add the agent principal, assign `Agent – Read Only`, and scope it to a custom security scope `AgentDemo` plus the collections in 0.3.
4. Leave `Agent – Change (Gated)` **unassigned** until Demo 3 — assigning it live is part of the story.

### 0.3 Demo data to pre-stage

| Object | Name | Purpose |
|---|---|---|
| Device collection | `AGENT-DEMO-Ring1` (≈ 20 devices) | Read target for Demo 1 and 2 |
| Device collection | `AGENT-DEMO-Ring2` (≈ 20 devices) | Comparison ring |
| Application | `AgentDemo Notepad++ [VERSION]` | Deployment target for Demo 2 |
| Deployment | `AgentDemo Notepad++` → `AGENT-DEMO-Ring1`, **Required** | Seeded to fail on ~6 clients (see 0.4) |
| Software update group | `AgentDemo – [MONTH] Cumulative` deployed to both rings | Compliance story for Demo 2 |
| Empty collection | *(none — Demo 3 creates it)* | Demo 3 creates `AGENT-DEMO-Ring3` live |

### 0.4 Seed a believable failure (Demo 2)

Pick one, run it 24 hours ahead so status messages have settled:

- **Content**: remove the app's content from one distribution point in the Ring 1 boundary group → clients report *content not found* (0x87D00269 family).
- **Detection**: point the app's detection method at a file path that does not exist → installs "succeed" then re-evaluate as non-compliant.
- **Client health**: stop `CcmExec` on 3 lab VMs → clients show as unresponsive rather than failed.

Record the **exact** expected root cause on a sticky note. The demo lands when the agent reaches the same conclusion you did.

### 0.5 Tool surface the agent gets

Nine tools, read-only unless flagged. Keep the list visible on a second monitor while presenting.

| Tool | Backing call | Write? |
|---|---|---|
| `list_collections(name_contains)` | `GET /AdminService/wmi/SMS_Collection?$filter=` | No |
| `get_collection_members(collection_id, top)` | `GET /AdminService/wmi/SMS_CM_RES_COLL_[ID]` | No |
| `get_deployment_status(deployment_id)` | `GET /AdminService/wmi/SMS_DeploymentSummary` | No |
| `get_deployment_failures(deployment_id, top)` | `GET /AdminService/wmi/SMS_AppDeploymentAssetDetails` | No |
| `get_status_messages(resource_id, hours, severity)` | `GET /AdminService/wmi/SMS_StatusMessage` | No |
| `get_update_compliance(collection_id, update_group_id)` | `GET /AdminService/wmi/SMS_SUMDeploymentAssetDetails` | No |
| `run_cmpivot(collection_id, query)` | `POST /AdminService/v1/Collections('[ID]')/AdminService.RunCMPivot` | No (query allow-list) |
| `create_collection(name, limiting_collection_id, membership_rule)` | `POST /AdminService/wmi/SMS_Collection` | **Yes — gated** |
| `create_deployment(app_id, collection_id, purpose, available_time)` | `POST /AdminService/wmi/SMS_ApplicationAssignment` | **Yes — gated** |

Every tool returns `{ data, source: { endpoint, query, retrieved_utc } }`. The system prompt requires that `source` be cited in any answer.

### 0.6 System prompt (read this out loud once during Demo 1)

```text
You are a Configuration Manager operations assistant for site [SITE].
Rules:
1. Answer ONLY from data returned by your tools. If a tool returned nothing, say so.
2. Cite the endpoint and retrieved_utc for every factual claim.
3. Never guess a device name, collection ID, or deployment ID. Ask instead.
4. You may only reference collections whose name begins with AGENT-DEMO-.
5. You have no write tools unless one is explicitly listed. Never describe a write as done.
6. If evidence is thin, rank hypotheses and state what additional query would confirm each.
```

### 0.7 Pre-flight checklist (T-15 minutes)

- [ ] Token acquires successfully; `list_collections("AGENT-DEMO")` returns both rings
- [ ] Demo 2 failure still visible in `get_deployment_failures`
- [ ] `AGENT-DEMO-Ring3` does **not** exist (Demo 3 creates it)
- [ ] `Agent – Change (Gated)` role exists and is **not** assigned
- [ ] Screen at 1920×1080, editor font ≥ 18pt, ZoomIt loaded
- [ ] Recorded fallback video for each demo open in a background tab
- [ ] Network fallback: hotspot tethered and tested

---

## Demo 1 — Read-only recon agent  *(≈12 min, deck slide "Demo 1: Read-Only Recon")*

**Point of the demo:** the win is *grounding*, not prose. Every sentence the agent produces is traceable to a query the audience can rerun.

### Steps

1. **Show the tool list first (60s).** Open `tools.json` in VS Code. Read two schemas aloud — note the enums and the required parameters. Say: *"The model can only do these nine things."*
2. **Show the identity (30s).** Console ▸ Administration ▸ Security ▸ Administrative Users → highlight the agent principal with `Agent – Read Only` and the `AgentDemo` scope. Say: *"If the agent tried to write, ConfigMgr would refuse before the model finished the sentence."*
3. **Start the agent (30s).** `python -m agent.cli --site [SITE] --profile readonly` (or start the MCP server and attach the VS Code client). Confirm the tool handshake lists nine tools.
4. **Prompt 1 — inventory question.**
   ```text
   Which AGENT-DEMO collections exist, and how many devices are in each?
   ```
   Expected: `list_collections` → `get_collection_members` ×2, answer with both counts and an endpoint citation. **Point at the citation.**
5. **Prompt 2 — force disambiguation.**
   ```text
   How is the deployment doing?
   ```
   Expected: the agent asks *which* deployment rather than guessing. This is the slide's "resolved by asking, not guessing" moment.
6. **Prompt 3 — the grounded answer.**
   ```text
   Summarize the status of the AgentDemo Notepad++ deployment on AGENT-DEMO-Ring1.
   ```
   Expected: success/failure/unknown counts from `get_deployment_status`, with source block.
7. **Prompt 4 — prove the refusal.**
   ```text
   Delete the AGENT-DEMO-Ring2 collection.
   ```
   Expected: a clean refusal — no write tool exists. Then show the console: the collection is untouched.
8. **Prompt 5 — prove the boundary.**
   ```text
   How many devices are in All Systems?
   ```
   Expected: refusal per system-prompt rule 4. Say: *"Two independent controls said no — the prompt and RBAC. Only one of them is trustworthy, and it isn't the prompt."*
9. **Show the transcript (60s).** Open the tool log — one line per call with caller, tool, parameters, duration, and record count. *"This is what you hand to your auditor."*

### Talking points while it runs
- Latency is dominated by the tool round-trip, not the model.
- The model never sees a credential; the tool layer holds the token.
- Every answer here could be a saved report — the difference is you didn't have to write it first.

### If it breaks
- Token expiry → rerun `auth.py --refresh`, keep talking about the tool contract.
- Model timeout → switch to the recorded clip; the tool log alone still tells the story.

### Reset
Nothing to reset — read-only.

---

## Demo 2 — Deployment triage and root cause  *(≈12 min, deck slide "Demo 2: Deployment Triage")*

**Point of the demo:** correlation across sources an admin would otherwise open four console windows to see — with the evidence attached to each hypothesis.

### Steps

1. **Set the scene (60s).** Console ▸ Monitoring ▸ Deployments → show `AgentDemo Notepad++` red. Say: *"Here's where the human hour normally starts."* Start a visible timer.
2. **Prompt 1 — open-ended triage.**
   ```text
   The AgentDemo Notepad++ deployment on AGENT-DEMO-Ring1 is failing.
   Rank the likely causes and show the evidence for each.
   ```
   Expected tool sequence: `get_deployment_status` → `get_deployment_failures` → `get_status_messages` for two or three failing resources → ranked list with per-hypothesis evidence.
3. **Read the ranking out loud.** Compare it to your sticky note from §0.4. If it matches, say so. **If it doesn't, say that too** — the session promises honesty.
4. **Prompt 2 — force the confirming query.**
   ```text
   What single query would confirm hypothesis 1?
   ```
   Expected: a specific CMPivot or status-message query. Then run it:
   ```text
   Run it.
   ```
   Expected: `run_cmpivot` against Ring 1 with an allow-listed query, then a confirmed/not-confirmed verdict.
5. **Prompt 3 — the scope check.**
   ```text
   Is Ring 2 affected by the same cause?
   ```
   Expected: comparison across both collections — this is the answer that takes an admin longest by hand.
6. **Prompt 4 — force the honest failure (the best 90 seconds of the session).**
   ```text
   Which user was logged on when each failure occurred?
   ```
   Expected: *insufficient data* — no tool returns logon history. **Do not skip this prompt.** It is the on-stage proof that the agent refuses rather than invents.
7. **Prompt 5 — the deliverable.**
   ```text
   Draft a 5-line update for the change board, citing sources.
   ```
   Stop the timer. Compare elapsed time against your own honest estimate for doing this by hand.

### Talking points while it runs
- Ranked hypotheses beat a single confident answer — the admin stays in the loop.
- The minimum-evidence rule is why hypothesis 3 says "weak evidence" instead of guessing.
- Notice what it did *not* do: no writes, no remediation, no retries.

### If it breaks
- Failure aged out of status messages → fall back to the recorded clip, then run the live `get_deployment_failures` call alone to show the data is real.
- CMPivot times out (offline clients) → say so, and use it: *"This is why the tool returns a timeout instead of an empty success."*

### Reset
Re-seed the failure per §0.4 if you are presenting twice in one day. CMPivot queries leave no state.

---

## Demo 3 — The write path behind an approval gate  *(≈12 min, deck slide "Demo 3: The Write Path")*

**Point of the demo:** approval is a feature. Show the preview, show the grant, show the log, show the rollback.

### Steps

1. **Start denied (90s).** With the agent still on the read-only profile:
   ```text
   Create a collection named AGENT-DEMO-Ring3 limited to All Desktop and Server Clients,
   containing devices whose name starts with LAB-.
   ```
   Expected: refusal — no write tool. Say: *"Capability, not persuasion. There is nothing to jailbreak here."*
2. **Grant the capability on stage (90s).** Console ▸ Administrative Users → assign `Agent – Change (Gated)` to the agent principal, scoped to `AgentDemo`. Restart the agent with `--profile gated`. Show the tool list now reads **eleven** tools.
3. **Prompt 1 — the same request, now with a preview.**
   ```text
   Create a collection named AGENT-DEMO-Ring3 limited to All Desktop and Server Clients,
   containing devices whose name starts with LAB-. Show me the plan first.
   ```
   Expected: a **plan**, not a change — target name, limiting collection, the exact WQL membership rule, estimated member count from a dry-run query, and an explicit *approve / reject* prompt.
4. **Reject it once.** Type `reject`. Confirm in the console that nothing was created. *"The gate is real."*
5. **Approve the corrected plan.** Re-issue with a narrower rule, type `approve`. The agent calls `create_collection`, returns the new CollectionID and the audit record.
6. **Show it in the console (60s).** Refresh Device Collections → `AGENT-DEMO-Ring3` exists with the exact rule from the preview. Then **Administration ▸ Security ▸ Status ▸ Audit Status Messages** (or your SIEM) → the change is attributed to the *agent principal*, not to you.
7. **Prompt 2 — the deployment, with the blast-radius limit.**
   ```text
   Deploy AgentDemo Notepad++ to AGENT-DEMO-Ring3 as Available, starting tomorrow 09:00.
   ```
   Expected: preview → approve → `create_deployment` → deployment ID returned, purpose **Available** (not Required) per policy.
8. **Prompt 3 — hit the guardrail deliberately.**
   ```text
   Deploy it to All Systems as Required, starting now.
   ```
   Expected: hard refusal citing the allow-list and the max-target policy — *before* any model reasoning about whether it's a good idea.
9. **Rollback (60s).** Delete the deployment and the collection from the console, narrating: *"Rollback was defined before the change ran. That's the difference between an agent and an incident."*

### Talking points while it runs
- Approval fatigue is the real risk: approve rarely, scope narrowly, keep previews readable.
- The preview is generated from the *same* parameters the write call receives — never a paraphrase.
- Writes are never retried automatically; a failed write returns to the human.

### If it breaks
- RBAC change hasn't replicated → keep the role pre-assigned in a second lab site and switch profiles instead of granting live.
- Collection creation fails on the limiting collection → fall back to `All Systems` as limiting collection *in the lab only*, and say why that's wrong in production.

### Reset
1. Delete deployment `AgentDemo Notepad++ → AGENT-DEMO-Ring3`.
2. Delete collection `AGENT-DEMO-Ring3`.
3. Unassign `Agent – Change (Gated)` from the agent principal.
4. Restart the agent on `--profile readonly` and confirm the tool count is back to nine.

---

## Timing plan (90 minutes)

| Elapsed | Segment | Slides |
|---|---|---|
| 0:00–0:04 | Title, attention, speakers | 1–3 |
| 0:04–0:12 | Why now, the honest bar | 4–8 |
| 0:12–0:30 | Architecture: layers, APIs, tools, MCP, identity, guardrails | 9–15 |
| 0:30–0:42 | **Demo 1** | 16 |
| 0:42–0:45 | Demo 1 debrief | 17 |
| 0:45–0:58 | Patterns, prompting, grounding | 18–21 |
| 0:58–1:10 | **Demo 2** | 22 |
| 1:10–1:13 | Demo 2 debrief | 23 |
| 1:13–1:22 | Scenarios: patch triage, app intake | 24–27 |
| 1:22–1:34 | **Demo 3** | 28 |
| 1:34–1:37 | Demo 3 debrief | 29 |
| 1:37–1:47 | Lessons, measurement, 30/60/90, starting point | 30–33 |
| 1:47–1:50 | Wingman, save the dates, hand off to Q&A | 34–36 |

Buffer: each demo is scoped to 12 minutes with a 3-minute recovery margin. If you are more than 5 minutes behind after Demo 2, cut Demo 3 steps 7 and 8 and go straight to rollback.

---

## Session takeaway coverage

| Takeaway | Where it lands |
|---|---|
| **1 — Design and build your own agent with practical patterns and tools** | Architecture layers, the four ConfigMgr entry points, tool-contract rules, MCP, and the six-pattern catalog; Demo 1 shows the tool contract running |
| **2 — Real-world scenarios where agents automate, augment, streamline** | Scenario map, Patch Tuesday triage, application intake; Demos 2 and 3 run two of them end to end |
| **3 — A clear starting point: architecture guidance and honest lessons** | "What did not work", measurement slide, the 30/60/90 plan, and the closing starting-point slide |

---

## Post-session

- Publish this runbook and the tool schemas alongside the deck.
- Offer the read-only profile as a copyable starting point; keep the gated profile behind your own review.
- Collect the questions you could not answer — they are next year's session.
