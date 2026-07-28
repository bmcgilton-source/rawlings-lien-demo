# Demo Script — Rawlings Lien Workflow Prototype

**Audience:** Partners at the firm (no CRM/Salesforce background) plus one technology consultant.
**Premise:** Everything in `docs/architecture.md` is built — Built Components (§3), Planned Components (§4, the Summary tiles and Bulk Advance Liens), and the Settlement Health Plan Junction (§4.7).
**Grounding:** Every beat below is tied to the language and structure of *Lien Workflow Management Platform Scope* (the RFP). The meta-notes in this document reference it directly; the talk track itself never does — it's written to be spoken as a story about the business, not read as a citation of a spec.

---

## Why this script is organized this way

The RFP states the platform must drive a lien through **"an order to cash lifecycle"** defined by **six capability areas** — Settlement Configuration, Lien Intake, Claim Evaluation, Settlement Response, Recovery Calculation, and Collection & Disbursement — and that the **"receive, process, and respond pattern is central to the system."** This demo is built around those two structures, across two acts:

- **Act 1** walks one settlement's claimants through intake, evaluation, and response — a complete, small, traceable loop, opening and closing on the receive/respond exchange with the administrator.
- **Act 2** pivots to a second settlement, pre-loaded with a real volume of liens, to show the same platform operating at the scale this business actually runs at.

The two-settlement split isn't cosmetic — it's what keeps Act 1's "this is fifteen claimants" story honest. If the live-import settlement and the volume settlement were the same record, everything shown in Act 1 (the Lien related list, the Escalation Queue) would already be sitting on top of ~1,000 pre-seeded rows, and the "at scale" reveal in Act 2 would land flat. Two settlements means the data is scoped apart by construction — no filtering tricks required. (See `demo-script-open-questions.md` for how this was decided.)

It also stays honest about scope, the way the RFP asks vendors to be: *"Anything a vendor proposes beyond a single lien from intake through collection should be called out explicitly."* Three of the six capability areas are demonstrated live; three are visualized on the record but explicitly narrated as not yet built.

| Capability area (RFP language) | Demonstrated how |
|---|---|
| Settlement Configuration | Live — the Settlement record and its terms |
| Lien Intake | Live — Import Claimants |
| Claim Evaluation | Live, with Liability/Damages simulated per the scope boundary |
| Settlement Response | Visualized only (Path) — narrated as not built |
| Recovery Calculation | Visualized only (Path) — narrated as not built |
| Collection & Disbursement | Visualized only (Path) — narrated as not built |

---

## Two narration tracks

Per `architecture.md` §4.5, keep these visibly separate:

- **Main track (partners):** business language, visual results, no mention of batches, governor limits, or Apex.
- **Aside track (the consultant):** only spoken if asked, or at the one designated beat (Beat 7). Confirms the mechanism is production-shaped, not a mockup.

---

## Pre-Demo Setup

- Settlement A's Files related list is empty going in — nothing generated yet. No Python server or ngrok needed for the live path — see Beat 6.
- The `SampleClaimants` Static Resource is uploaded and reachable in one click (Setup → Static Resources) for Beat 0.
- **Settlement A** (`Hip Implant Mass Tort 2024`) — empty of liens going in. This is the only settlement the live import touches.
- **Settlement B** (a second, pre-loaded settlement) — already carrying the ~1,000-record seeded volume (§4.6) and the pre-built deadline threshold record (`[Pre-existing] Helen Vasquez`), so its Summary tiles and red deadline tile read as a real, mature book of business the moment the room walks in.
- Browser tabs: Settlement A open (Lien related list scrolled to top) with the Escalation Queue list view in a second tab; Settlement B ready to switch to for Act 2.
- One silent end-to-end rehearsal completed and data reset per `architecture.md` §5.

---

## The Script

### Act 1 — One lien, the whole loop (Settlement A)

#### Beat 0 — Open with the raw file (40s)
**Page shown:** Setup → Static Resources → `SampleClaimants`; then Settlement A record, Files related list.
**Action:** Open the Static Resource record, point at the uploaded CSV. Switch to Settlement A, scroll to the Files related list, show it empty.
**Talk track:** "Every lien starts the same way — somebody else's data lands in our lap. A settlement administrator sends us their list of claimants. Today, that file's sitting right here — I uploaded it into Salesforce myself, ahead of time, the way you'd stage a file before a manual run." *(switch to Settlement A's Files related list)* "And nothing's gone back out yet — this record hasn't generated anything for the administrator. We work what's inside, then send something back. That loop — receive it, process it, respond — is the heartbeat of everything you're about to see. In production the receiving half disappears entirely: the moment an administrator drops a file on the channel we agree on, the platform picks it up on its own — no one uploading anything by hand."

#### Beat 1 — Settlement Configuration (1m)
**Page shown:** Settlement A record.
**Action:** Walk through the administrator, the response window (90 days), and the Settlement Health Plans related list.
**Talk track:** "Before any lien exists, before any claimant shows up, there's this — the settlement itself. Who's administering it, and the terms everyone agreed to — including the clock we're working against: ninety days to respond, starting from intake. Every lien created here inherits these terms automatically. And here are the health plans participating in this settlement — this is the list every incoming claimant gets checked against a minute from now, during intake."

#### Beat 2 — Lien Intake (1m)
**Page shown:** Settlement A record, Import Claimants quick action.
**Action:** Click **Import Claimants**. Let the toast land without narrating over it.
**Talk track:** "This is where the file we saw a minute ago actually goes to work. Normally this would happen on its own — the moment the administrator drops a file off, the platform picks it up without anyone touching a button. I'm clicking it manually today just so you can see the exact moment it happens. A list like this arrives from the administrator — could be fifteen names, could be thousands. Each row gets checked: does it belong to a plan we already work with, is there enough here to act on, and have we already seen this claimant on this settlement — if so, we update what's already there instead of creating a duplicate. What passes becomes a lien, new or updated. What doesn't gets set aside for someone to look at, instead of silently disappearing." *(click Import, let toast land)*

#### Beat 3 — Claim Evaluation, in aggregate (2m)
**Page shown:** Lien related list, then the Escalation Queue tab.
**Action:** Scroll the Lien related list. Switch tabs to the Escalation Queue list view.
**Talk track:** "The system didn't wait for us to tell it what to do next — it already worked through every one of these. For each claimant, it's answering two questions: does this actually belong to one of our plans, and if so, what's actually owed back. Most of the time it can answer both on its own, and those move forward automatically. But sometimes it can't — something doesn't line up, and rather than guess, it stops and hands that one to a person." *(switch to Escalation Queue tab)* "These are the ones it couldn't resolve. Nothing here got lost or dropped — it got routed, with a reason attached and someone assigned to look at it.

"One thing worth naming here: today that coverage-and-amount check is running against data we've simulated. In production, it connects out to the real systems that hold this information — the health plan's own eligibility and claims data — through what the platform treats as two dedicated services, coverage and damages. The pattern you're watching, receive, evaluate, route, doesn't change when those get plugged in. What changes is what's actually answering the question underneath it."

#### Beat 4 — Claim Evaluation, one record (2.5m)
**Page shown:** Open a Coverage Confirmed lien; open its child Response record; scroll to History; then the Path (chevron) on the Lien.
**Action:** Show Stage, Intake Date, Response Deadline on the Lien. Open the Response (Draft, Claimed Amount). Click into the Path and advance the Lien one stage forward, to **Response Ready**. Scroll to Field History and point out the new entry sitting right behind the automated one.
**Talk track:** "Here's what happened to one claimant, specifically. Coverage's confirmed, we've established what's owed, and a response position is already drafted, ready to go back to the administrator before the deadline. And scrolling down here — every one of these changes is logged. Who did it, what changed, when. Nobody typed this up after the fact. The system kept it as it happened.

"And it doesn't stop tracking once intake's done — it follows this lien through everything that happens to it, start to finish. Watch." *(click into the Path, advance to Response Ready)* "That's a stage move I just made by hand, and it's already sitting in the history right behind the automated one — same detail: who, what, when. No different treatment because a person did it instead of the system. Every hop this lien makes for the rest of its life gets captured exactly the same way."

*(Prep note, not spoken: pick any Coverage Confirmed lien for this beat, not the one you'll need for Beat 6 — advancing it here means it won't appear in the "Liens Ready to Respond" export anymore, since it's a stage past Coverage Confirmed. Also sets up Beat 7: this is the identical Coverage Confirmed → Response Ready move that Bulk Advance performs on ~850 records at once.)*

#### Beat 5 — The escalation path, one record (1m)
**Page shown:** Open an Escalated lien.
**Action:** Show Escalation Reason field and the assigned Task (due in 5 days).
**Talk track:** "Same lifecycle, one branch over. For this claimant, what came back doesn't confirm they were actually covered by the health plan on the date they were treated — the enrollment dates on file don't line up. That's the liability question, and the system won't guess at it. It stopped, wrote down exactly why, and handed it to a person with five days on the clock. Whoever picks this up goes back to the health plan, pulls the real enrollment record, and either confirms coverage — and this moves forward just like the others did — or confirms it doesn't apply, and we close it out."

#### Beat 6 — Respond: closing the loop (1m)
**Page shown:** Settlement A record, **Generate Response File** quick action; then the Files related list.
**Action:** Click **Generate Response File**. Let the results view show the generated rows without narrating over it. Scroll to the Files related list and point at the new file.
**Talk track:** "Now we send something back." *(click Generate Response File)* "One click, and it pulls together every lien we just confirmed — claimant, amount, ready to go back to the administrator." *(results view shows the rows)* "Notice the one we opened a few minutes ago isn't in this file — we bumped it forward to Response Ready ourselves already, so it's a step past this. Everyone else who confirmed the normal way is right here. In production, this goes out on its own, over the same channel it came in on. But if we ever needed to do this by hand — the automated hand-off is down, or it's a one-off — this is exactly how someone would do it: one click, and it's attached right here on the record, not floating around in an email or a folder somewhere." *(scroll to Files related list)* "File in. Claims worked. File out — and it lives right here, on the record, for as long as anyone needs to look back at it."

*(If the consultant asks why this isn't the live automated hand-off: in production, delivery to the administrator's SFTP server runs through a middleware integration layer — Salesforce doesn't speak SFTP directly, and standing up that layer is out of scope for this prototype. Generate Response File is the honest stand-in for where that middleware would sit: it builds the real CSV and attaches it as a Salesforce File, so the mechanism and the data are both real — only the outbound transport itself is simulated. No external dependency, no silent failure mode — it either produces the file or throws a visible error. A "Liens Ready to Respond" report also exists as a manual/ad-hoc alternative if this action is ever unavailable, but it's not part of the scripted path. See `demo-script-open-questions.md` for how this was decided.)*

---

### Act 2 — The book of business, at scale (Settlement B)

#### Beat 7 — Book of business at scale (2m) — *main volume beat*
**Page shown:** Navigate to Settlement B. Summary tiles (Total Liens, Escalated, one tile per stage, then Green/Yellow/Red deadline tiles).
**Action:** Click **Bulk Advance Liens**. Pick a From Stage with a large count. Show the preview count. Confirm. Wait for completion. Click Refresh. Point at the tiles shifting.
**Talk track (main, partners):** "That's the whole cycle for what just came in — fifteen claimants, start to finish. But this firm isn't running one settlement with fifteen claimants in it. It's running many, some of them for years. Let me show you one of those." *(navigate to Settlement B)* "Here's the whole state of this settlement's book, at a glance — how many liens total, how many are escalated, where every single one of them sits right now. See this cluster sitting at Coverage Confirmed — that's hundreds of liens all waiting on the same next step. Normally somebody opens each one to push it forward. I'm going to move that entire group forward, in one action." *(click Bulk Advance, pick From Stage, show preview)* "That'll move about eight hundred fifty of them forward a stage." *(confirm, wait, refresh)* "Done. Watch the tiles — that whole group just moved. Nobody opened eight hundred fifty records one at a time to do that."
**Talk track (consultant aside — only if asked "does this scale"):** "Under the hood this is a batch job — the same mechanism the platform uses for jobs into the millions of rows. What you just watched run live is the identical code path; at a hundred thousand records it just runs more chunks in the background, nothing about the logic changes."

#### Beat 8 — Deadline monitoring (1m)
**Page shown:** Still on Settlement B — the "Liens Near Deadline" component on the Settlement record page (§4.9), sitting alongside the Summary tiles.
**Action:** Point to the list — Helen Vasquez and, if the seeded data produced others, a few more rows sorted soonest-first.
**Talk track:** "This is the other thing living right here on the page — every lien on this settlement that's running short on time, soonest at the top. This one's been sitting for eighty-two days. Nobody had to do that math by hand or go pull a report — the system tracks the days remaining and surfaces it here on its own. It won't tap someone on the shoulder the way an escalation does — that's deliberate. Escalation needs a person to act, so it pushes a task and a notification. A deadline is something you check, the way you'd check any operational view — and now that check doesn't require leaving this page."

#### Beat 9 — The full lifecycle (1m)
**Page shown:** Open a seeded lien already sitting at a later stage (Negotiation or Agreed), scrolled to the Path (chevron).
**Action:** Point across all 11 stages. Click a later stage to show it can be manually advanced.
**Talk track:** "This one's already traveled further than intake — it's been through evaluation, and right now it's sitting in negotiation. This chevron is the full path every lien takes, start to finish. What you've watched run on its own tonight is the first stretch of it — intake, evaluation, and the response back to the administrator. The rest of this line — negotiation, recovery, collection — the platform already tracks where every lien sits against it, but the work behind those steps isn't built yet." *(click a later stage)* "Same record, same history, same everything — what's left is more workflow on top of what's already here, not a different system."

#### Beat 10 — Close (1m)
**No page — address the room directly.**
**Talk track:** "What we've shown tonight is a single lien carried through intake, evaluation, and response — start to finish — and then the same platform holding an entire book of business and moving it at real volume, live, in one action. And everything underneath that — the audit trail, the access control, the security — came from the platform itself; we didn't build any of it by hand. Three things we haven't built on purpose: the coverage and damages engines themselves, which stay purpose-built and connect out to the health plans' own systems rather than living here; the middleware layer that actually talks to an administrator's SFTP server on both ends — receiving a file automatically and sending one back — which today we stand in for by hand, importing the file ourselves and exporting a report in its place; and role-based restriction on actions like Bulk Advance, which is a small configuration change on this same platform, not a redesign. What comes next is negotiation, recovery, and collection — and none of it requires rebuilding what you saw tonight. It's the same data model, the same automation pattern, extended."

*(Prep note, not spoken: be ready to speak to the effort of building that middleware layer specifically on AWS Transfer Family + Lambda, not MuleSoft — see `demo-script-open-questions.md`.)*

---

## Anticipated Questions (have ready, don't volunteer)

| If asked | Answer |
|---|---|
| "Is this secure enough for health data?" | The platform handles the security and compliance groundwork natively — encryption, access control, audit logging — so we're not writing that ourselves. That's exactly why we picked a platform to build on rather than building the whole thing from scratch. |
| "Who can see which liens?" | Access is controlled by role and by attribute, down to who's allowed to see which settlement and which lien — already proven in this build: a Health Plan A user only ever sees Health Plan A's liens. |
| "What if the administrator's file has bad data in it?" | In production, every inbound file gets checked against an agreed data quality standard the moment it arrives — bad rows get rejected and handed back, not silently dropped. That check isn't built into this prototype yet; today's import assumes clean data. |
| "Does this replace the CRM or the finance system?" | No — this sits between them. It coordinates the workflow and hands off to the CRM for account records and to finance when money actually moves; it doesn't try to be either of those systems. |
| "How does this get deployed and updated as the org grows?" | Everything here is built as version-controlled configuration and code, deployed through a controlled pipeline — not hand-edited directly in a live org. |
| "Why only a thousand records? What prevents a hundred thousand?" | Nothing about the platform caps this at a thousand — that's a choice, not a limit we ran into. The exact same code that just moved this pool would move a hundred thousand the same way; it would just run more rounds in the background. We didn't want to add a slower, chunked seeding step and a longer live wait tonight just to make the number bigger — a thousand proves the mechanism works exactly the same way a hundred thousand would, without stretching out the demo or adding risk to the first live run. |
