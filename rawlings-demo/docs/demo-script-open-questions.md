# Demo Script — Open Questions

Questions raised while walking through `demo-script.md`, to resolve before the script is considered final.

---

### Should the response-file generation beat (Beat 6) be cut entirely?

**Raised by:** Brian, while reviewing Beat 0.

**Context:** The outbound file generation (`ResponseFileWriter.cls` → local Python server → ngrok) is flagged as one of the riskier pieces of the build — it depends on a live local server, ngrok tunnel, and a Named Credential pointed at a URL that changes per session, plus a 2–5 second async wait narrated as "give it a moment." The build schedule's own risk register already flagged "demo network blocks ngrok" as Medium likelihood / High impact — the worst combination in the register, and the only risk in the whole demo tied to something outside the Salesforce org (a local process, a tunnel, the venue's network).

**Decision:** Replace the live callout with a native Salesforce report. Build a "Liens Ready to Respond" report (Lien object, filtered by Settlement + Stage = Coverage Confirmed) and use the standard Export button, saving the export into the `outbound/` folder so Beat 0's visual bookend (empty folder → file appears) still holds. No Apex, no LWC, no external server, no network dependency — the whole mechanism lives inside the report UI. The talk track now does double duty: it still frames the automated production path ("this goes out on its own, over the same channel it came in on") and adds an ad-hoc/manual-fallback story ("if we ever needed to do this by hand... this is exactly how someone would do it") — which reads as an operational strength, not a downgrade. `ResponseFileWriter.cls` and the Python server stay built and functional in the org; they're just no longer the thing running live in the room.

**Correction during review:** the consultant-facing answer originally said this was "the real SFTP callout, just not run live for risk reasons." That overstates it — `ResponseFileWriter.cls` POSTs to a local HTTP server, a stand-in for the exchange, not a literal SFTP client. Per `architecture.md` §8, real delivery to an administrator's SFTP server in production goes through a middleware integration layer (MuleSoft or AWS Transfer Family + Lambda); Salesforce doesn't speak SFTP directly, and that middleware is out of scope for this prototype. So the accurate answer if asked is two-part: real delivery needs middleware not built here, and the local-server stand-in that *was* built isn't run live because it depends on a tunnel and the venue's network for the whole demo.

**Status:** Resolved. `docs/demo-script.md` Beat 6 rewritten; see `architecture.md` §4.8 for the report build item and the note on the built-but-not-demoed SFTP path.

---

### Settlement record doesn't show "participating health plans"

**Raised by:** Brian, while reviewing Beat 1.

**Context:** Beat 1's original talk track claimed the Settlement record shows its participating health plans alongside administrator and response window. Checked against the data model: `Settlement__c` only has Administrator, Program Start Date, Response Window Days, and Status. Health plan is modeled per-Lien only (`Health_Plan__c` lookup, resolved by matching Account name at import time). There's no page that shows "this settlement's participating health plans" as a set.

**Decision:** Worth closing. Logged as a build item in `architecture.md` §4.7 — a new `Settlement_Health_Plan__c` junction object (Lookup to `Settlement__c`, Lookup to `Account`), shown as a related list on the Settlement record page. Decorative only: no validation rule constraining a Lien's `Health_Plan__c` to the junction records, no Apex, no test class. 3 junction records to be hand-created for the demo settlement, linked to the same 3 Health Plan Accounts already used elsewhere in the demo.

**Status:** Logged, not yet built. Once built, Beat 1 of `demo-script.md` should be updated to show the related list directly instead of narrating health plans as per-lien only. Whether to eventually enforce the Lien↔Settlement health plan constraint is tracked separately in `architecture.md` §9.

---

### Will a plain list view / related list hold up at ~1,000 records, and does the pre-seeded volume leak into the earlier beats?

**Raised by:** Brian, while reviewing Beat 3.

**Context:** A list view or related list technically paginates fine at 1,000 rows, but it's a poor visual for proving aggregate state — that's what the Summary tiles (§4.1–4.4) are for. The bigger issue: the setup notes had the ~1,000-record volume pre-seeded onto the *same* settlement used for the live import, so before the volume reveal even happened, the Lien related list and Escalation Queue in the earlier beats would already be sitting on top of ~1,000 extra rows — quietly undercutting the "this was just fifteen claimants" framing the volume beat depends on.

**Decision:** Split into two Settlement records instead of filtering. Settlement A holds only what the live import creates during the demo; Settlement B is pre-loaded with the ~1,000-record seed and the pre-built deadline record ahead of time. Because Lien related lists, Escalation Queue membership, and the Summary tiles are all scoped by the `Settlement__c` lookup, this separates the two stories by construction — no date filters or prefix filters needed. This also reshaped the beat order: the full intake→evaluation→response loop now closes on Settlement A before the demo pivots to Settlement B for the volume/bulk-advance/deadline/lifecycle beats (see `docs/demo-script.md`, Act 1 / Act 2).

**Status:** Logged. Build impact tracked in `architecture.md` §4.6/§5 (seed script targets the new volume settlement) and in `rawlings-demo-build-schedule.md`'s Two-Settlement Restructure section.

---

### Beat 5 (escalation path, one record) feels too short

**Raised by:** Brian, while reviewing Beat 5.

**Context:** Flagged in passing, not elaborated on yet — Beat 5 is currently one line of talk track (escalation reason + task + deadline) versus Beat 4's fuller treatment of the automated path. Worth a closer look at whether the escalation story needs more room (e.g., showing the queue member who'd pick it up, or what "resolving" it actually looks like) or whether short-and-mirrored is the right call by design.

**Root cause found:** the actual build sets one generic, hardcoded `Escalation_Reason__c` — `"Coverage could not be confirmed automatically"` — for every escalated lien regardless of cause (`flow-build-instructions.md`, step 4a). There was no real story to tell, just a label, which is why the beat couldn't carry more without inventing something.

**Decision:** Give escalation a feasible, specific reason grounded in the RFP's own "liability question" framing — the claimant's health plan enrollment dates on file don't confirm coverage on the treatment date, so eligibility needs to be verified with the health plan before liability can be confirmed. This is a one-line edit to the already-built, already-activated Flow (not a new component) — logged as Task E.1 in `rawlings-demo-build-schedule.md`. Beat 5's talk track now explains the specific reason and what resolving it actually looks like (an ops analyst pulls the real enrollment record from the health plan and either confirms or closes the lien), which also gives the beat more substance without changing its length much.

**Status:** Resolved. `docs/demo-script.md` Beat 5 rewritten; `docs/flow-build-instructions.md` and `rawlings-demo-build-schedule.md` updated to match.

---

### Deadline coloring doesn't actually surface itself to anyone

**Raised by:** Brian, while reviewing Beat 8.

**Context:** `Deadline_Status__c` turning red is a passive formula computation — it doesn't push anything to anyone, unlike escalation, which actively creates a Task and fires a Custom Notification (§3.3). The original Beat 8 talk track ("it flagged itself red") blurred that distinction, implying deadline monitoring was as proactive as escalation when it isn't. Someone still has to already be looking at the right record or list to ever notice.

**Decision:** Build a "Liens Near Deadline" component — logged in `architecture.md` §4.9 — a native Dynamic Related List (Single) on the Settlement record page, filtered to Yellow/Red, non-Closed/Collected liens, sorted soonest-first. No Apex, no LWC, purely declarative. This sits alongside the Summary tiles so a partner sees both the count and the actual at-risk records without leaving the page. The talk track is also corrected to be honest about the difference between this (a computed, always-visible view) and escalation (an active push) rather than implying they work the same way.

**Status:** Logged, not yet built. `docs/demo-script.md` Beat 8 already rewritten to reference the new component and the corrected talk track.

---

### Need an AWS-specific effort estimate for the middleware layer before the real demo

**Raised by:** Brian, while reviewing the corrected Beat 10 close.

**Context:** Beat 10's talk track and `architecture.md` §8 both name the missing piece as "a middleware integration layer (MuleSoft or AWS Transfer Family + Lambda)" — real delivery to an administrator's SFTP server, in either direction, isn't built in this prototype. Brian's read: for this client, AWS is the realistic path, not MuleSoft. If a partner or the consultant asks what it would actually take to build that layer, "MuleSoft or AWS" isn't a real answer — there needs to be a specific, defensible point of view on the AWS Transfer Family + Lambda path: what it involves (SFTP endpoint setup, Lambda for validation/transform, triggering Bulk API 2.0 loads, Platform Event wiring back into Salesforce), rough effort, and rough timeline.

**Open:** This isn't something to resolve in the script — it's a personal prep item. Brian needs to work out a real AWS-specific effort estimate before the demo, separate from anything in this document.

**Status:** Open — prep item, not a script change.
