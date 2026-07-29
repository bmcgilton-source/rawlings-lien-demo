# Demo Script — Rawlings Lien Workflow Prototype

**Audience:** Partners at the firm (no CRM/Salesforce background) plus one technology consultant.
**Premise:** Everything in `docs/architecture.md` is built — Built Components (§3), Planned Components (§4, the Summary tiles and Bulk Advance Liens), and the Settlement Health Plan Junction (§4.7).
**Grounding:** Every beat below is tied to the language and structure of *Lien Workflow Management Platform Scope* (the RFP). The meta-notes in this document reference it directly; the talk track itself never does — it's written to be spoken as a story about the business, not read as a citation of a spec.

---

## Why this script is organized this way

The RFP states the platform must drive a lien through **"an order to cash lifecycle"** defined by **six capability areas** — Settlement Configuration, Lien Intake, Claim Evaluation, Settlement Response, Recovery Calculation, and Collection & Disbursement — and that the **"receive, process, and respond pattern is central to the system."** This demo is built around those two structures, across three acts:

- **Act 1** receives and validates an administrator file, then follows one named claimant through evaluation and the initial response.
- **Act 2** keeps following that same lien through negotiation, recovery, remittance, disbursement, and the Finance instruction.
- **Act 3** pivots to a second settlement, pre-loaded with real volume, to show how the same lifecycle is operated across the book of business.

The single-lien focus is deliberate, but it does not imply liens are operated one at a time. Rawlings processes liens at volume. We follow one lien live so the business rules, decisions, exceptions, and artifacts remain understandable. The same governed stage transitions are intended to be available in bulk; Act 3 demonstrates that mechanism on a second settlement without mixing ~1,000 seeded records into the clean intake story.

It also stays honest about scope, the way the RFP asks vendors to be: *"Anything a vendor proposes beyond a single lien from intake through collection should be called out explicitly."* All six capability areas are represented live. The honesty boundary is explicit: later-stage control points and user experience are real, while the recovery amount, remittance, and allocation are entered as prototype service results rather than produced by production calculation, payment, or Finance systems.
| Capability area (RFP language) | Demonstrated how |
|---|---|
| Settlement Configuration | Live — the Settlement record and its terms |
| Lien Intake | Live — Import Claimant File, including data-quality validation and rejection handling |
| Claim Evaluation | Live, with Liability/Damages simulated per the scope boundary |
| Settlement Response | Live — response-file generation and a guided negotiation decision; SFTP transport is simulated |
| Recovery Calculation | Live workflow/control point — the recovery result is entered as a simulated service output, not calculated by a production rules engine |
| Collection & Disbursement | Live workflow/control point — guided remittance reconciliation, allocation, closure, and a prototype Finance instruction; no funds move and no Finance integration exists |

---

## Two narration tracks

Per `architecture.md` §4.5, keep these visibly separate:

- **Main track (partners):** business language, visual results, no mention of batches, governor limits, or Apex.
- **Aside track (the consultant):** only spoken if asked, or at the one designated beat (Beat 6). Confirms the mechanism is production-shaped, not a mockup.

---

## Pre-Demo Setup

- Settlement A's Files related list is empty going in — nothing generated yet. No Python server or ngrok needed for the live path — see Beat 5.
- `ClaimantImportDemo.csv` is saved locally on the presenter's machine, one click away in a file browser, for the live upload in Beat 2. It also exists as a Static Resource in the org for version control, but the live beat reads from disk, not Setup. **Do not confuse it with `ClaimantValidationDemo.csv`** — a similarly named fixture used elsewhere in the org; uploading the wrong one produces the wrong created/updated/rejected counts and leaves `CLM-PRE-003` un-updated.
- **`Import Claimant File`** is the primary action in Settlement A's action bar; the original **`Import Claimants`** action stays as a manual fallback if the live upload does not work. It reads a known-good Static Resource through the same validation service, so use the clean-file fallback talk track and omit the rejection-file portion.
- **Settlement A** (`Hip Implant Mass Tort 2024`) — exactly **one** lien going in: `[Pre-existing] Priya Anand` (`CLM-PRE-003`), already at Coverage Confirmed. This is the record Beat 2's live import updates instead of duplicating — same precedent as Settlement B's `Angela Whitfield`. Reset via `scripts/apex/resetSettlementA.apex`, which deletes everything on the settlement and recreates this one record.
- **Hero Lien:** Thomas Adeyemi (`CLM-00007`, $7,800 recoverable) is created by the live upload. He is not opened on screen until Beat 5 (Generate Response File) — see that beat's prep note. Use this same Lien from Beat 5 through Finance instruction generation.
- **Settlement B** (a second, pre-loaded settlement) already carries ~1,000 seeded liens and the pre-built deadline threshold record (`Angela Whitfield`, `CLM-PRE-002`, `Response_Deadline__c` 5 days out) for the final operational-volume act. Reset via `scripts/apex/resetSettlementB.apex`, which also seeds ~100 additional liens in Yellow deadline status and ~10 in Red so the Liens Near Deadline view isn't a single lonely row, with none past due and Angela still soonest.
- Browser tabs: Settlement A open (Lien related list scrolled to top); Settlement B ready to switch to for Act 3. The Escalated Liens list for Beat 3/4 lives directly on the Settlement A record page — no separate tab needed.
- One silent end-to-end rehearsal completed and data reset per `architecture.md` §5.

---

## The Script

### Act 1 — Receive, validate, evaluate, and respond (Settlement A)

#### Beat 0 — Open with the raw file (20s)
**Page shown:** A local file browser showing `ClaimantImportDemo.csv` on the desktop; then Settlement A record, Files related list.
**Action:** Point at the file sitting on the desktop. Switch to Settlement A, show the Files related list is empty.
**Talk track:** "Phase 1 is intentionally focused on carrying a single lien from intake through collection. So today, we’re going to follow one claimant from the administrator’s file all the way through that lifecycle. Staying with one record keeps every decision, exception, and artifact visible. At the end, I’ll show how the same transitions operate across a Settlement at volume.

"This is the administrator’s source file. I’ll upload it manually so you can see the point where Salesforce takes over. In Phase 1, SFTP replaces this manual step; the workflow inside Salesforce remains the same." *(switch to Settlement A)* "This Settlement has not produced an outbound file yet. We’ll come back here after the claims have been worked and close the exchange loop."

#### Beat 1 — Settlement Configuration (1m)
**Page shown:** Settlement A record.
**Action:** Walk through the administrator, the response window (90 days), and the Settlement Health Plans related list.
**Talk track:** "This is the Settlement record—the governing configuration for the program." *(point to Administrator and Status)* "It identifies the administrator we exchange information with and whether the program is active." *(point to Response Window)* "This program uses a ninety-day response window. The prototype applies that convention to accepted claimants; production will derive the deadline from the effective terms and agreed clock-start event." *(point to Settlement Health Plans)* "These are the participating health plans. Intake uses this list as a control: a claimant row cannot enter this Settlement under an unconfigured plan."

#### Beat 2 — Lien Intake, clean and not-so-clean (1.5m)
**Page shown:** Settlement A record → **Import Claimant File** quick action → upload screen → Import Results screen; then the Files related list, open the new rejection file.
**Action:** Click **Import Claimant File**. Drag `ClaimantImportDemo.csv` from the desktop into the upload screen (or Browse to it), advance to Import, let the results screen land without narrating over it. Then switch to the Files related list and open the rejection CSV.
**Talk track:** "I’m placing the administrator’s file at the Salesforce boundary. From here, Salesforce validates the file and each claimant row against this Settlement." *(upload and process; pause for results)*

"Here are the results. Nineteen rows were received. Fourteen created new Liens. One updated an existing Lien rather than creating a duplicate. Four were rejected during intake." *(point to the result counts)*

"Those four did not become incomplete recovery records. One references a plan that does not participate in this Settlement, one is missing its claimant ID, one contains an invalid amount, and one duplicates another claimant in the file." *(open the rejection CSV)* "This correction file identifies the row and reason. It is the artifact we would return to the administrator through SFTP."

*(Prep note, not spoken: if the upload screen misbehaves live, fall back to **Import Claimants**. It reads a known-good Static Resource through the same validation service. Use the clean-file fallback talk track and omit the intentional rejection-file demonstration. The primary path depends on `[Pre-existing] Priya Anand` (`CLM-PRE-003`) existing so the results remain 14 created, 1 updated, and 4 rejected.)*

#### Beat 3 — Claim Evaluation, in aggregate (2m)
**Page shown:** Settlement A record — Lien Summary tiles, then the Escalated Liens related list (same page, no tab switch needed).
**Action:** Point to the Pipeline Stage tile (Coverage Confirmed population), then scroll down to Escalated Liens.
**Talk track:** "The accepted rows are now valid Liens, and Salesforce is already moving every one of them forward — no one is sitting here triaging a queue." *(point to Coverage Confirmed)* "This is the automatic path, and it's the majority: coverage confirmed, amount confirmed, straight through without a person touching it." *(scroll to Escalated Liens)* "Only the ones the system genuinely can't resolve land here — and even then, nothing sits idle. The moment a result is inconclusive, it's converted into owned work with a reason and a due date, so a human is pulled in only at the point where a human is actually required.

"That distinction matters: the four intake rejections were bad source data and never became Liens at all — the system caught those on its own. These three did become Liens, but the evaluation itself came back inconclusive, which is the one case where we deliberately hand off to a person. For the prototype, Liability and Damages results are supplied with the demo data. In production, dedicated services supply those same results, and Salesforce keeps doing what it just did here: resolve automatically wherever it can, and escalate only the genuine exceptions."

#### Beat 4 — The escalation path, one record (1.5m)
**Page shown:** Open one of the escalated liens flagged in Beat 3; then its assigned Task.
**Action:** Show the Escalation Reason field. Open the assigned Task itself — Subject, Assigned To, Due Date.
**Talk track:** "Let’s open one of those exceptions." *(point to Stage and Escalation Reason)* "This Lien passed intake, but coverage could not be confirmed for the treatment date. The stage shows Escalated, and this field records the reason the automated path stopped." *(open the Task)*

"This is the work created from that exception. It has a subject, an owner, and a five-day due date. The queue received a notification when it was assigned. Once a reviewer records the coverage outcome, the Lien either resumes the standard path or closes without recovery."

*(Prep note, not spoken: Thomas Adeyemi is the hero record for Beats 5, 6, and 7. Don't open or edit him before Beat 5 — Generate Response File must be what advances him to Response Submitted, not a manual stage change.)*

#### Beat 5 — Respond, and meet Thomas (2m)
**Page shown:** Settlement A record, **Generate Response File**; Files related list; then Thomas Adeyemi's Lien and Response — opened for the first time.
**Action:** Navigate back to Settlement A from the escalated lien. Click **Generate Response File**, let the results appear, show the attached CSV. Then open Thomas Adeyemi's Lien for the first time — show Stage = Response Submitted, Intake Date, Response Deadline, Coverage Result, Recoverable Amount, Response Status = Sent, Sent Date, and the full History (Intake → Coverage Confirmed → Response Submitted, all on one record).
**Talk track:** "Let’s return to the Settlement and send the confirmed positions back to the administrator." *(generate the file; pause for results)* "This result shows each included claimant, health plan, amount, and response deadline." *(show the attached file)* "Salesforce generated the outbound artifact and preserved it on the Settlement. The prototype stops at this boundary; Phase 1 SFTP delivers the same file.

"Now let’s follow one claimant from that response." *(open Thomas)* "This is Thomas’s Lien. The Path shows Response Submitted. His intake date and deadline show the clock, coverage is Confirmed, and the recoverable amount is seventy-eight hundred dollars." *(show Response and History)* "The related Response is Sent, the sent date is recorded, and History shows Intake, Coverage Confirmed, and Response Submitted on the same record."

*(If the consultant asks about transport: core Salesforce does not directly initiate SFTP. A lightweight integration layer such as AWS Transfer Family and Lambda receives and delivers files, then calls Salesforce APIs. The prototype generates and preserves the real business artifacts; inbound and outbound transport are simulated.)*

---

### Act 2 — One lien through recovery and collection (Settlement A)

#### Beat 6 — The full lifecycle, live, one control point at a time (3m)
**Page shown:** Thomas Adeyemi, still open from Beat 5, now at Response Submitted. Point to the Path, then launch **Negotiate**.
**Action:** Three separate quick actions, run back to back for the demo but each a standalone, independently-launchable control point in reality:
  1. **Negotiate** — Administrator Position **$6,000**, Agreed Amount **$6,500**, Negotiation Reason *"One disputed charge was excluded after review of the settlement program terms; the remaining charges were accepted."* Ends at Stage = Agreed.
  2. **Record Recovery & Remittance** — Recovery Amount **$6,500**, Remittance Amount **$6,500**. Ends at Stage = Collected.
  3. **Approve Disbursement** — Health Plan Allocation **$5,200**, Rawlings Allocation **$1,300**. Ends at Stage = Closed, Disbursement Status = Approved.
  Let each completion screen appear before launching the next action; return to the Lien and show its final Path and History once all three are done.
**Talk track:** "We're staying with Thomas so every downstream decision is easy to see. Rawlings operates these stages at volume, and I'll show the bulk pattern after we finish his journey." *(launch Negotiate)*

"This is the Negotiation control point. Our position is seventy-eight hundred dollars. The administrator's position is six thousand, and the agreed amount is sixty-five hundred. The reason is required before the Lien can advance." *(enter the values, finish)* "Thomas is now Agreed.

"In practice, the next step happens later — once the administrator's payment actually arrives. It's a separate action for exactly that reason: Recovery and Remittance doesn't get recorded until there's a real payment to record." *(launch Record Recovery & Remittance)* "This screen compares the agreed amount against the recovery result and remittance. For the prototype, I'm entering the service and payment results. Both are sixty-five hundred, so there's no variance. A mismatch would stop the straight-through path and create review work instead of letting it reach Disbursement." *(finish)* "Thomas is now Collected.

"Once collection is confirmed, disbursement can be approved." *(launch Approve Disbursement)* "This screen allocates the amount received: fifty-two hundred to the health plan and thirteen hundred to Rawlings. Those allocations must equal the remittance." *(finish and show completion)* "Thomas is now Closed. This is the same Lien created from the file we uploaded — not a pre-staged downstream example, and each of those three actions is independently available whenever its moment actually arrives, not bundled into one sitting."

*(Scope note, spoken once): "One boundary to keep clear: the workflow and exception controls are live. The recovery, remittance, and allocation values are prototype inputs. Production services and charge-level records will supply those results."*

*(Prep note, not spoken: if any of the three flows does not launch cleanly, do not edit fields manually in front of the audience. Show the Path, describe the guided control points as the fallback, skip Beat 7, and continue to the operational-volume act.)*

#### Beat 7 — Generate the Finance instruction (1.5m)
**Page shown:** Thomas, now Closed with Disbursement Approved; **Generate Finance Instruction**; Files related list.
**Action:** Generate the instruction, let the success state appear, then show the attached CSV and the generated-at/generated-by fields.
**Talk track:** "The Lien is closed, the payment is reconciled, and the allocation is approved. The remaining step is the controlled handoff to Finance." *(generate the instruction)*

"The success screen shows the agreed amount, remittance, and both allocations." *(point to the filename and amounts)* "Salesforce generated a prototype machine-readable instruction from the approved values." *(show Files and audit fields)* "The file remains attached to Thomas’s Lien, along with who generated it and when. Finance would define the final production schema, delivery method, and acknowledgment process. Salesforce is controlling and preserving the instruction; it is not moving the money."

---

### Act 3 — The book of business, at scale (Settlement B)

#### Beat 8 — Governed stage transitions at volume (1.5m)
**Page shown:** Settlement B Summary tiles and **Bulk Advance Liens**.
**Action:** Show the large Coverage Confirmed population. Open Bulk Advance, preview the transition, confirm, and refresh the tiles if rehearsal timing is reliable. Otherwise stop after preview.
**Talk track:** "We followed Thomas individually to make the workflow clear. Rawlings does not have to operate the book one record at a time." *(point to the Summary tiles)* "This Settlement shows the population at each lifecycle stage and the work currently escalated.

"Every lifecycle transition will also be available as a permission-controlled bulk action." *(open Bulk Advance)* "The user selects the current and target stages, and Salesforce previews the affected population before anything moves." *(confirm only if rehearsed; refresh)* "The work runs asynchronously, and the refreshed tiles show the group in its new stage. Production applies the stage-specific rules and permissions while retaining history on each Lien."

**Consultant aside, only if asked about 100,000 rows:** "The implementation uses Salesforce’s asynchronous batch pattern and query locator rather than a synchronous browser transaction. That is the appropriate scaling mechanism; production acceptance would still validate the complete 100,000-row workload, processing time, locking, monitoring, and failure recovery with representative data."

#### Beat 9 — Deadline monitoring (1m)
**Page shown:** Settlement B, **Liens Near Deadline** beside the Summary tiles.
**Action:** Point to Angela Whitfield and the soonest-first list.
**Talk track:** "The stage counts tell us where the book stands. This list tells us where time is becoming a risk." *(point to the list)* "Each row is an active Lien approaching its program deadline, ordered by urgency. The user can see the claimant, current stage, and days remaining without leaving the Settlement.

"Coverage uncertainty creates assigned work because someone must resolve it. Deadline exposure remains visible here as an operational control across the portfolio."

#### Beat 10 — Close (1m)
**No page — address the room directly.**
**Talk track:** "We started with Thomas as one row in an administrator file. Salesforce validated that row, created the Lien, routed the evaluation, preserved the response, controlled the agreement and reconciliation, and produced the Finance instruction.

"The controls remained visible throughout: invalid data was returned with a reason; unresolved business questions became owned work; financial mismatches stopped the process; and outbound artifacts stayed attached to the record.

"We demonstrated one Lien so the workflow was clear, then showed the same transition model across a Settlement at volume. That is the platform pattern this prototype is proving.

"The Liability and Damages engines, SFTP transport, recovery-rules engine, remittance feed, and Finance delivery remain defined integration boundaries. Production extends this orchestration layer with charge-level records, effective-dated rules, representative volume testing, and the required security, audit-retention, and compliance controls."

*(Prep note, not spoken: be ready to discuss AWS Transfer Family + Lambda as one lightweight SFTP integration option, while keeping the final integration recommendation subject to nonfunctional requirements and cost.)*

---

## Anticipated Questions (have ready, don't volunteer)

| If asked | Answer |
|---|---|
| "Is this secure enough for health data?" | Salesforce provides managed identity, access, encryption, monitoring, and audit capabilities that we configure and validate rather than building a security platform ourselves. Production suitability still requires the appropriate services and licensing, a BAA, the final sharing and encryption design, retention policies, operational controls, and evidence that those controls meet HIPAA, 42 CFR Part 2, and applicable state requirements. |
| "Who can see which liens?" | Access is controlled by role and by attribute, down to who's allowed to see which settlement and which lien — already proven in this build: a Health Plan A user only ever sees Health Plan A's liens. |
| "What if the administrator's file has bad data in it?" | That's not hypothetical — you just saw it, in Beat 2. Every inbound file gets checked against an agreed data-quality contract the moment it lands: required fields, valid values, whether the health plan is even part of this settlement, duplicate claimant IDs within the file. Bad rows get rejected and handed back with a specific reason each, not silently dropped or forced in. That's built and running today, not a production-only promise. |
| "Does this replace the CRM or the finance system?" | No — this sits between them. It coordinates the workflow and hands off to the CRM for account records and to finance when money actually moves; it doesn't try to be either of those systems. |
| "Is that the final Finance file format?" | No. It is a prototype machine-readable instruction proving the handoff and audit pattern. Finance would define and approve the production schema, transport, acknowledgment, and reconciliation contract. |
| "Where are the individual medical charges and recovery rules?" | The guided Flow demonstrates the control points using prototype amounts. Production adds versioned charge-level records and effective-dated program, state-law, and health-plan contract rules so the result can be reproduced after those rules change. |
| "How does this get deployed and updated as the org grows?" | Everything here is built as version-controlled configuration and code, deployed through a controlled pipeline — not hand-edited directly in a live org. |
| "Why only a thousand records? What about a hundred thousand?" | A thousand records keeps the live demonstration fast while exercising the asynchronous batch mechanism rather than a browser transaction. That is the intended scaling pattern, but the demo is not a substitute for a production-volume test. Before launch we would validate the complete 100,000-row workload, processing time, locking, storage, monitoring, error isolation, and recovery using representative files and downstream automation. |
