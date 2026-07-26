@isTest
private class SettlementLienSummaryControllerTest {

    private static Settlement__c createSettlement() {
        Settlement__c settlement = new Settlement__c(
            Name = 'Test Summary Settlement',
            Administrator__c = 'Test Administrator',
            Program_Start_Date__c = Date.today().addDays(-10),
            Response_Window_Days__c = 90,
            Status__c = 'Active'
        );
        insert settlement;
        return settlement;
    }

    // Every insert routes through "Lien Automation on Create" (Coverage Confirmed or Escalated,
    // depending on Coverage_Result__c) — the same constraint the volume seed script works around
    // (architecture.md §4.6). Response_Deadline__c can still be set explicitly on insert; only
    // Stage__c gets overwritten by the Flow, and only a later update can move it further.
    private static Lien__c newConfirmedLien(Id settlementId, String claimantId, Integer deadlineDaysFromToday) {
        return new Lien__c(
            Settlement__c = settlementId,
            Claimant_Name__c = 'Claimant ' + claimantId,
            Claimant_ID__c = claimantId,
            Coverage_Result__c = 'Confirmed',
            Recoverable_Amount__c = 1000,
            Response_Deadline__c = Date.today().addDays(deadlineDaysFromToday)
        );
    }

    private static Lien__c newEscalatedLien(Id settlementId, String claimantId) {
        return new Lien__c(
            Settlement__c = settlementId,
            Claimant_Name__c = 'Claimant ' + claimantId,
            Claimant_ID__c = claimantId,
            Coverage_Result__c = 'Unable to Confirm'
        );
    }

    @isTest
    static void testGetSummary_emptySettlementReturnsZeros() {
        Settlement__c settlement = createSettlement();

        Test.startTest();
        SettlementLienSummaryController.LienSummary summary = SettlementLienSummaryController.getSummary(settlement.Id);
        Test.stopTest();

        System.assertEquals(0, summary.totalLiens);
        System.assertEquals(0, summary.escalatedCount);
        System.assertEquals(0, summary.greenCount);
        System.assertEquals(0, summary.yellowCount);
        System.assertEquals(0, summary.redCount);
        for (SettlementLienSummaryController.StageCount sc : summary.stageCounts) {
            System.assertEquals(0, sc.count, 'Stage ' + sc.stage + ' should be 0 for a settlement with no liens');
        }
    }

    @isTest
    static void testGetSummary_stageCountsInPipelineOrder() {
        Settlement__c settlement = createSettlement();

        List<Lien__c> liens = new List<Lien__c>{
            newConfirmedLien(settlement.Id, 'A1', 90),
            newConfirmedLien(settlement.Id, 'A2', 90),
            newConfirmedLien(settlement.Id, 'A3', 90),
            newEscalatedLien(settlement.Id, 'B1'),
            newEscalatedLien(settlement.Id, 'B2')
        };
        insert liens;

        // Force two of the Coverage Confirmed liens further down the pipeline — an update,
        // not an insert, so it doesn't re-fire the record-created Flow.
        List<Lien__c> confirmed = [
            SELECT Id FROM Lien__c
            WHERE Settlement__c = :settlement.Id AND Stage__c = 'Coverage Confirmed'
            LIMIT 2
        ];
        for (Lien__c lien : confirmed) {
            lien.Stage__c = 'Response Ready';
        }
        update confirmed;

        Test.startTest();
        SettlementLienSummaryController.LienSummary summary = SettlementLienSummaryController.getSummary(settlement.Id);
        Test.stopTest();

        System.assertEquals(5, summary.totalLiens);
        System.assertEquals(2, summary.escalatedCount);

        Map<String, Integer> countsByStage = new Map<String, Integer>();
        List<String> orderedStages = new List<String>();
        for (SettlementLienSummaryController.StageCount sc : summary.stageCounts) {
            countsByStage.put(sc.stage, sc.count);
            orderedStages.add(sc.stage);
        }

        System.assertEquals(1, countsByStage.get('Coverage Confirmed'));
        System.assertEquals(2, countsByStage.get('Response Ready'));
        System.assertEquals(0, countsByStage.get('Intake'));
        System.assertEquals(0, countsByStage.get('Closed'));

        System.assertEquals(
            new List<String>{
                'Intake', 'Coverage Confirmed', 'Response Ready', 'Response Submitted',
                'Negotiation', 'Agreed', 'Pre-Validation', 'Recovery Calculated', 'Collected', 'Closed'
            },
            orderedStages,
            'Stage tiles must appear in pipeline order, not alphabetical'
        );
    }

    @isTest
    static void testGetSummary_deadlineBucketsExcludeClosedAndCollected() {
        Settlement__c settlement = createSettlement();

        List<Lien__c> liens = new List<Lien__c>{
            newConfirmedLien(settlement.Id, 'GREEN', 30),  // Days_Remaining__c > 20
            newConfirmedLien(settlement.Id, 'YELLOW', 15), // 11-20
            newConfirmedLien(settlement.Id, 'RED', 5),     // <= 10
            newConfirmedLien(settlement.Id, 'CLOSEDRED', 5) // would be Red, but moved to Closed below
        };
        insert liens;

        Lien__c toClose = [
            SELECT Id FROM Lien__c
            WHERE Settlement__c = :settlement.Id AND Claimant_ID__c = 'CLOSEDRED'
            LIMIT 1
        ];
        toClose.Stage__c = 'Closed';
        update toClose;

        Test.startTest();
        SettlementLienSummaryController.LienSummary summary = SettlementLienSummaryController.getSummary(settlement.Id);
        Test.stopTest();

        System.assertEquals(1, summary.greenCount);
        System.assertEquals(1, summary.yellowCount);
        System.assertEquals(1, summary.redCount, 'Closed lien must not count toward Red, even with a Red-range deadline');
    }
}
