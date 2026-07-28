# Today’s Build Plan — End-to-End Lien Demo Compromise

**Date:** July 28, 2026  
**Available time:** One focused working day  
**Goal:** Extend the existing, working Salesforce demo just enough to carry one lien credibly from intake through collection and closure.

## Definition of done

By the end of the day, the presenter can complete this story without leaving Salesforce:

1. Open a configured settlement.
2. Trigger the existing claimant-file import.
3. Show automated evaluation and escalation routing.
4. Open one coverage-confirmed lien.
5. Generate the initial administrator response file.
6. Run one guided action covering negotiation, recovery, remittance, and disbursement.
7. Finish with the lien at `Closed`.
8. Show the resulting values and field history.
9. Briefly show deadline monitoring and scale as supporting evidence.

The demo must explicitly state that:

- The Static Resource is a pre-staged stand-in for inbound SFTP.
- Outbound files are generated but not transported by SFTP.
- Liability and Damages results are simulated.
- The guided late-lifecycle Flow demonstrates workflow orchestration, not completed production recovery or Finance integrations.

## Scope for today

### Must complete

- Add the minimum late-lifecycle fields to `Lien__c`.
- Build one guided Screen Flow for negotiation through closure.
- Add the Flow as a Lien quick action.
- Place the new fields and action on the Lien record page.
- Create deterministic demo data and a reset procedure.
- Rewrite the main talk track around one lien.
- Complete two full rehearsals.

### Preserve as-is

- Static Resource claimant input
- Existing claimant import Apex/LWC
- Existing Lien routing Flow
- Escalation queue and Task behavior
- Response creation and response-file generation
- Deadline monitoring
- Summary tiles
- Bulk Advance capability
- Volume settlement

### Do not build today

- Screen Flow file upload
- Real SFTP transport
- Exchange or File Job objects
- Charge Item, Position, Recovery Decision, Remittance, or Disbursement objects
- Production recovery-rules engine
- Finance or CRM integration
- Custom timeline component
- New reporting infrastructure
- General-purpose processing for every lien scenario

## Target demo values

Use one claimant consistently through the late-lifecycle story.

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

## Work schedule

### 8:00–8:20 — Protect the working demo

- Confirm the current import, routing, and response-file path still works.
- Record the demo settlement ID and intended claimant ID.
- Confirm the current Git working tree before editing.
- Do not alter or discard unrelated working-tree changes.
- Write down the current reset steps for the existing demo.

**Gate:** Existing demo is known-good before new work begins.

### 8:20–9:20 — Add the minimum Lien fields

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

Also:

- Add all new fields to `Rawlings_Demo_Access`.
- Enable field-history tracking for:
  - `Agreed_Amount__c`
  - `Recovery_Amount__c`
  - `Remittance_Amount__c`
  - `Disbursement_Status__c`
- Deploy the fields and permission-set changes.

**Acceptance check:**

- Fields are visible to the demo user.
- The variance formula returns `$0` for equal agreed and remittance amounts.
- Existing Apex tests still compile.
- Field-history tracking is confirmed enabled for `Agreed_Amount__c`, `Recovery_Amount__c`, `Remittance_Amount__c`, and `Disbursement_Status__c` — non-negotiable, since Beat 4's talk track promises the audience these later-lifecycle changes get captured the same way the automated ones did.

**Cut rule:** If metadata deployment consumes more than 60 minutes, do not cut field-history tracking on these four fields. Cut something else in this block first (e.g., defer the permission-set update to immediately after the Flow-building block) before touching history.

### 9:20–12:00 — Build `Complete Lien Journey` Screen Flow

Create a Screen Flow that accepts `recordId` for a `Lien__c`.

#### Step 1 — Load and validate

- Get the current Lien.
- Permit the action only when the lien has a positive recoverable amount.
- Display claimant, settlement, current stage, and asserted amount.

#### Step 2 — Negotiation screen

Display:

- Recoverable amount

Collect:

- Administrator position
- Agreed amount
- Negotiation reason

Validate:

- Amounts cannot be negative.
- Agreed amount cannot exceed the asserted/recoverable amount for this demo.
- Negotiation reason is required.

Update:

- Store the three values.
- Set Stage to `Agreed`.

#### Step 3 — Recovery and remittance screen

Display:

- Agreed amount

Collect:

- Recovery amount
- Remittance amount

Decision:

- If remittance equals agreed amount, continue.
- If it does not match:
  - Set Stage to `Pre-Validation`.
  - Populate `Escalation_Reason__c` with a payment-variance explanation.
  - Create a Task for payment review.
  - End with an exception message.

For the main demo path:

- Store the recovery and remittance amounts.
- Set Stage to `Collected`.

#### Step 4 — Disbursement screen

Display:

- Remittance amount

Collect:

- Health plan allocation
- Rawlings allocation

Validate:

- Both amounts must be non-negative.
- The two allocations must equal the remittance amount.

Update:

- Set `Disbursement_Status__c` to `Approved`.
- Set Stage to `Closed`.

#### Step 5 — Completion screen

Display:

- Claimant
- Initial asserted amount
- Administrator position
- Agreed amount
- Remittance amount
- Payment variance
- Health plan allocation
- Rawlings allocation
- Final stage and disbursement status

**Acceptance check:**

- The main path ends at `Closed`.
- The mismatch path ends at `Pre-Validation` and creates a Task.
- Required values and allocation math are enforced.
- Flow errors are visible rather than silently swallowed.

**Cut rule at 11:30:** If the exception branch is not working, remove it from today’s live Flow. Keep the happy path and narrate the intended exception behavior.

### 12:00–12:30 — Break and checkpoint

Before breaking:

- Save and activate the latest working Flow version.
- Confirm the main Flow path works once.
- Note any deferred issue explicitly.

Do not start additional scope during the break.

### 12:30–1:15 — Add the action and update the Lien page

- Create a Flow quick action on `Lien__c`:
  - Label: `Complete Lien Journey`
  - Flow: the new guided Screen Flow
- Add the action to the Lien action bar.
- Add three compact field sections:
  - Negotiation
  - Recovery and Payment
  - Disbursement
- Keep the existing Path and History prominent.
- Do not redesign the entire record page.

**Acceptance check:**

- The action launches from the selected Lien.
- The Flow receives the correct record ID.
- Updated values appear on the record after completion.
- History is still visible.

### 1:15–1:45 — Prepare deterministic data and reset

- Select the exact coverage-confirmed claimant for the live story.
- Ensure its recoverable amount is `$18,500`.
- Ensure a Draft Response exists.
- Ensure it will appear in the response file before the presenter manually advances it.
- Create a reset script or documented reset procedure that:
  - Clears all new late-lifecycle fields.
  - Restores Stage to `Coverage Confirmed`.
  - Restores Disbursement Status to blank or Draft.
  - Removes any payment-exception Task created during testing.
- Keep the existing Static Resource path as the import fallback.

**Acceptance check:** Reset can be completed in five minutes or less.

### 1:45–2:45 — Rewrite the main demo script

Restructure the current script into this main path:

1. **Settlement configuration**
2. **Pre-staged SFTP input**
3. **Import and automated routing**
4. **One coverage-confirmed claimant**
5. **Draft position and audit history**
6. **Generate outbound response file**
7. **Complete Lien Journey**
8. **Closed lien and complete financial result**
9. **Operational health and approaching deadlines**
10. **Optional scale proof**
11. **Close on platform fit and honest scope**

Target timing:

| Segment | Time |
|---|---:|
| Configuration and intake | 3 min |
| Evaluation and escalation | 4 min |
| Initial response | 3 min |
| Negotiation through closure | 5 min |
| Audit, operational health, and scale | 3 min |
| Close | 1 min |
| **Total** | **19 min** |

Required late-lifecycle disclosure:

> “The prototype currently automates intake, evaluation routing, and the initial response. This guided interaction demonstrates how Salesforce controls the negotiation, recovery, reconciliation, and disbursement decisions. The production recovery rules, SFTP transport, and Finance integration are later-phase work.”

Required inbound-file disclosure:

> “For demo reliability, the administrator’s input file is pre-staged in Salesforce. In Phase 1, an SFTP adapter creates the same inbound transaction automatically; the Salesforce processing shown from this point remains the same.”

### 2:45–3:30 — First full rehearsal

Run the entire demo without stopping.

Record:

- Total time
- Navigation delays
- Flow errors
- Records that did not refresh
- Places where the talk track overclaims functionality
- Reset problems

Fix only issues that block or materially weaken the main story.

**Gate:** The full main path completes once before any polish work.

### 3:30–4:00 — Corrective work

Priority order:

1. Broken Flow path
2. Incorrect field values or calculations
3. Missing permission
4. Page refresh/navigation problem
5. Reset failure
6. Talk-track correction
7. Visual polish

Do not add new features.

### 4:00–4:40 — Second full rehearsal

- Reset the data.
- Close unrelated browser tabs.
- Run the demo at presentation pace.
- Use the exact talk track disclosures.
- Confirm total time is no more than 20 minutes.
- Confirm the optional volume segment can be skipped without breaking the close.

**Gate:** Two successful full runs are more valuable than one additional feature.

### 4:40–5:00 — Final staging

- Reset the chosen lien one final time.
- Confirm the live settlement is in the expected starting state.
- Confirm the response-file destination/Files list is ready.
- Place the intended claimant CSV somewhere accessible.
- Stage browser tabs.
- Save a copy of the reset instructions.
- Stop changing metadata.

## Main demo click path

1. App Launcher → Lien Operations
2. Settlements → live demo Settlement
3. Show configuration and participating health plans
4. Import Claimants
5. Open Lien related list
6. Open the selected coverage-confirmed claimant
7. Show Response and History
8. Return to Settlement → Generate Response File
9. Return to selected Lien
10. Complete Lien Journey
11. Show final amounts, Closed stage, and History
12. Return to Settlement summary/deadline components
13. Optionally show the volume Settlement and Bulk Advance
14. Close

## Optional scale segment

Keep the existing volume settlement and Bulk Advance capability, but limit the segment to 60 seconds unless asked for more.

Suggested talk track:

> “The main proof was one lien through the complete lifecycle. The same platform also has to manage the book of business. This second settlement shows the operational distribution and the existing asynchronous bulk mechanism. It is supporting evidence for scale, not a claim that the narrow Phase 1 prototype delivers every production-volume requirement.”

## Fallback strategy

### If the new Flow fails before rehearsal

- Do not demonstrate it live.
- Use a pre-populated Closed lien.
- Walk the new field sections and Path.
- Explain the guided workflow as the proposed next increment.
- Keep the current intake-through-response demonstration intact.

### If import fails live

- Open a pre-imported coverage-confirmed lien.
- Say the file was processed during pre-demo validation.
- Continue from the lien workspace.

### If response-file generation fails

- Open the already-built “Liens Ready to Respond” report.
- Show the same outbound data.
- Continue without attempting repeated clicks.

### If time is running long

Cut in this order:

1. Bulk Advance live action
2. Detailed deadline explanation
3. Second escalation record
4. Field-history deep dive

Never cut the guided journey or the scope disclosure.

## End-of-day checklist

- [ ] New Lien fields deployed
- [ ] Demo permission set updated
- [ ] Complete Lien Journey Flow active
- [ ] Flow quick action visible
- [ ] Main happy path completes at Closed
- [ ] Payment variance displays correctly
- [ ] Allocation validation works
- [ ] Demo claimant has deterministic values
- [ ] Reset procedure tested
- [ ] Script updated
- [ ] Scope disclosures included
- [ ] First full rehearsal complete
- [ ] Blocking issues corrected
- [ ] Second full rehearsal complete
- [ ] Browser and data reset for presentation

