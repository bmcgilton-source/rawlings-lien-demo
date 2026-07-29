@isTest
private class ClaimantImportServiceTest {

    private static final String HEADER = 'Claimant_Name,Claimant_ID,Health_Plan,Injury_Category,Coverage_Result,Recoverable_Amount\n';

    private static Settlement__c createSettlement() {
        Settlement__c settlement = new Settlement__c(Name = 'Test Settlement');
        insert settlement;
        return settlement;
    }

    private static Account createHealthPlan(String name) {
        Account acc = new Account(Name = name);
        insert acc;
        return acc;
    }

    private static void participate(Id settlementId, Id healthPlanId) {
        insert new Settlement_Health_Plan__c(Settlement__c = settlementId, Health_Plan__c = healthPlanId);
    }

    private static Settlement__c setupSettlementWithPlanA() {
        Settlement__c settlement = createSettlement();
        Account planA = createHealthPlan('Health Plan A');
        participate(settlement.Id, planA.Id);
        return settlement;
    }

    @isTest
    static void testValidHeaderSucceeds() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-001,Health Plan A,Hip Implant,Confirmed,5000\n';

        Test.startTest();
        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));
        Test.stopTest();

        System.assertEquals(1, result.createdCount, 'Valid row with exact header should create a lien');
        System.assertEquals(0, result.rejectedCount, 'No rows should be rejected');
    }

    @isTest
    static void testHeaderMismatchRejectsFileWithoutDml() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = 'Claimant Name,Claimant ID,Health Plan,Injury Category,Coverage Result,Recoverable Amount\n'
            + 'Test Claimant,TST-001,Health Plan A,Hip Implant,Confirmed,5000\n';

        Boolean thrown = false;
        try {
            ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));
        } catch (ClaimantImportService.ClaimantFileException e) {
            thrown = true;
        }

        System.assert(thrown, 'Header mismatch should throw a file-level exception');
        System.assertEquals(0, [SELECT COUNT() FROM Lien__c WHERE Settlement__c = :settlement.Id], 'No liens should be created on header mismatch');
    }

    @isTest
    static void testEmptyFileIsRejected() {
        Settlement__c settlement = setupSettlementWithPlanA();

        Boolean thrown = false;
        try {
            ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(''));
        } catch (ClaimantImportService.ClaimantFileException e) {
            thrown = true;
        }

        System.assert(thrown, 'Empty file should throw a file-level exception');
    }

    @isTest
    static void testHeaderOnlyFileIsRejected() {
        Settlement__c settlement = setupSettlementWithPlanA();

        Boolean thrown = false;
        try {
            ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(HEADER));
        } catch (ClaimantImportService.ClaimantFileException e) {
            thrown = true;
        }

        System.assert(thrown, 'Header-only file should throw a file-level exception');
    }

    @isTest
    static void testValidConfirmedRowCreatesCoverageConfirmedLienAndDraftResponse() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-002,Health Plan A,Hip Implant,Confirmed,5000\n';

        Test.startTest();
        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));
        Test.stopTest();

        System.assertEquals(1, result.automatedCount, 'Confirmed row with positive amount should route to Coverage Confirmed');
        Lien__c lien = [SELECT Stage__c FROM Lien__c WHERE Settlement__c = :settlement.Id LIMIT 1];
        System.assertEquals('Coverage Confirmed', lien.Stage__c);
        List<Response__c> responses = [SELECT Status__c FROM Response__c WHERE Lien__c = :lien.Id];
        System.assertEquals(1, responses.size(), 'Coverage Confirmed lien should get a Draft Response');
        System.assertEquals('Draft', responses[0].Status__c);
    }

    @isTest
    static void testValidUnableToConfirmRowCreatesEscalatedLienAndTask() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-003,Health Plan A,Hip Implant,Unable to Confirm,\n';

        Test.startTest();
        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));
        Test.stopTest();

        System.assertEquals(1, result.escalatedCount, 'Unable to Confirm row should route to Escalated');
        Lien__c lien = [SELECT Stage__c FROM Lien__c WHERE Settlement__c = :settlement.Id LIMIT 1];
        System.assertEquals('Escalated', lien.Stage__c);
        List<Task> tasks = [SELECT Subject FROM Task WHERE WhatId = :lien.Id];
        System.assertEquals(1, tasks.size(), 'Escalated lien should get a review Task');
    }

    @isTest
    static void testMissingClaimantIdRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,,Health Plan A,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('MISSING_CLAIMANT_ID', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testUnknownHealthPlanRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-004,Nonexistent Plan,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('UNKNOWN_HEALTH_PLAN', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testNonparticipatingHealthPlanRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        createHealthPlan('Health Plan B'); // exists as an Account, but never linked to this settlement
        String csv = HEADER + 'Test Claimant,TST-005,Health Plan B,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('NONPARTICIPATING_HEALTH_PLAN', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testNonnumericAmountRejectsRowWithoutFailingImport() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER
            + 'Good Claimant,TST-006,Health Plan A,Hip Implant,Confirmed,5000\n'
            + 'Bad Claimant,TST-007,Health Plan A,Hip Implant,Confirmed,not-a-number\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.createdCount, 'The numeric row should still be created');
        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('INVALID_RECOVERABLE_AMOUNT', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testNegativeAmountRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-008,Health Plan A,Hip Implant,Confirmed,-100\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('NEGATIVE_RECOVERABLE_AMOUNT', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testConfirmedWithBlankAmountRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-009,Health Plan A,Hip Implant,Confirmed,\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('MISSING_RECOVERABLE_AMOUNT', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testConfirmedWithZeroAmountRejectsRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-010,Health Plan A,Hip Implant,Confirmed,0\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('NONPOSITIVE_CONFIRMED_AMOUNT', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testDuplicateClaimantIdInFileRejectsLaterRow() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER
            + 'First Occurrence,TST-011,Health Plan A,Hip Implant,Confirmed,5000\n'
            + 'Second Occurrence,tst-011,Health Plan A,Hip Implant,Confirmed,6000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.createdCount, 'Only the first occurrence should be created');
        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('DUPLICATE_IN_FILE', result.rowErrors[0].rejectionCode);
        Lien__c lien = [SELECT Claimant_Name__c FROM Lien__c WHERE Settlement__c = :settlement.Id LIMIT 1];
        System.assertEquals('First Occurrence', lien.Claimant_Name__c);
    }

    @isTest
    static void testExistingSettlementAndClaimantIdUpdatesInsteadOfInserting() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String firstCsv = HEADER + 'Original Name,TST-012,Health Plan A,Hip Implant,Confirmed,5000\n';
        ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(firstCsv));

        String secondCsv = HEADER + 'Updated Name,TST-012,Health Plan A,Hernia Mesh,Confirmed,7500\n';

        Test.startTest();
        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(secondCsv));
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Second import should not create a new lien');
        System.assertEquals(1, result.updatedCount, 'Second import should update the existing lien');
        System.assertEquals(1, [SELECT COUNT() FROM Lien__c WHERE Settlement__c = :settlement.Id], 'Only one lien should exist for this claimant');
        Lien__c lien = [SELECT Claimant_Name__c, Injury_Category__c, Recoverable_Amount__c FROM Lien__c WHERE Settlement__c = :settlement.Id LIMIT 1];
        System.assertEquals('Updated Name', lien.Claimant_Name__c);
        System.assertEquals('Hernia Mesh', lien.Injury_Category__c);
        System.assertEquals(7500.00, lien.Recoverable_Amount__c);
    }

    @isTest
    static void testAmbiguousExistingLienRejectsRow() {
        Settlement__c settlement = createSettlement();
        Account planA = createHealthPlan('Health Plan A');
        participate(settlement.Id, planA.Id);

        Lien__c dup1 = new Lien__c(
            Settlement__c = settlement.Id,
            Claimant_Name__c = 'Dup One',
            Claimant_ID__c = 'TST-013',
            Health_Plan__c = planA.Id,
            Injury_Category__c = 'Hip Implant',
            Coverage_Result__c = 'Confirmed',
            Recoverable_Amount__c = 100,
            Stage__c = 'Intake',
            Intake_Date__c = Date.today(),
            Response_Deadline__c = Date.today().addDays(90)
        );
        Lien__c dup2 = dup1.clone(false, false, false, false);
        insert new List<Lien__c>{ dup1, dup2 };

        String csv = HEADER + 'Updated Name,TST-013,Health Plan A,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(0, result.createdCount);
        System.assertEquals(0, result.updatedCount);
        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('AMBIGUOUS_EXISTING_LIEN', result.rowErrors[0].rejectionCode);
    }

    @isTest
    static void testMixedFileCommitsValidRowsAndRejectsInvalidRows() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER
            + 'Valid One,TST-020,Health Plan A,Hip Implant,Confirmed,5000\n'
            + 'Valid Two,TST-021,Health Plan A,Hip Implant,Unable to Confirm,\n'
            + 'Invalid Amount,TST-022,Health Plan A,Hip Implant,Confirmed,bad\n'
            + 'Missing Plan,TST-023,,Hip Implant,Confirmed,100\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(4, result.rowsReceived);
        System.assertEquals(2, result.createdCount);
        System.assertEquals(2, result.rejectedCount);
    }

    @isTest
    static void testRejectionCsvIsCreatedAndLinkedToSettlement() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,,Health Plan A,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertNotEquals(null, result.rejectionContentDocumentId, 'A rejection file should be generated');
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :result.rejectionContentDocumentId
            AND LinkedEntityId = :settlement.Id
        ];
        System.assertEquals(1, links.size(), 'The rejection file should be linked to the Settlement');
    }

    @isTest
    static void testRejectionCsvContainsRowNumberCodeAndEscapedReason() {
        Settlement__c settlement = setupSettlementWithPlanA();
        // The quoted claimant name contains an embedded comma; the claimant id column is blank,
        // which triggers MISSING_CLAIMANT_ID. The rejection file must round-trip the comma safely.
        String csv = HEADER + '"Comma, Claimant",,Health Plan A,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('MISSING_CLAIMANT_ID', result.rowErrors[0].rejectionCode);
        System.assertNotEquals(null, result.rejectionContentDocumentId);

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :result.rejectionContentDocumentId
            AND IsLatest = true
        ];
        String body = cv.VersionData.toString();
        System.assert(body.contains('Row_Number'), 'Rejection CSV should include the header row');
        System.assert(body.contains(String.valueOf(result.rowErrors[0].rowNumber)), 'Rejection CSV should include the row number');
        System.assert(body.contains('MISSING_CLAIMANT_ID'), 'Rejection CSV should include the rejection code');
        System.assert(body.contains('"Comma, Claimant"'), 'Rejection CSV should preserve commas inside quoted values');
    }

    @isTest
    static void testNoRejectionFileIsCreatedWhenAllRowsAreValid() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER + 'Test Claimant,TST-030,Health Plan A,Hip Implant,Confirmed,5000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(null, result.rejectionContentDocumentId);
        System.assertEquals(null, result.rejectionFilename);
    }

    @isTest
    static void testReturnedCountsMatchCommittedAndRoutedRecords() {
        Settlement__c settlement = setupSettlementWithPlanA();
        String csv = HEADER
            + 'Confirmed One,TST-040,Health Plan A,Hip Implant,Confirmed,5000\n'
            + 'Confirmed Two,TST-041,Health Plan A,Hip Implant,Confirmed,6000\n'
            + 'Escalated One,TST-042,Health Plan A,Hip Implant,Unable to Confirm,\n'
            + 'Rejected One,TST-042,Health Plan A,Hip Implant,Confirmed,7000\n';

        ClaimantImportResult result = ClaimantImportService.importFromCsv(settlement.Id, Blob.valueOf(csv));

        System.assertEquals(4, result.rowsReceived);
        System.assertEquals(3, result.createdCount);
        System.assertEquals(1, result.rejectedCount);
        System.assertEquals('DUPLICATE_IN_FILE', result.rowErrors[0].rejectionCode);
        System.assertEquals(2, result.automatedCount);
        System.assertEquals(1, result.escalatedCount);
        System.assertEquals(3, [SELECT COUNT() FROM Lien__c WHERE Settlement__c = :settlement.Id]);
    }

    @isTest
    static void testMissingSettlementThrows() {
        String csv = HEADER + 'Test Claimant,TST-050,Health Plan A,Hip Implant,Confirmed,5000\n';

        Boolean thrown = false;
        try {
            ClaimantImportService.importFromCsv(null, Blob.valueOf(csv));
        } catch (ClaimantImportService.ClaimantFileException e) {
            thrown = true;
        }

        System.assert(thrown, 'Expected an exception when no settlement is provided');
    }
}
