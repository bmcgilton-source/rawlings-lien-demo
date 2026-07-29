# Today's Build Plan — Bulk-Ready for Mario, Lien-Lifecycle as Stretch

**Date:** July 28, 2026
**Available time:** One focused working day
**Context:** The first live demo is with Mario. He has not confirmed — and won't before this demo — the single-lien full-lifecycle pivot explored in earlier planning (`questions-for-mario.md`). His demo therefore runs the existing, already-built two-act script in `docs/demo-script.md` unchanged: **Act 1** (one lien, intake through response) then **Act 2** (the same platform at volume — bulk advance, deadline monitoring, the full lifecycle Path). Bulk is the lead story, not an optional 60-second coda.

Building out the late-lifecycle single-lien Screen Flow (negotiation → recovery → disbursement → closed) is still worth doing — for a *later* demo — and today's plan gives it real time. But it is explicitly **stretch scope**: it does not replace, delay, or put at risk anything Mario is scheduled to see.

**Retroactive note:** the plan below (step 7, and every later reference to it) describes building one combined `Complete Lien Journey` Screen Flow. That is what was originally built, then split later the same day into three independent flows/quick actions — `Negotiate`, `Record Recovery & Remittance`, `Approve Disbursement` — each gated on the Lien's current stage instead of one guided session. The plan, schedule, and checklist below are left as originally written for the historical record; see `architecture.md` §4.11 for the as-built design and `demo-script.md` Beat 6 for how it's actually run in the demo.

## Two tiers of "done"

### Tier 1 — Must complete (Mario's demo depends on this)

1. Reverify Act 1 end-to-end, specifically the reworked `ResponseFileWriter.cls` native-attach path (committed today, not yet run live).
2. **Task R.3** — restage the browser/desktop for both settlements.
3. **Task V.7** — full live dry run of Bulk Advance on the volume settlement, clean twice.
4. One full combined rehearsal of Act 1 + Act 2 back to back, at presentation pace.
5. Data reset and environment staged, ready to go.

### Tier 2 — Stretch (only after Tier 1 is done and gated)

6. Add the late-lifecycle fields to `Lien__c`.
7. Build the `Complete Lien Journey` guided Screen Flow (negotiation through closure).
8. Add it as a quick action and place it on the Lien record page.
9. **Only if it's solid and rehearsed:** fold in a brief teaser at Beat 9 of `demo-script.md`, where a later-stage lien is already opened and the Path is already being discussed. If it isn't solid, Beat 9 runs exactly as scripted today (Path narration, "not built yet") — there is no fallback to write, because the stretch work simply doesn't appear.

**Do not let Tier 2 work touch Tier 1 gates.** If Tier 2 runs long, it gets cut — never the reverse.

## Scope for today

### Preserve as-is (everything already built — architecture.md §3–§4)

- Static Resource claimant input, claimant import Apex/LWC
- Lien routing Flow, escalation queue and Task behavior
- `ResponseFileWriter.cls` native-attach response generation (just reworked — needs live reverification, not rebuilding)
- Summary tiles, Bulk Advance batch mechanism, volume settlement seed data
- Deadline monitoring ("Liens Near Deadline"), Settlement Health Plan junction
- Field history tracking, Lightning Path (all 11 stages)

### Stretch build (Tier 2 only, time-boxed, cuttable at any point)

Same field list, Flow design, and cut rules as the original single-lien plan — reproduced below.

### Do not build today (either tier)

- Screen Flow file upload, real SFTP transport
- `Exchange__c`, `File_Job__c`, `Evaluation__c`, `Charge_Item__c`, `Position__c`, `Recovery_Decision__c`, `Remittance__c`, `Disbursement_Instruction__c` — this full object set is the `fresh-click-through-demo.md` redesign, a separate future-looking concept doc that explicitly contradicts today's plan ("do not make volume the hero"). It is not today's build target and not connected to the current org.
- Production recovery-rules engine, Finance/CRM integration, custom timeline component
- New reporting infrastructure, general-purpose processing for every lien scenario

## Target demo values (for Tier 2 stretch work)

Use one claimant consistently for the late-lifecycle story.

| Value | Demo amount |
|---|---:|
| Initial asserted/recoverable amount | $18,500 |
| Administrator position | $14,000 |
| Agreed amount | $15,250 |
| Recovery amount | $15,250 |
| Remittance amount | $15,250 |
| Payment variance | $0 |
| Health plan allocation | $12,200 |
| Rawlings allocation | $3,050 |
| Disbursement status | Approved |

Suggested negotiation reason:

> One disputed charge was excluded after review of the settlement program terms; the remaining charges were accepted.

## Addendum: live file-upload replaces the pre-staged import (built mid-day, outside original scope)

Not part of the original plan — added because the presenter wanted Beat 0/2 to show an actual file landing live, not a pre-staged Static Resource with a narrated disclosure. Design: `architecture.md` §4.10 / `rawlings-demo-build-schedule.md` "Claimant Import via Screen Flow." This touches **Beat 0/2, the opening of Mario's demo** — higher stakes than the late-lifecycle stretch work, which only appears at the end if it earns its way in.

Built:
- `ClaimantImportService.importFromCsv()` — shared CSV-parse/insert logic extracted out of `ClaimantImportController`, which now delegates to it (Static Resource path unchanged and re-verified — the original `ClaimantImportControllerTest` passes unmodified against the refactor).
- `ClaimantFileImportInvocable` — `@InvocableMethod` Apex action, takes a Settlement Id + ContentDocumentId, reads the `ContentVersion` and calls the shared service.
- `claimantFileUpload` LWC — wraps `lightning-file-upload`, exposed to Flow screens (`lightning__FlowScreen` target). **Built as a fallback after the native `flowruntime:fileUpload` screen component turned out not to exist in this org/API version** — the exact risk the design doc flagged in advance.
- `Import_Claimant_File` Screen Flow — Upload screen (the LWC) → Apex Action → Results screen. Simpler than first drafted: the custom LWC outputs a single Id directly, so no collection-extraction workaround was needed.
- `Settlement__c.Import_Claimant_File` quick action, added **first** in the Settlement action bar (`numVisibleActions` bumped 3→4). The original `Import Claimants` action stays deployed and in the bar as a manual fallback, per the "swap which one's primary, don't delete either" guidance in the design doc.

**Verified via CLI:** all Apex — 6/6 tests passing, including one that inserts a real `ContentVersion` and drives the invocable end-to-end.
**Not verified — needs a browser:** the Flow screen itself, the `lightning-file-upload` interaction, and the Flow↔LWC data binding (`recordId` in, `contentDocumentId` out via `FlowAttributeChangeEvent`). This is the second browser-untested piece built today, alongside `Complete Lien Journey`.

**If this doesn't work when tested:** the old `Import Claimants` action is still live in the action bar — fall back to it and keep the pre-staged disclosure exactly as `demo-script.md` already has it. Nothing about this addition can break the existing working path; it's additive.

## Addendum: Finance Instruction Generator (built after `Complete Lien Journey`, outside the original Tier 2 step list)

Not part of the original Tier 2 plan (steps 6–9 above only cover the `Complete Lien Journey` Flow) — added as a further stretch item once that Flow was built, to give the lifecycle a final, auditable artifact rather than ending at `Closed`/`Approved` with nothing downstream. Full spec: `docs/finance-instruction-generator-spec.md`. Design and status: `architecture.md` §4.12.

Built: three audit fields on `Lien__c` (`Finance_Instruction_Generated_At__c`, `Finance_Instruction_Generated_By__c`, `Finance_Instruction_Filename__c`), `FinanceInstructionWriter.cls` (+ test, 8/8 passing, 96% coverage), `generateFinanceInstruction` LWC, `Generate Finance Instruction` quick action placed after `Complete Lien Journey` in the Lien action bar, plus a Files related list and the three audit fields added to the Lien Lightning Record Page.

**Browser-verified 2026-07-28:** against a manually-imported Lien with `Stage__c` and the financial fields edited directly (not via the `Complete Lien Journey` guided screens) — action button appeared after a hard refresh (Lightning caches FlexiPage action bars client-side; a newly-deployed action doesn't always show until the tab reloads), eligibility validation correctly blocked generation with a business-readable message while required amounts were blank, and generation succeeded once the spec's demo values were entered (Agreed/Recovery/Remittance $15,250; Health Plan Allocation $12,200; Rawlings Allocation $3,050; Disbursement Status Approved) — CSV attached to the Lien's Files related list.

**Still not verified:** the underlying `Complete Lien Journey` guided Flow (§4.11) itself — today's test reached the eligible state by editing fields directly, not by running the Negotiation → Recovery and Remittance → Disbursement screens live. Beat 9 readiness (below) still depends on that Flow, not on the Finance Instruction Generator alone.

## Addendum: Claimant Intake Validation and Rejection Handling (built later the same day, outside the original plan)

Not part of any tier above — a separate spec (`docs/claimant-intake-validation-spec.md`) requested after the day's original scope was set. Rebuilds the import path added by the earlier live-file-upload addendum (above) so it actually enforces the PDF's data-quality contract instead of just parsing rows and inserting Liens. Design and status: `architecture.md` §4.13.

Built:
- `ClaimantImportResult.cls` / `ClaimantRowError.cls` — new typed result shared by both import entry points, replacing the old `Map<String, Integer>` return.
- `ClaimantImportService.importFromCsv` rewritten: exact-header/empty-file/size/row-limit checks, then 14 row-level rules applied in the spec's fixed priority order (required fields, Claimant ID length, Health-Plan existence *and* Settlement participation via `Settlement_Health_Plan__c`, allowed Coverage Result values, Recoverable Amount required/numeric/non-negative/positive-when-Confirmed, case-insensitive duplicate-in-file), existing-Lien update-instead-of-insert by Settlement + Claimant ID (ambiguous matches rejected), partial DML (`Database.insert/update(records, false)`) so one bad record doesn't sink the batch, and a quote-escaped rejection CSV attached to the Settlement whenever anything's rejected.
- `ClaimantImportController` and `ClaimantFileImportInvocable` updated to return/consume the typed result. `claimantImport` LWC toast and `Import_Claimant_File` Screen Flow's results screen both updated to show the full created/updated/rejected/automated/escalated breakdown, with a `warning`-styled variant when anything's rejected.
- `ClaimantValidationDemo.csv` — a new, separate Static Resource fixture (15 rows: 8 Confirmed + 2 Unable-to-Confirm creates, 1 update of `SampleClaimants.csv`'s `CLM-00001`, 4 intentional rejections) matching the spec's own worked example. Not yet wired to a Quick Action or the demo script.
- `ClaimantImportServiceTest` rewritten to 22 methods (all cases the spec calls out, plus a couple extra); `ClaimantFileImportInvocableTest` extended to 2.

**Deployed and CLI-verified, later the same session:** the CLI turned out to be present on the machine, just not on the PATH the initial check used — found and invoked via its full install path. Deployed via `sf project deploy start` (dry-run first, then the real deploy), scoped to exactly this addendum's files. **27/27 Apex tests passing** in the org (`ClaimantImportServiceTest`, `ClaimantFileImportInvocableTest`, and the pre-existing `ClaimantImportControllerTest` — deploy ID `0AfdL00000ePP6kSAG`).

**One pre-existing file had to be fixed to make this deployable at all:** `ClaimantImportControllerTest.cls` (not otherwise part of this addendum) called `ClaimantImportController.importClaimants` expecting the old `Map<String, Integer>` return type — the org-wide Apex recompile that every deploy triggers would have failed on this file even though it wasn't in scope. Fixed to consume the new typed result and to give its test settlement `Settlement_Health_Plan__c` junction records, without which the new plan-participation check would have rejected every row of the real `SampleClaimants.csv` that test reads live.

**Deploy deliberately excluded the flexipages and permission set already showing local changes** (`Lien_Record_Page.flexipage-meta.xml`, `Settlement_Record_Page.flexipage-meta.xml`, `Rawlings_Demo_Access.permissionset-meta.xml`) — those reflect page-layout edits made directly in the org that don't exist in the local working copy. Only the files this addendum actually changed (plus the one pre-existing test fix above) were passed to `--source-dir`.

**Browser-verified live, same day:** presenter cleared the live settlement to zero Liens (`scripts/apex/resetSettlementA.apex`) and uploaded `ClaimantValidationDemo.csv` through `Import_Claimant_File`. Result, confirmed by direct query afterward: **11 created (9 Coverage Confirmed, 2 Escalated), 0 updated, 4 rejected, 15 rows received.** Pulled the generated rejection CSV back out of the org and it matches exactly — correct row numbers, codes (`UNKNOWN_HEALTH_PLAN`, `MISSING_CLAIMANT_ID`, `INVALID_RECOVERABLE_AMOUNT`, `DUPLICATE_IN_FILE`), reasons, and quote-escaping. Both the uploaded file and the rejection file landed on the Settlement's Files related list as expected. This also closes out the original live-file-upload addendum's open item — same Flow, same LWC, same data binding, now exercised live.

**Known risk to the already-working import — resolved by the same live test:** `ClaimantValidationDemo.csv` uses the same three Health Plan Accounts `SampleClaimants.csv` does, against the same live settlement, and all passed the participation check. `Import Claimants` itself hasn't been separately re-clicked since the deploy, but it runs identical validation code against identical data, so this isn't expected to be a live surprise.

**Caveat found during the live run, not a bug:** because the settlement had zero pre-existing Liens at test time, the fixture's `CLM-00001` "update" row created a new Lien instead of updating one — 11 created/0 updated rather than the fixture's designed 10/1. To see the update branch specifically, re-seed `CLM-00001` (via `Import Claimants`/`SampleClaimants.csv`) before uploading `ClaimantValidationDemo.csv` on top of it.

**Reset script reused successfully:** `scripts/apex/resetSettlementA.apex` (pre-existing, not written for this addendum) worked unmodified to clear the live settlement between import test runs — deletes by Settlement Id regardless of Claimant ID prefix, so it handles both `SampleClaimants.csv`- and `ClaimantValidationDemo.csv`-derived Liens the same way. Run twice live during this addendum's testing.

**Remaining before trusting this in front of Mario:** re-click the actual `Import Claimants` button (not just its underlying data) against `SampleClaimants.csv`, and exercise the update path specifically per the caveat above. Otherwise this addendum is now fully live-verified, not just deployed.

## Work schedule

### 8:00–8:20 — Protect the working demo

- Confirm the current Git working tree (uncommitted work from prior sessions was already checkpointed and pushed to `main` — `195b9f8`).
- Reverify Act 1 works end-to-end **including the reworked response-file mechanism**, which has not been run live since the native-attach rework: Import Claimants → Coverage Confirmed → open a Response → Generate Response File → confirm the CSV lands on the Settlement's Files related list.
- Record the live settlement ID (Settlement A) and volume settlement ID (Settlement B, `Talc Powder Mass Tort 2023`, `a02dL00000p27A8QAI`).

**Gate:** Act 1 is confirmed working, specifically the just-changed response-file path, before touching anything else.

### 8:20–8:35 — Task R.3: restage for two settlements

Per `rawlings-demo-build-schedule.md`: Tab 1 = Settlement A (Lien related list scrolled to top) + Escalation Queue list view in a second tab; a third tab or bookmark ready to jump to Settlement B. Confirm Settlement B's Summary tiles and Bulk Advance action are visible without searching.

**Acceptance check:** Both settlements are one click away.

### 8:35–10:00 — Task V.7: full live dry run of Bulk Advance

On Settlement B: confirm Summary tiles reflect ~1,000 total liens with the expected spread. Run Bulk Advance Liens (Coverage Confirmed → Response Ready), confirm the preview reads ~850, submit, wait for completion, Refresh, confirm the tile shift. Spot-check Field History on a few moved records. Rehearse the narration from `demo-script.md` Beats 7–9 while doing this.

Run it twice. Fix anything that blocks or materially weakens the story; note anything cosmetic for later.

**Gate:** Two clean dry runs before moving on.

### 10:00–10:30 — First combined rehearsal (Act 1 + Act 2)

Run the full `demo-script.md` script back to back, uninterrupted, at presentation pace — this is Mario's actual demo. Record total time, navigation delays, anything that doesn't refresh, any talk-track overclaim.

**Gate:** One clean full run of Mario's demo, start to finish, before any Tier 2 work begins.

### 10:30–1:30 — Tier 2 stretch: add the minimum Lien fields + build the Flow

Only start this block once the 10:00–10:30 gate is met. If V.7 or the combined rehearsal ran long and ate into this window, shrink this block — do not borrow time from the afternoon's Tier 1 rehearsals below.

Create these fields on `Lien__c`:

| Label | API name | Type |
|---|---|---|
| Administrator Position | `Administrator_Position__c` | Currency(16,2) |
| Agreed Amount | `Agreed_Amount__c` | Currency(16,2) |
| Negotiation Reason | `Negotiation_Reason__c` | Long Text Area |
| Recovery Amount | `Recovery_Amount__c` | Currency(16,2) |
| Remittance Amount | `Remittance_Amount__c` | Currency(16,2) |
| Payment Variance | `Payment_Variance__c` | Formula(Currency): `Remittance_Amount__c - Agreed_Amount__c` |
| Health Plan Allocation | `Health_Plan_Allocation__c` | Currency(16,2) |
| Rawlings Allocation | `Rawlings_Allocation__c` | Currency(16,2) |
| Disbursement Status | `Disbursement_Status__c` | Picklist: Draft, Pending Approval, Approved |

All `Stage__c` values this Flow needs (`Agreed`, `Pre-Validation`, `Collected`, `Closed`) already exist on the picklist — no picklist changes required.

Also: add all new fields to `Rawlings_Demo_Access`; enable field-history tracking for `Agreed_Amount__c`, `Recovery_Amount__c`, `Remittance_Amount__c`, `Disbursement_Status__c`; deploy fields and permission-set changes.

Build a Screen Flow (`recordId` input, `Lien__c`) — same design as originally spec'd:

1. **Load and validate** — get the Lien, permit only when recoverable amount is positive, display claimant/settlement/stage/asserted amount.
2. **Negotiation screen** — collect administrator position, agreed amount, negotiation reason; validate non-negative, agreed ≤ asserted, reason required; set Stage → `Agreed`.
3. **Recovery and remittance screen** — collect recovery + remittance amounts; if remittance ≠ agreed, set Stage → `Pre-Validation`, populate `Escalation_Reason__c` (reused field) with a variance explanation, create a payment-review Task, end with an exception message; otherwise set Stage → `Collected`.
4. **Disbursement screen** — collect health plan + Rawlings allocations; validate non-negative and that they sum to the remittance amount; set `Disbursement_Status__c` → `Approved`, Stage → `Closed`.
5. **Completion screen** — display claimant, all captured amounts, variance, final stage/status.

**Acceptance check:** main path ends at Closed; mismatch path ends at Pre-Validation with a Task; validation and allocation math enforced; Flow errors visible, not swallowed.

**Cut rule:** if this whole block is running out of time, cut the exception branch (Step 3's mismatch path) first — keep the happy path, narrate the intended exception behavior if it ever comes up. If still short on time, stop after the fields deploy and skip the Flow entirely — deployed fields with no Flow is a clean stopping point, not a broken one.

### 1:30–2:15 — Tier 2 stretch: quick action + page placement

- Create a Flow quick action on `Lien__c` (`Complete Lien Journey`), add to the Lien action bar.
- Add three compact field sections (Negotiation / Recovery and Payment / Disbursement); keep Path and History prominent; do not redesign the record page.

**Acceptance check:** action launches from the selected Lien with the correct record ID; updated values and History appear after completion.

### 2:15–2:35 — Tier 2 stretch: deterministic data and reset — **Done**

**Correction from the original plan:** this uses Settlement B (the volume settlement), not Settlement A. Beat 9 of `demo-script.md` already opens a later-stage lien on Settlement B for the full-lifecycle Path moment — that's the natural home for the teaser, not Settlement A. Settlement A also can't absorb a 16th hand-built record without undermining its "this is fifteen claimants" framing (the exact problem `demo-script-open-questions.md` already solved once by splitting the two settlements). A dedicated hand-built record on Settlement B follows the same precedent as `[Pre-existing] Helen Vasquez`.

Built: a dedicated Lien on Settlement B (`Talc Powder Mass Tort 2023`, `a02dL00000p27A8QAI`) — `Claimant_ID__c = 'CLM-PRE-002'`, Angela Whitfield, Health Plan A, `Stage__c = 'Coverage Confirmed'`, `Recoverable_Amount__c = 18500`. Record Id `a00dL00003YfQ1SQAV`. Inserting it fired the existing routing Flow automatically, which created its Draft Response (`Claimed_Amount__c = 18500`) for free — no manual step needed.

Reset script: `scripts/apex/resetLateLifecycleDemo.apex` — clears all eight late-lifecycle fields, restores `Stage__c` to `Coverage Confirmed`, deletes any `Review: Payment variance` Task on this record. Run via `sf apex run --file scripts/apex/resetLateLifecycleDemo.apex --target-org rawlings-demo`. Verified working.

**Talk-track note (unresolved):** Beat 9's current line — "This one's already traveled further than intake... right now it's sitting in negotiation" — assumes an already-negotiated record. This record starts at Coverage Confirmed instead, so the teaser shows the *entire* guided journey live rather than a partial Path click. That's a stronger demo but needs different framing ("watch the rest of this lien's life happen live" instead of "it's already traveled further"). Rewrite this line in `demo-script.md` only if the 2:35 rehearsal decides Tier 2 is demo-ready.

**Acceptance check:** reset completes in under a minute (single record, one Apex script run) — met.

**Hard stop for Tier 2 at 2:35.** Whatever state the stretch work is in at this point is what exists for today — the rest of the day belongs to Tier 1.

### 2:35–3:15 — Second combined rehearsal (Mario's actual demo)

Reset data, close unrelated tabs, run `demo-script.md` end to end at presentation pace exactly as Mario will see it.

**Decide here whether Tier 2 is demo-ready:** only fold the Beat 9 teaser in if the Flow ran clean in this rehearsal with no fixes needed. If it needed any fix during this run, leave Beat 9 as scripted today and treat the Flow as ready for a *future* rehearsal, not this one.

**Gate:** two clean full runs of Mario's demo (this one plus the 10:00–10:30 run) — more valuable than any additional Tier 2 polish.

### 3:15–3:45 — Corrective work

Priority order: broken Flow path (Act 1 or Act 2) → incorrect field values/calculations → missing permission → page refresh/navigation problem → reset failure → talk-track correction → visual polish. Do not add new scope.

### 3:45–4:15 — Third rehearsal only if corrections were made

Skip if the 2:35 rehearsal was already clean.

### 4:15–5:00 — Final staging

- Reset both settlements' data one final time.
- Confirm the live settlement is in its expected starting state; response-file destination (Files list) ready.
- Stage browser tabs per the R.3 restage.
- Save a copy of the reset instructions.
- Stop changing metadata.

## Mario's demo click path (unchanged from `demo-script.md`)

1. Static Resource → Settlement A Files (empty)
2. Settlement Configuration — administrator, response window, participating health plans
3. Import Claimants
4. Lien related list → Escalation Queue
5. Open a Coverage Confirmed lien → Response → History → advance Path to Response Ready
6. Open an Escalated lien → escalation reason + Task
7. Generate Response File → Files related list
8. Switch to Settlement B → Summary tiles → Bulk Advance Liens (live)
9. Liens Near Deadline component
10. Open a later-stage lien, Path chevron — **if Tier 2 is demo-ready per the 2:35 rehearsal decision, launch `Complete Lien Journey` briefly here instead of just narrating "not built yet"; otherwise run this beat exactly as scripted**
11. Close

## Fallback strategy

### If Bulk Advance is slow or fails live during V.7 or the real demo

- Do not wait on a stalled job live. Show the Summary tiles' current state, narrate the mechanism (consultant aside track), and reference the prior successful dry run.

### If import fails live

- Open a pre-imported coverage-confirmed lien on Settlement A, say the file was processed during pre-demo validation, continue from the lien workspace.

### If response-file generation fails

- Open the "Liens Ready to Respond" report as the documented manual/ad-hoc alternative (`demo-script-open-questions.md`), show the same outbound data, continue without repeated clicks.

### Tier 2 stretch work, at any state of readiness

- No fallback needed — it is not in Mario's scripted path unless the 2:35 rehearsal explicitly earned it a place at Beat 9.

## End-of-day checklist

- [ ] Act 1 reverified against the reworked `ResponseFileWriter.cls`
- [ ] Task R.3 — two-settlement restage complete
- [ ] Task V.7 — Bulk Advance dry run clean twice
- [ ] First combined rehearsal complete (10:00–10:30 gate)
- [ ] Second combined rehearsal complete, at presentation pace
- [ ] Corrective work applied if needed, re-rehearsed
- [ ] Browser and data reset for presentation
- [x] Tier 2 fields deployed *(stretch)*
- [x] Tier 2 Flow active and quick action visible *(stretch)* — not yet tested end-to-end in browser
- [x] Tier 2 reset procedure documented *(stretch)* — `scripts/apex/resetLateLifecycleDemo.apex`, verified running clean
- [x] Finance Instruction Generator built and browser-verified *(stretch, addendum)* — generation, eligibility validation, and File attachment all confirmed live; the `Complete Lien Journey` Flow itself is still the open item above, not this
- [ ] Beat 9 teaser decision made explicitly — in or out *(stretch)*
- [ ] Beat 9 talk-track line rewritten to match a Coverage-Confirmed starting point, if teaser goes in *(stretch)*
- [x] Claimant Intake Validation and Rejection Handling deployed via CLI *(addendum)* — deploy ID `0AfdL00000ePP6kSAG`
- [x] `ClaimantImportServiceTest` / `ClaimantFileImportInvocableTest` / `ClaimantImportControllerTest` actually run and passing in the org *(addendum)* — 27/27
- [x] `SampleClaimants.csv` / the original `Import Claimants` action's Health-Plan data checked against the new participation requirement *(addendum)* — all 3 plans linked and confirmed passing live via the equivalent validation-demo upload; the `Import Claimants` button itself still not re-clicked
- [x] `ClaimantValidationDemo.csv` uploaded live through `Import_Claimant_File` *(addendum)* — 11 created/0 updated/4 rejected, rejection CSV verified correct; update path not yet exercised (needs `CLM-00001` re-seeded first)
