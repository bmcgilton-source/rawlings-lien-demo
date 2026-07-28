@isTest
private class ResponseFileWriterTest {

    private static Settlement__c createSettlement() {
        Settlement__c settlement = new Settlement__c(
            Name = 'Test Response Settlement',
            Administrator__c = 'Test Administrator',
            Program_Start_Date__c = Date.today().addDays(-10),
            Response_Window_Days__c = 90,
            Status__c = 'Active'
        );
        insert settlement;
        return settlement;
    }

    // Inserts land at Coverage Confirmed, with a Draft Response__c child, via the
    // "Lien Automation on Create" Flow (Coverage_Result__c = Confirmed, positive
    // Recoverable_Amount__c) — matches the pattern in BulkStageTransitionControllerTest.
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
    static void testGenerateResponseFile_marksResponsesSentAndAdvancesStage() {
        Settlement__c settlement = createSettlement();
        List<Lien__c> liens = createConfirmedLiens(settlement.Id, 5);
        Set<Id> lienIds = new Map<Id, Lien__c>(liens).keySet();

        Test.startTest();
        ResponseFileWriter.GenerateResult result = ResponseFileWriter.generateResponseFile(settlement.Id);
        Test.stopTest();

        System.assertEquals(5, result.rows.size());

        List<Lien__c> updatedLiens = [SELECT Stage__c FROM Lien__c WHERE Id IN :lienIds];
        for (Lien__c lien : updatedLiens) {
            System.assertEquals('Response Submitted', lien.Stage__c, 'Every included lien should advance to Response Submitted');
        }

        List<Response__c> responses = [SELECT Status__c, Sent_Date__c FROM Response__c WHERE Lien__c IN :lienIds];
        System.assertEquals(5, responses.size());
        for (Response__c response : responses) {
            System.assertEquals('Sent', response.Status__c, 'Every response tied to an included lien should be marked Sent');
            System.assertEquals(Date.today(), response.Sent_Date__c);
        }

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :settlement.Id
        ];
        System.assertEquals(1, linkCount, 'The generated CSV should be attached to the Settlement');
    }

    @isTest
    static void testGenerateResponseFile_noCoverageConfirmedLiens_throwsException() {
        Settlement__c settlement = createSettlement();

        Boolean exceptionThrown = false;
        try {
            ResponseFileWriter.generateResponseFile(settlement.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'A settlement with no Coverage Confirmed liens should throw an AuraHandledException');
    }

    @isTest
    static void testGenerateResponseFile_nullSettlementId_throwsException() {
        Boolean exceptionThrown = false;
        try {
            ResponseFileWriter.generateResponseFile(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        System.assert(exceptionThrown, 'A null settlementId should throw an AuraHandledException');
    }
}
