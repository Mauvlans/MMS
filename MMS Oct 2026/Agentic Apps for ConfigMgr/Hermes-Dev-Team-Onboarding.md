# Build your own Hermes dev team — Ubuntu Desktop on Proxmox

A practical companion to the [Agentic Apps for ConfigMgr demo runbook](MMS-Agentic-ConfigMgr-Demo-Runbook.md). This guide gets you from an empty VM to an assistant that can research, code, test, review, and hand work back to you. **It does not install or implement the ConfigMgr demo agent** in the runbook; that runbook describes a separate sample and its proposed tool surface. Start with a throwaway repo before giving any agent access to a ConfigMgr lab.

**What you need:** a Proxmox VE node with spare resources, an Ubuntu Desktop amd64 LTS ISO, network access, a model-provider account, and (for GitHub projects) your own GitHub account. Budget roughly **4 vCPU, 8 GB RAM, and 64 GB disk** for a comfortable starter VM; increase disk/RAM for multiple concurrent builds. Use a dedicated VM and an unprivileged Ubuntu user. No Proxmox, Microsoft, or GitHub credentials belong in prompts or Git.

## 1. Create the Ubuntu Desktop VM

1. Download the **amd64 LTS desktop ISO** from [Ubuntu Desktop](https://ubuntu.com/download/desktop). Verify the download against Ubuntu's published checksums if you transfer it between machines. In Proxmox, select a storage that supports **ISO image**, then **ISO Images → Upload**. Note its storage ID and exact ISO filename.
2. In Proxmox, select **Create VM**. Choose an unused VM ID and name (for example `hermes-dev`). Select the uploaded ISO, a disk storage with enough free space, **64 GB disk**, **4 cores**, **8192 MiB RAM**, and a network bridge with normal Internet access. The defaults for firmware/display are fine for a first build. Do not select a production-only network just to make setup easier.
3. Start the VM, open **Console**, follow the Ubuntu installer, create a normal user, reboot, and remove/eject the ISO if it boots back into the installer. Take a Proxmox snapshot after the OS is working (if your storage supports snapshots).

**Prefer a shell on the Proxmox node?** This is the equivalent example, **not an unattended Ubuntu installation**. Replace all four values after checking `qm list`, `pvesm status`, and `pvesm list local --content iso`; the ISO storage might not be `local`, the disk storage might not be `local-lvm`, and your bridge might not be `vmbr0`. Never reuse an existing VM ID.

```bash
# Run on a Proxmox node, not inside Ubuntu. EDIT THESE VALUES FIRST.
VMID=1234
DISK_STORAGE=local-lvm
ISO='local:iso/ubuntu-26.04.1-desktop-amd64.iso'  # exact uploaded volid
BRIDGE=vmbr0
qm list
pvesm status
pvesm list local --content iso
# Stop if VMID already exists or any storage, ISO, bridge, or capacity differs.
qm create "$VMID" --name hermes-dev --ostype l26 \
  --memory 8192 --cores 4 --cpu host \
  --scsihw virtio-scsi-single --scsi0 "${DISK_STORAGE}:64" \
  --ide2 "${ISO},media=cdrom" --boot 'order=ide2;scsi0' \
  --net0 "virtio,bridge=${BRIDGE}" --agent enabled=1
qm config "$VMID"
qm start "$VMID"
```

Install Ubuntu **interactively in the Proxmox console**. After the first successful reboot, eject the ISO in Hardware → CD/DVD Drive (or adjust the boot order so disk boots first). The ISO filename above is an *example*, not a promise that this release is installed on your node. See the [Proxmox `qm` reference](https://pve.proxmox.com/pve-docs/qm.1.html) for flags.

## 2. Prepare Ubuntu and install Hermes

Open **Terminal inside the Ubuntu VM** (not the Proxmox shell):

```bash
sudo apt update
sudo apt install -y git curl ca-certificates qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
# Official Hermes installer; review a downloaded script first if your policy requires it.
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version
hermes doctor
```

The official installer bootstraps its own runtime; do not install random Python packages into the Ubuntu system Python to repair it. If `hermes` is not found, open a fresh terminal or check `~/.local/bin` on `PATH`. `hermes doctor` reports optional integrations that you have not configured; focus first on a working model call.

## 3. Connect a model and prove it works

```bash
hermes setup       # interactive first-run wizard
hermes model       # select/authenticate your provider and model later
hermes -z 'Reply exactly: HERMES_OK'
```

Choose a provider you already have access to (Nous Portal, GitHub Copilot, OpenRouter, Anthropic, etc.). Follow the on-screen sign-in or key prompt; available models and pricing depend on your account. **GitHub `gh` login is not by itself proof of Copilot model access** — use the Hermes model picker and test a real call. The `HERMES_OK` response is your first acceptance check. If it fails, run `hermes doctor` and revisit `hermes model` before adding workers.

For day-to-day use, run `hermes` in a project directory. `hermes desktop` is an optional desktop interface; the terminal is enough. Configure settings with `hermes config set` rather than editing its live YAML by hand. Keep provider secrets in Hermes's protected credential store or its `.env`, **never** in a repository or `AGENTS.md`.

## 4. Give it a real project and a clear contract

For an existing GitHub repo, install and authenticate the GitHub CLI in the VM if needed, then:

```bash
sudo apt install -y gh
# Interactive browser/device authentication; choose HTTPS when prompted.
gh auth login
gh auth status
gh repo clone OWNER/REPO ~/projects/REPO
cd ~/projects/REPO
hermes
```

Replace `OWNER/REPO`; a new scratch repo also works. In a project, write a short **`AGENTS.md`** at its root (review it before committing). Hermes loads project context from the repo; avoid contradictory `.hermes.md`/`AGENTS.md` instructions. Example for *your own* repo — replace the build commands and paths:

```markdown
# Project working agreement
- Read the README and existing code before designing a change. Reuse existing components.
- Work on a feature branch or isolated worktree; do not push directly to main.
- For each task: state acceptance criteria, implement, run relevant tests/build, and report commands plus actual results.
- Review the diff for secrets and unintended changes. Open a PR for human review; do not merge or deploy without approval.
- Do not use production credentials or modify production systems. Stop and ask before destructive operations.
```

Now give the coordinator a bounded first assignment:

```text
Inspect this repo and AGENTS.md. Do not edit anything yet. Tell me the build/test commands,
three useful first issues, what access is missing, and a proposed plan for the smallest issue.
```

Then, after checking the plan:

```text
Implement the smallest issue on a branch. Delegate independent research or review
when useful. Run the tests yourself, show their actual output, and open a PR.
Do not merge or deploy; report the PR link and remaining risks.
```

For parallel edits, start from the repo with `hermes -w` (isolated Git worktree), or ask Hermes to use separate worktrees for workers. Two agents editing one checkout will overwrite each other. A green local test is **not** proof that CI, deployment, or the end-user flow passed.

## 5. Grow a dev team in two stages

**Stage A — start with one coordinator plus short-lived specialists.** In your normal `hermes` conversation, ask it to use `delegate_task` for independent research, a distinct implementation slice, and a fresh review. Children have isolated conversations and return findings to the coordinator. They are **not durable employees**: the coordinator must integrate code, rerun tests, inspect the result, and tell you what is still blocked. Ask for explicit roles and handoffs, e.g.:

```text
Act as tech lead for this repo. Split this issue into backend, frontend, and independent
review only if those slices can proceed independently. Give each worker the repo path,
acceptance criteria, and tests. Keep edits isolated in worktrees. Integrate and verify
before reporting completion. Escalate ambiguous product decisions to me.
```

**Stage B — add named profiles and a durable board when there is recurring work.** Profiles have separate config, skills, memory, and sessions. Create them **only after** the single coordinator works; configure a model/provider for each (a profile does not automatically inherit your default's credentials). Role descriptions help task routing:

```bash
hermes profile create backend --description 'Implements APIs and data changes; tests and documents contracts.'
hermes profile create frontend --description 'Implements UI and accessibility; verifies user flows.'
hermes profile create reviewer --description 'Independently reviews diffs, security, and regression tests; does not merge.'
hermes -p backend setup
hermes -p frontend setup
hermes -p reviewer setup
hermes profile list
```

For the first board, use the **same host** and your actual repo path. The board keeps task state and handoffs across conversations; the gateway hosts its dispatcher. Do not call it a multi-host queue or assume creating a card means code was shipped.

```bash
cd ~/projects/REPO
hermes kanban boards create my-project --name 'My Project' \
  --default-workdir "$PWD" --switch
hermes kanban create 'Write a read-only API design' \
  --assignee backend --workspace worktree \
  --body 'Inspect the existing API. Draft a design in the repo with acceptance criteria; do not deploy.'
hermes gateway install    # install the supported background gateway service
hermes gateway start
hermes gateway status
hermes kanban list
```

Before trusting the dispatcher, check that each profile can complete a simple `hermes -p backend -z 'Reply OK'`-style model call, and inspect `hermes kanban show <TASK_ID>`, `hermes kanban runs <TASK_ID>`, or `hermes kanban log <TASK_ID>` for the actual worker result. `hermes dashboard` provides a visual Kanban view. If the task is blocked, fix its cause rather than creating duplicate cards. For GitHub deliverables, use PRs and verify their exact head SHA and required checks; keep a human merge/deploy gate. See the [Kanban tutorial](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban-tutorial) before adding dependencies and automatic routing.

## 6. Optional: chat from Discord, without giving everyone shell access

Run `hermes gateway setup` and select Discord, following the [official Discord setup guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord). Create a bot in the Discord Developer Portal, enable the intents required by the guide, invite it with the minimum permissions, and **restrict allowed user IDs**. Enter the bot token only in the setup flow, never a Git commit or chat message. By default server channels require an @mention. Use a private test channel and send a harmless query before letting it touch a project. The gateway is optional; the local CLI workflow above works without Discord.

## Operating rules / what “done” means

- **Daily loop:** issue → acceptance criteria → separate branch/worktree → implementation → tests/build → independent review → PR → human approval → deployment → read-back/functional verification. Share the PR and evidence, not merely a confident summary.
- **Credentials:** grant minimum necessary access to the VM and worker profiles. Keep ConfigMgr AdminService credentials and write roles out of this general dev setup. For the demo runbook, start with read-only lab RBAC, constrained tool calls, and an external approval gate for any write. An `AGENTS.md` instruction alone cannot enforce access control.
- **Boundaries:** no `--yolo` or disabled approvals as the starter default; no automatic production changes, disk wipes, secret exports, or blind retries of a write. Back up the VM and repo; use a disposable lab for experiments.
- **Troubleshooting:** `hermes doctor`, `hermes gateway status`, `hermes logs`, `gh auth status`, and the exact task/PR read-back tell you which layer failed. No tests or required checks configured? Say so; don't call the PR green.

### References

- [Hermes installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation), [profiles](https://hermes-agent.nousresearch.com/docs/user-guide/profiles), [delegation](https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation), [worktrees](https://hermes-agent.nousresearch.com/docs/user-guide/git-worktrees), [Kanban](https://hermes-agent.nousresearch.com/docs/user-guide/features/kanban), [security](https://hermes-agent.nousresearch.com/docs/user-guide/security)
- [Ubuntu Desktop downloads](https://ubuntu.com/download/desktop) · [Proxmox `qm` manual](https://pve.proxmox.com/pve-docs/qm.1.html)
