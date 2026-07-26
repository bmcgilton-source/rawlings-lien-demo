@isTest
private class BulkStageTransitionControllerTest {

    private static Settlement__c createSettlement() {
        Settlement__c settlement = new Settlement__c(
            Name = 'Test Bulk Settlement',
            Administrator__c = 'Test Administrator',
            Program_Start_Date__c = Date.today().addDays(-10),
            Response_Window_Days__c = 90,
            Status__c = 'Active'
        );
        insert settlement;
        return settlement;
    }

    // Inserts land at Coverage Confirmed via the "Lien Automation on Create" Flow
    // (Coverage_Result__c = Confirmed, positive Recoverable_Amount__c) — the Flow fires
    // on every insert with no bypass, so this is the only way to get records onto the
    // pipeline, matching the pattern used by the volume seed script (architecture.md §4.6).
    private static List<Lien__c> createConfirmedLiens(Id settlementId, Integer count) {
        List<Lien__c> liens = new List<Lien__c>();
        for (Integer i = 0; i < count; i++) {
            liens.add(new Lien__c(
                Settlement__c = settlementId,
                Claimant_Name__c = 'Test Claimant ' + i,
                Claimant_ID__c = 'TST-' + i,
                Coverage_Result__c = 'Confirmed',
                Recoverable_Amount__c = 5000
            ));
        }
        insert liens;
        return liens;
    }

    @isTest
    static void testGetStageOptions_excludesEscalatedAndClosed() {
        List<String> options = BulkStageTransitionController.getStageOptions();

        System.assert(!options.contains('Escalated'), 'Escalated must never be a From Stage option');
        System.assert(!options.contains('Closed'), 'Closed is terminal and should not be a From Stage option');
        System.assert(options.contains('Coverage Confirmed'), 'Coverage Confirmed should be a valid From Stage');
    }

    @isTest
    static void testPreviewCount_matchesIndependentCount() {
        Settlement__c settlement = createSettlement();
        createConfirmedLiens(settlement.Id, 12);

        Test.startTest();
        Integer preview = BulkStageTransitionController.previewCount(settlement.Id, 'Coverage Confirmed');
        Test.stopTest();

        Integer actual = [
            SELECT COUNT()
            FROM Lien__c
            WHERE Settlement__c = :settlement.Id
            AND Stage__c = 'Coverage Confirmed'
        ];
        System.assertEquals(actual, preview, 'previewCount should match an independent count for the same From Stage');
    }

    @isTest
    static void testEnqueueBulkTransition_movesAllRecords() {
        Settlement__c settlement = createSettlement();
        createConfirmedLiens(settlement.Id, 15);

        Test.startTest();
        Id jobId = BulkStageTransitionController.enqueueBulkTransition(settlement.Id, 'Coverage Confirmed', 'Response Ready');
        Test.stopTest();

        List<Lien__c> liens = [SELECT Stage__c FROM Lien__c WHERE Settlement__c = :settlement.Id];
        System.assertEquals(15, liens.size());
        for (Lien__c lien : liens) {
            System.assertEquals('Response Ready', lien.Stage__c, 'Every Coverage Confirmed lien should advance to Response Ready');
        }

        AsyncApexJob job = [SELECT Status FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', job.Status);
    }

    @isTest
    static void testEnqueueBulkTransition_invalidToStage_throwsException() {
        Settlement__c settlement = createSettlement();

        Boolean exceptionThrown = false;
        try {
            BulkStageTransitionController.enqueueBulkTransition(settlement.Id, 'Coverage Confirmed', 'Closed');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'An invalid From/To pair should throw an AuraHandledException');
    }

    @isTest
    static void testEnqueueBulkTransition_escalatedFromStage_throwsException() {
        Settlement__c settlement = createSettlement();

        Boolean exceptionThrown = false;
        try {
            BulkStageTransitionController.enqueueBulkTransition(settlement.Id, 'Escalated', 'Coverage Confirmed');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'Escalated must never be accepted as a From Stage, even via a direct Apex call bypassing the LWC');
    }

    @isTest
    static void testGetJobStatus_returnsCompletedJob() {
        Settlement__c settlement = createSettlement();
        createConfirmedLiens(settlement.Id, 5);

        Test.startTest();
        Id jobId = BulkStageTransitionController.enqueueBulkTransition(settlement.Id, 'Coverage Confirmed', 'Response Ready');
        Test.stopTest();

        BulkStageTransitionController.BatchJobStatus status = BulkStageTransitionController.getJobStatus(jobId);
        System.assertEquals('Completed', status.status);
        System.assertEquals(0, status.numberOfErrors);
        System.assertEquals(
            status.totalJobItems,
            status.jobItemsProcessed,
            'All batch chunks should be processed once the job is Completed'
        );
    }

    @isTest
    static void testGetJobStatus_unknownJobId_throwsException() {
        Boolean exceptionThrown = false;
        try {
            BulkStageTransitionController.getJobStatus('707000000000000AAA');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'An unknown job Id should throw an AuraHandledException');
    }
}
