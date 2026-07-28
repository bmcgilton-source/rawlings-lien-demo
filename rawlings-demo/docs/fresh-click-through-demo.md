# Fresh Salesforce Click-Through Demo — Rawlings Lien Workflow

## Demo objective

Prove that Salesforce can serve as the managed workflow platform for one lien from SFTP intake through collection while:

1. Making the **receive → process → respond** exchange visible.
2. Carrying one lien through all six capability areas in the scope.
3. Showing automation, human exception handling, auditability, and controlled access.
4. Keeping Liability, Damages, healthcare claims management, CRM, and Finance outside the Phase 1 boundary.
5. Distinguishing native Salesforce capability, configuration, custom code, and external SFTP transport.

This is a proposed fresh demo design. It does not depend on the existing prototype.

## Recommended format

- **Length:** 22–25 minutes, plus questions
- **Story:** one claimant, one health plan, one settlement, one lien, one payment
- **Primary persona:** Lien Operations Specialist
- **Supporting personas:** Operations Manager and Health Plan Reviewer
- **Demo record:** Jordan Reyes / Horizon Health Plan / Apex Hip Implant Settlement
- **Phase 1 integration:** SFTP only
- **Opening promise:** “We will follow one recovery opportunity from the file arriving through the money being reconciled.”

## Salesforce application navigation

Create a Lightning app named **Lien Operations** with these navigation items:

1. Operations Home
2. Settlements
3. Liens
4. Work Queue
5. Exchanges
6. Payments
7. Reports

Use a persistent utility item for **Lien Timeline** or place the timeline directly on the Lien Lightning record page.

## High-level object model

| Salesforce object | Purpose | Key relationships / fields |
|---|---|---|
| Account | Health plans and settlement administrators | Record Type, client status, data-sharing status |
| Contact | Administrator and health-plan contacts | Related Account, role |
| Settlement__c | Master configuration for a settlement | Administrator, response window, readiness status, effective dates |
| Settlement_Plan__c | Participating health plans and plan-specific terms | Settlement, Health Plan Account, contract rule set |
| Program_Term__c | Effective-dated lien resolution rules | Settlement, rule type, value, effective dates, version |
| Lien__c | One claimant recovery opportunity in one settlement | Claimant identifiers, Settlement, Health Plan, Stage, owner, deadline, hold |
| Evaluation__c | Immutable Liability or Damages evaluation result | Lien, type, result, source, rule/service version, evaluated date |
| Charge_Item__c | Recoverable medical charge under review | Lien, service date, billed amount, recoverable amount, disposition |
| Position__c | A versioned assertion or administrator counter-position | Lien, direction, amount, status, sent/received time |
| Exchange__c | Business-level inbound or outbound exchange | Settlement/Lien, direction, channel, message type, correlation ID, status |
| File_Job__c | Technical tracking for an SFTP file | File name, checksum, row counts, timestamps, error file, status |
| Recovery_Decision__c | Reproducible recovery calculation | Lien, rule versions, administrator amount, calculated amount, variance, outcome |
| Remittance__c | Payment received from administrator | Settlement, payment reference, received date, total |
| Remittance_Line__c | Charge- or lien-level allocation | Remittance, Lien, Charge Item, expected amount, received amount, variance |
| Disbursement_Instruction__c | Approved instruction for Finance | Lien, health-plan amount, Rawlings amount, status, approval data |
| Workflow_Event__c | Human-readable lifecycle and decision history | Lien, event, prior/new value, reason, actor, timestamp |
| Case / Task | Exception and assigned work management | Related Lien, queue, priority, SLA, resolution |

Claimant identity can be held on `Lien__c` for the narrow prototype. A separate person/master-data design should be deferred until Phase 2 discovery determines identity, privacy, and cross-settlement requirements.

## Lifecycle shown in Path

Configure the `Lien__c` Lightning Path with:

**Intake Review → Coverage Evaluation → Damages Evaluation → Position Ready → Position Submitted → Negotiation → Agreed → Recovery Validated → Payment Expected → Payment Reconciled → Disbursement Approved → Closed**

Use separate status fields for **Hold**, **Exception**, and **SLA Risk**. Do not overload the lifecycle stage with operational exceptions.

## Click-through and talk track

### Scene 1 — Start with operational control (1.5 minutes)

**Page:** Lien Operations Home

**Select / click:**

- App Launcher → **Lien Operations**
- **Operations Home**
- Point to “My Work,” “Approaching Deadline,” “Inbound Jobs,” and “Exceptions”

**Functions demonstrated:**

- Role-based homepage
- Queue ownership
- Deadline monitoring
- Native dashboards and reports

**Talk track:**

> “This is the operating front door. It tells a specialist what needs attention, what is approaching a program deadline, and whether an exchange with an administrator needs intervention. The platform is designed to run straight through when the data and rules allow it; this page is where people enter only when judgment or an exception is required.”

> “Today we will not tour a collection of disconnected features. We will follow one lien, Jordan Reyes, from an inbound SFTP file all the way through collection and disbursement.”

### Scene 2 — Configure the settlement and open the readiness gate (2 minutes)

**Page:** `Settlement__c` record — Apex Hip Implant Settlement

**Select / click:**

- Settlements → **Apex Hip Implant Settlement**
- **Details** tab
- Related → **Participating Health Plans**
- Related → **Program Terms**
- Click **Validate Readiness**
- Click **Open for Intake**

**Show:**

- Administrator Account
- Response deadline: 90 days
- Participating Horizon Health Plan
- Effective-dated program terms
- SFTP endpoint/profile reference
- Readiness checklist and status

**Functions demonstrated:**

- Screen Flow for readiness validation
- Approval or permission-controlled state change
- Effective-dated configuration
- Configuration history

**Talk track:**

> “Before a claimant can become a lien, the settlement defines how the work will operate: who administers it, which health plans participate, which rule versions apply, how long we have to respond, and where files are exchanged.”

> “The readiness gate is important. Automation cannot create liens against an incomplete program. Salesforce validates the required configuration, records who opened the settlement, and fixes the applicable rule versions in time.”

### Scene 3 — Receive through SFTP and validate the data contract (2.5 minutes)

**Page:** Exchanges → inbound `File_Job__c`

**Select / click:**

- Exchanges → **Inbound**
- Open `CLAIMANTS_2026-09-14.csv`
- Click **Process File** if the demo uses a staged trigger; otherwise refresh until status is Complete
- Open the **Validation Results** section
- Click the single accepted row for Jordan Reyes

**Show:**

- SFTP receipt timestamp
- File checksum and correlation ID
- Schema/data-contract version
- Rows received, accepted, rejected, and updated
- Attached source file
- Optional rejected-row file
- Created `Lien__c` link

**Functions demonstrated:**

- External SFTP transfer layer
- Apex/bulk ingestion service
- Idempotency via checksum and external claimant key
- Validation and error-file generation
- Platform Event or event-driven Flow

**Talk track:**

> “The administrator placed this file on SFTP. The integration layer received it, registered the exchange, and passed it into Salesforce. Before workflow begins, the file is checked against the agreed data contract.”

> “The checksum prevents the same file from being processed twice. Each accepted row either creates a lien or updates the existing lien for that claimant and settlement. Rejected data is not silently discarded; it is preserved with a reason and can be returned as an error file through SFTP.”

> “That is the first receive–process–respond loop: receive a file, validate and create work, then acknowledge exactly what happened.”

### Scene 4 — Inspect the lien workspace and audit timeline (1.5 minutes)

**Page:** Jordan Reyes `Lien__c`

**Select / click:**

- Click the created Lien
- **Overview** tab
- Point to Lightning Path, deadline, owner, health plan, and amounts
- Open **Timeline**

**Functions demonstrated:**

- Dynamic Lightning record page
- Path and stage guidance
- Calculated deadline
- Field history plus business-event history

**Talk track:**

> “This is the durable record for one recovery opportunity. The page keeps the current state concise, while the timeline preserves how it got here.”

> “The response deadline was derived from the settlement terms, ownership was assigned by routing rules, and the source exchange remains linked. Years from now, an authorized reviewer can reconstruct which data, rule version, person, and system action produced the outcome.”

### Scene 5 — Evaluate liability and damages without pretending to build the engines (2.5 minutes)

**Page:** Lien → Evaluations

**Select / click:**

- **Evaluations** tab
- Click **Run Prototype Evaluation**
- Review Liability result
- Review Damages result
- Expand Evaluation details

**Show:**

- Liability: coverage confirmed
- Damages: three charge items, two included and one excluded
- Prototype/manual source label
- Rule/service version
- Input/output snapshot or reference

**Functions demonstrated:**

- Orchestrating Flow
- `Evaluation__c` records
- Stubbed Phase 1 service boundary
- Charge-item creation
- Versioned outcomes

**Talk track:**

> “The workflow now asks two distinct questions. Liability asks whether the participating plan covered the claimant. Damages asks which charges are recoverable under the program.”

> “For Phase 1, these service results are deliberately stubbed or entered through a controlled prototype action. We are proving that Salesforce can request, store, version, act on, and audit the results—not claiming that the Liability or Damages engines are being built inside this prototype.”

> “The workflow advances automatically because both results are conclusive. An inconclusive result would create owned work instead of allowing the lien to drift.”

### Scene 6 — Demonstrate the human exception branch (1.5 minutes)

**Page:** Same Lien → action menu or pre-staged alternative Evaluation

**Select / click:**

- Click **Simulate Exception** or open a pre-staged related exception
- Open the generated **Case**
- Click **Resolve**
- Select a resolution reason and enter a note

**Functions demonstrated:**

- Case/Task routed to a queue
- SLA and escalation
- Required reason codes
- Resume automation

**Talk track:**

> “Straight-through processing is only credible if the exception path is equally clear. Here, a missing coverage date pauses the lien, creates owned work with an SLA, and records why automation stopped.”

> “The reviewer resolves the discrepancy using a controlled reason. The lien then resumes from the point it paused; no one has to recreate it or remember the next step.”

### Scene 7 — Send the initial position and receive the administrator response (2.5 minutes)

**Page:** Lien → Positions and Exchanges

**Select / click:**

- Click **Review Position**
- Inspect included/excluded Charge Items and asserted amount
- Click **Approve and Queue for SFTP**
- Open resulting outbound `Exchange__c`
- Then open pre-staged inbound administrator response

**Functions demonstrated:**

- Screen Flow for review/approval
- Outbound file generation
- SFTP queue/status tracking
- Correlation of response to original position
- Versioned `Position__c`

**Talk track:**

> “The system has assembled the position from the evaluated charge items. An authorized user reviews the evidence and approves the response.”

> “Salesforce creates the outbound business exchange, and the SFTP layer delivers the file. When the administrator replies, the correlation ID attaches that response to the correct lien and position.”

> “This is the central pattern again: receive claimant data, process the lien, respond with our position; then receive the counter-position, process it, and respond with the next step.”

### Scene 8 — Negotiate to an agreed amount (2 minutes)

**Page:** Lien → Negotiation Workspace

**Select / click:**

- Compare **Our Position** and **Administrator Position**
- Remove or retain one disputed Charge Item
- Enter required negotiation reason
- Click **Accept Agreed Amount**

**Functions demonstrated:**

- Custom Lightning Web Component or Screen Flow
- Field-level and action-level permissions
- Charge-level decisions
- Versioned positions and approval

**Talk track:**

> “The administrator disputes one charge. The negotiator can retain or remove individual items, but the system requires authority and a reason. It never overwrites the earlier position; it creates the next version.”

> “The result is an agreed amount with a reproducible trail from claimant data to charge-level disposition.”

### Scene 9 — Reproduce the recovery calculation (2 minutes)

**Page:** Lien → Recovery Calculation

**Select / click:**

- Click **Calculate Recovery**
- Expand **Rules Applied**
- Point to program-term, state-law, and plan-contract versions
- Click **Approve Recovery**

**Functions demonstrated:**

- Apex calculation service for complex logic
- Effective-dated metadata/rule records
- `Recovery_Decision__c`
- Approval Flow and segregation of duties

**Talk track:**

> “Agreement does not end the control process. The platform reconciles the administrator’s amount against what is recoverable under the settlement program, applicable state rule, and health plan contract.”

> “Every rule is versioned and effective-dated. The calculation stores its inputs and applied versions, so the same answer can be reproduced later even after a law or contract changes.”

### Scene 10 — Receive payment and reconcile at charge level (2.5 minutes)

**Page:** Payments → inbound remittance

**Select / click:**

- Payments → open remittance `REM-10482`
- Click **Match Remittance**
- Review expected versus received amount
- Expand allocated `Remittance_Line__c` rows
- Click **Confirm Reconciliation**

**Functions demonstrated:**

- SFTP remittance intake
- Automated matching
- Charge-level allocation
- Variance exception path
- Record locking after confirmation

**Talk track:**

> “The administrator’s remittance arrives through the same Phase 1 channel: SFTP. Salesforce matches the reference to the lien and reconciles the payment to the agreed charge-level amount.”

> “A variance would route to a payment exception. This remittance balances, so the specialist confirms reconciliation and the lien advances.”

### Scene 11 — Create the Finance instruction and close the lien (1.5 minutes)

**Page:** Lien → Disbursement

**Select / click:**

- Open generated `Disbursement_Instruction__c`
- Review Health Plan and Rawlings allocations
- Click **Approve Instruction**
- Click **Generate Finance SFTP File**
- Return to Lien and show Stage = Closed

**Functions demonstrated:**

- Controlled allocation
- Approval
- Outbound SFTP instruction
- Closure controls

**Talk track:**

> “Salesforce calculates the approved allocation and creates the instruction Finance will use to move funds. In Phase 1 that instruction leaves by SFTP; direct Finance integration belongs to a later phase.”

> “The lien closes only after the remittance balances and the disbursement instruction is approved. We have now carried one recovery opportunity from claimant intake through collection without crossing the agreed prototype boundary.”

### Scene 12 — Prove governance and the path forward (2 minutes)

**Page:** Lien Timeline, Login As restricted persona if practical, then Reports

**Select / click:**

- Open **Timeline**
- Show complete sequence and decision reasons
- Switch to, or show screenshot of, Health Plan Reviewer view
- Reports → **Operational Health**
- Point to throughput, cycle time, holds, and deadline tracking

**Functions demonstrated:**

- Shield/Setup Audit Trail/Event Monitoring as licensed
- Role hierarchy, sharing rules, restriction rules, permission sets
- Native reporting
- Deployment metadata in source control

**Talk track:**

> “The workflow is only useful if access and evidence travel with it. A health-plan reviewer sees only authorized settlements and liens, and only the actions granted to that role. The timeline shows who or what changed the lien, when, why, and which exchange or rule version was involved.”

> “Native reporting covers operational health without standing up a separate reporting platform. At production scale, asynchronous ingestion and processing handle files on the order of 100,000 claimants, while long-running jobs remain visible and recoverable.”

> “That scale statement is the path beyond this narrow prototype, not a claim that Phase 1 delivers the full book of business.”

## Closing statement

> “The choice being demonstrated is not simply Salesforce as a database. It is Salesforce as the governed orchestration layer around Rawlings’ differentiated services. The platform owns durable workflow, access, audit, work routing, reporting, and the administrator exchange. Liability, Damages, claims data, CRM, and Finance retain clear service boundaries.”

> “For Phase 1, the proof is intentionally narrow and concrete: one lien, all six capability areas, SFTP in both directions, and a complete history from intake to collection. The same object and event model can then be hardened for volume and connected upstream and downstream in later phases.”

## Capability implementation map

| Requirement | Native Salesforce | Configuration | Custom / external |
|---|---|---|---|
| Authentication, SSO, roles, permissions | Yes | Permission sets, sharing, restriction rules | Identity architecture may require design |
| HIPAA-supporting controls and audit evidence | Platform/licensing dependent | Retention and access policies | BAA and control validation required; Shield may be required |
| Custom lien data model | Platform capability | Custom objects, fields, record types | — |
| Workflow, queues, approvals, escalations | Flow, Case, Task, queues | Business-specific Flows and SLAs | Apex only for logic Flow cannot express |
| Full business-event history | Field History is partial | Tracking configuration | Custom immutable event/timeline object; Shield where required |
| SFTP | No direct core-platform endpoint | Named configuration references | External managed SFTP/integration layer required |
| 100,000-row ingestion | Bulk API/asynchronous platform capability | Job policies | Integration orchestration and resilient loader |
| Rule reproducibility | Metadata/data platform | Effective-dated rule records | Versioned calculation service for complex rules |
| Reporting | Reports and dashboards | Operational report types | External analytics only if future needs exceed native reporting |
| External portal | Experience Cloud | Sharing and page configuration | Licensing and compliance architecture |
| Configuration as code | Salesforce DX/metadata | Package/repository structure | CI/CD pipeline |

## Build components implied by the demo

### Lightning pages and components

- Lien Operations Home
- Settlement Console
- Lien Workspace with Path and Timeline
- Negotiation Workspace
- Exchange Monitor
- Payment Reconciliation Workspace
- Operational Health dashboard

### Flows

- Validate Settlement Readiness
- Intake Accepted Row
- Route Evaluation Exception
- Review and Approve Position
- Accept Negotiated Amount
- Approve Recovery
- Reconcile Remittance
- Approve Disbursement and Close

### Custom services

- SFTP exchange adapter outside Salesforce
- File validation/idempotency service
- Bulk lien upsert service
- Outbound file generator
- Prototype Evaluation adapter/stub
- Versioned recovery calculation service
- Remittance matching service

### Security design

- Permission sets by persona
- Restriction/sharing rules by settlement and health plan
- Field-level security for sensitive claimant and financial data
- Custom permissions for approve, negotiate, reconcile, and disburse actions
- Encryption, event monitoring, audit retention, and BAA requirements validated during architecture

## Demo guardrails

- Do not imply that Salesforce directly provides SFTP.
- Do not claim HIPAA compliance from configuration alone; identify licensing, BAA, control, and implementation dependencies.
- Do not present stubbed Liability or Damages results as real engines.
- Do not introduce API, portal, CRM, or Finance integrations into the Phase 1 live path.
- Do not make volume the hero of the Phase 1 demo. Explain the scale architecture and optionally show job monitoring, but keep the proof centered on one lien through collection.
- Do not use stage changes alone as evidence of a completed workflow. Show the related business artifact at every step: evaluation, position, decision, remittance, or instruction.
- Do not overwrite decisions. Create versioned records so prior positions and rule results remain reproducible.

## Suggested backup material for Q&A

Prepare, but do not put in the main click path:

- Logical receive → process → respond architecture
- Native/configured/custom/external requirements matrix
- Security and compliance responsibility matrix
- 100,000-row ingestion sequence and failure recovery
- Prototype milestones, assumptions, dependencies, and risks
- Business Architect responsibilities and required Rawlings participation
- Licensing and operating-footprint assumptions
- Phase 2 and Phase 3 extension roadmap
