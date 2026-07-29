@isTest
private class FinanceInstructionWriterTest {

    private static Settlement__c createSettlement(String name) {
        Settlement__c settlement = new Settlement__c(
            Name = name,
            Administrator__c = 'Test Administrator',
            Program_Start_Date__c = Date.today().addDays(-10),
            Response_Window_Days__c = 90,
            Status__c = 'Active'
        );
        insert settlement;
        return settlement;
    }

    // Insert lands the lien at Coverage Confirmed via the "Lien Automation on Create" Flow
    // (Coverage_Result__c = Confirmed, positive Recoverable_Amount__c). A follow-up update
    // (which the create-only flow does not re-fire on) advances the lien to the eligible state.
    private static Lien__c createLien(Id settlementId, String claimantId, String claimantName) {
        Lien__c lien = new Lien__c(
            Settlement__c = settlementId,
            Claimant_Name__c = claimantName,
            Claimant_ID__c = claimantId,
            Coverage_Result__c = 'Confirmed',
            Recoverable_Amount__c = 15250
        );
        insert lien;
        return lien;
    }

    private static void makeEligible(Lien__c lien) {
        lien.Stage__c = 'Closed';
        lien.Disbursement_Status__c = 'Approved';
        lien.Agreed_Amount__c = 15250;
        lien.Recovery_Amount__c = 15250;
        lien.Remittance_Amount__c = 15250;
        lien.Health_Plan_Allocation__c = 12200;
        lien.Rawlings_Allocation__c = 3050;
        update lien;
    }

    @isTest
    static void testGenerateInstruction_eligibleLien_attachesFileAndUpdatesAudit() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00004', 'Jane Claimant');
        makeEligible(lien);

        Test.startTest();
        FinanceInstructionWriter.FinanceInstructionResult result = FinanceInstructionWriter.generateInstruction(lien.Id);
        Test.stopTest();

        System.assertEquals('Jane Claimant', result.claimantName);
        System.assertEquals(15250, result.agreedAmount);
        System.assertEquals(15250, result.remittanceAmount);
        System.assertEquals(12200, result.healthPlanAllocation);
        System.assertEquals(3050, result.rawlingsAllocation);
        System.assert(result.filename.startsWith('Finance_Instruction_CLM-00004_'));
        System.assert(result.filename.endsWith('.csv'));

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :lien.Id
        ];
        System.assertEquals(1, links.size(), 'The generated CSV should be attached to the Lien');
        System.assertEquals(result.contentDocumentId, links[0].ContentDocumentId);

        Lien__c updatedLien = [
            SELECT Finance_Instruction_Generated_At__c, Finance_Instruction_Generated_By__c, Finance_Instruction_Filename__c
            FROM Lien__c
            WHERE Id = :lien.Id
        ];
        System.assertEquals(result.filename, updatedLien.Finance_Instruction_Filename__c);
        System.assertEquals(UserInfo.getUserId(), updatedLien.Finance_Instruction_Generated_By__c);
        System.assertNotEquals(null, updatedLien.Finance_Instruction_Generated_At__c);
    }

    @isTest
    static void testGenerateInstruction_lienNotClosed_throwsBusinessError() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00005', 'Open Claimant');
        makeEligible(lien);
        lien.Stage__c = 'Agreed';
        update lien;

        Boolean exceptionThrown = false;
        try {
            FinanceInstructionWriter.generateInstruction(lien.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Close the lien before generating a Finance instruction.', e.getMessage());
        }
        System.assert(exceptionThrown, 'A lien that is not Closed should be rejected');

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lien.Id];
        System.assertEquals(0, linkCount, 'No File should be created for an ineligible lien');
    }

    @isTest
    static void testGenerateInstruction_disbursementNotApproved_throwsBusinessError() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00006', 'Pending Claimant');
        makeEligible(lien);
        lien.Disbursement_Status__c = 'Pending Approval';
        update lien;

        Boolean exceptionThrown = false;
        try {
            FinanceInstructionWriter.generateInstruction(lien.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Approve the disbursement before generating a Finance instruction.', e.getMessage());
        }
        System.assert(exceptionThrown, 'A lien without an approved disbursement should be rejected');
    }

    @isTest
    static void testGenerateInstruction_paymentVariance_throwsBusinessError() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00007', 'Variance Claimant');
        makeEligible(lien);
        lien.Remittance_Amount__c = 15000;
        lien.Health_Plan_Allocation__c = 12000;
        lien.Rawlings_Allocation__c = 3000;
        update lien;

        Boolean exceptionThrown = false;
        try {
            FinanceInstructionWriter.generateInstruction(lien.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('The remittance does not match the agreed amount. Resolve the payment variance first.', e.getMessage());
        }
        System.assert(exceptionThrown, 'A lien with nonzero payment variance should be rejected');
    }

    @isTest
    static void testGenerateInstruction_allocationMismatch_throwsBusinessError() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00008', 'Mismatch Claimant');
        makeEligible(lien);
        lien.Health_Plan_Allocation__c = 10000;
        lien.Rawlings_Allocation__c = 3050;
        update lien;

        Boolean exceptionThrown = false;
        try {
            FinanceInstructionWriter.generateInstruction(lien.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('Health plan and Rawlings allocations must equal the remittance amount.', e.getMessage());
        }
        System.assert(exceptionThrown, 'A lien whose allocations do not sum to the remittance should be rejected');
    }

    @isTest
    static void testGenerateInstruction_csvEscaping_quotesAndEscapesEmbeddedCharacters() {
        Settlement__c settlement = createSettlement('Acme "Statewide" Fund, LLC');
        Lien__c lien = createLien(settlement.Id, 'CLM-00009', 'O"Brien, Jane');
        makeEligible(lien);

        Test.startTest();
        FinanceInstructionWriter.FinanceInstructionResult result = FinanceInstructionWriter.generateInstruction(lien.Id);
        Test.stopTest();

        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :result.contentDocumentId
        ];
        String csv = cv.VersionData.toString();
        System.assert(csv.contains('"O""Brien, Jane"'), 'The claimant name should be quoted with doubled embedded quotes');
        System.assert(csv.contains('"Acme ""Statewide"" Fund, LLC"'), 'The settlement name should be quoted with doubled embedded quotes');
    }

    @isTest
    static void testGenerateInstruction_repeatedGeneration_createsTwoFilesAndUpdatesLatestAudit() {
        Settlement__c settlement = createSettlement('Test Finance Settlement');
        Lien__c lien = createLien(settlement.Id, 'CLM-00010', 'Repeat Claimant');
        makeEligible(lien);

        Test.startTest();
        FinanceInstructionWriter.FinanceInstructionResult first = FinanceInstructionWriter.generateInstruction(lien.Id);
        FinanceInstructionWriter.FinanceInstructionResult second = FinanceInstructionWriter.generateInstruction(lien.Id);
        Test.stopTest();

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :lien.Id];
        System.assertEquals(2, linkCount, 'Each generation should attach a new File without removing the prior one');

        Lien__c updatedLien = [
            SELECT Finance_Instruction_Filename__c
            FROM Lien__c
            WHERE Id = :lien.Id
        ];
        System.assertEquals(second.filename, updatedLien.Finance_Instruction_Filename__c, 'The audit fields should reflect the most recent generation');
    }

    @isTest
    static void testGenerateInstruction_missingLien_throwsBusinessError() {
        Boolean exceptionThrown = false;
        try {
            FinanceInstructionWriter.generateInstruction(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            System.assertEquals('The lien could not be found or you do not have access to it.', e.getMessage());
        }
        System.assert(exceptionThrown, 'A null lien id should be rejected');
    }
}
