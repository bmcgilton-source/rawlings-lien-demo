// Seeds ~1,000 synthetic Lien__c records against the "volume" Settlement used for Act 2 of the
// demo script (architecture.md §4.6). Run once via:
//   sf apex run --file scripts/apex/seedVolumeLiens.apex
//
// Prerequisites (architecture.md §5, deployment steps 6-7):
//   1. A second Settlement record already exists, separate from the live-import settlement.
//   2. Import Claimants has run at least once, so the Health Plan A/B/C Accounts exist.
// Update volumeSettlementName below to match that second Settlement's Name before running.

String volumeSettlementName = 'Talc Powder Mass Tort 2023'; // Id a02dL00000p27A8QAI, created by Task R.1

List<Settlement__c> settlements = [SELECT Id FROM Settlement__c WHERE Name = :volumeSettlementName LIMIT 1];
if (settlements.isEmpty()) {
    System.debug(
        'No Settlement found named "' + volumeSettlementName + '". Create the volume Settlement ' +
        'first (architecture.md §5 step 6), then set volumeSettlementName above and re-run.'
    );
    return;
}
Id settlementId = settlements[0].Id;

List<Account> healthPlans = [
    SELECT Id, Name FROM Account WHERE Name IN ('Health Plan A', 'Health Plan B', 'Health Plan C')
];
if (healthPlans.size() < 3) {
    System.debug(
        'Expected 3 Health Plan Accounts (Health Plan A/B/C) — found ' + healthPlans.size() +
        '. Run Import Claimants at least once first so these Accounts exist.'
    );
    return;
}

// Escalated is never a target — every seeded row must insert as Confirmed with a positive
// Recoverable_Amount__c or the on-create Flow forces it to Escalated (architecture.md §4.6).
// Pre-Validation is deliberately excluded from redistribution — it isn't part of
// BulkStageTransitionController's transition map either, so no other mechanism in this build
// ever moves a lien through it.
List<String> redistributionStages = new List<String>{
    'Response Ready', 'Response Submitted', 'Negotiation',
    'Agreed', 'Recovery Calculated', 'Collected', 'Closed'
};
List<String> injuryCategories = new List<String>{ 'Hip Implant', 'Hernia Mesh' };

Integer totalCount = 1000;
Integer redistributeCount = 150; // last 150 of the 1000 move off Coverage Confirmed post-insert

List<Lien__c> toInsert = new List<Lien__c>();
List<String> plannedStage = new List<String>(); // parallel to toInsert; 'Coverage Confirmed' or a redistribution target

for (Integer i = 0; i < totalCount; i++) {
    Lien__c lien = new Lien__c();
    lien.Settlement__c = settlementId;
    lien.Claimant_ID__c = 'SYN-' + String.valueOf(i + 1).leftPad(5, '0');
    lien.Claimant_Name__c = 'Synthetic Claimant ' + String.valueOf(i + 1).leftPad(5, '0');

    Account plan = healthPlans[Math.mod(i, healthPlans.size())];
    lien.Health_Plan__c = plan.Id;
    lien.Health_Plan_Text__c = plan.Name;
    lien.Injury_Category__c = injuryCategories[Math.mod(i, injuryCategories.size())];

    lien.Coverage_Result__c = 'Confirmed';
    lien.Recoverable_Amount__c = 1500 + Math.mod(i * 37, 8500);

    // All rows insert at Intake so the on-create Flow evaluates them; rows past index 849
    // get moved to a downstream stage by the separate post-insert update below.
    lien.Stage__c = 'Intake';

    Boolean isRedistributed = i >= (totalCount - redistributeCount);
    if (isRedistributed) {
        Integer stageIndex = Math.mod(i, redistributionStages.size());
        String targetStage = redistributionStages[stageIndex];
        plannedStage.add(targetStage);
        // Older intake dates the further along the pipeline, so downstream liens read as
        // having been in-flight longer rather than all landing on the same day.
        Integer depth = stageIndex + 1;
        lien.Intake_Date__c = Date.today().addDays(-(40 * depth + Math.mod(i, 20)));
    } else {
        plannedStage.add('Coverage Confirmed');
        lien.Intake_Date__c = Date.today().addDays(-(10 + Math.mod(i, 60)));
    }

    // Randomized -15 to +75 days out, per architecture.md §4.6, so Green/Yellow/Red spread
    // realistically rather than clustering in one bucket.
    lien.Response_Deadline__c = Date.today().addDays(Math.mod(i * 29, 91) - 15);

    toInsert.add(lien);
}

insert toInsert;
System.debug('Inserted ' + toInsert.size() + ' synthetic Liens.');

List<Lien__c> toRedistribute = new List<Lien__c>();
for (Integer i = 0; i < toInsert.size(); i++) {
    if (plannedStage[i] != 'Coverage Confirmed') {
        toRedistribute.add(new Lien__c(Id = toInsert[i].Id, Stage__c = plannedStage[i]));
    }
}
update toRedistribute;
System.debug('Redistributed ' + toRedistribute.size() + ' Liens across downstream stages.');

Map<String, Integer> finalCounts = new Map<String, Integer>();
for (AggregateResult ar : [
    SELECT Stage__c stage, COUNT(Id) cnt
    FROM Lien__c
    WHERE Settlement__c = :settlementId AND Claimant_ID__c LIKE 'SYN-%'
    GROUP BY Stage__c
]) {
    finalCounts.put((String) ar.get('stage'), (Integer) ar.get('cnt'));
}
System.debug('Final stage distribution for synthetic Liens: ' + finalCounts);
