public with sharing class FinanceInstructionWriter {

    private static final String CSV_HEADER = 'Instruction_ID,Settlement,Lien_ID,Claimant_ID,Claimant_Name,' +
        'Agreed_Amount,Recovery_Amount,Remittance_Amount,Payment_Variance,Health_Plan_Allocation,' +
        'Rawlings_Allocation,Disbursement_Status,Generated_At_UTC,Generated_By';

    private static final Decimal TOLERANCE = 0.01;

    public class FinanceInstructionResult {
        @AuraEnabled public String filename;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Datetime generatedAt;
        @AuraEnabled public String claimantName;
        @AuraEnabled public Decimal agreedAmount;
        @AuraEnabled public Decimal remittanceAmount;
        @AuraEnabled public Decimal healthPlanAllocation;
        @AuraEnabled public Decimal rawlingsAllocation;
    }

    @AuraEnabled
    public static FinanceInstructionResult generateInstruction(Id lienId) {
        if (lienId == null) {
            throw businessError('The lien could not be found or you do not have access to it.');
        }

        List<Lien__c> liens = [
            SELECT Settlement__r.Name, Claimant_ID__c, Claimant_Name__c, Stage__c,
                   Agreed_Amount__c, Recovery_Amount__c, Remittance_Amount__c, Payment_Variance__c,
                   Health_Plan_Allocation__c, Rawlings_Allocation__c, Disbursement_Status__c
            FROM Lien__c
            WHERE Id = :lienId
        ];
        if (liens.isEmpty()) {
            throw businessError('The lien could not be found or you do not have access to it.');
        }
        Lien__c lien = liens[0];

        validateEligibility(lien);

        Datetime generatedAt = Datetime.now();
        String claimantIdPart = sanitizeForFilename(lien.Claimant_ID__c);
        String timestampPart = generatedAt.formatGmt('yyyyMMdd-HHmmss');
        String filename = 'Finance_Instruction_' + claimantIdPart + '_' + timestampPart + '.csv';
        String instructionId = 'FIN-' + String.valueOf(lien.Id).right(6) + '-' + timestampPart;

        String csv = buildCsv(lien, instructionId, generatedAt);

        ContentVersion cv = new ContentVersion();
        cv.Title = filename.removeEnd('.csv');
        cv.PathOnClient = filename;
        cv.VersionData = Blob.valueOf(csv);
        insert cv;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        ContentDocumentLink link = new ContentDocumentLink();
        link.ContentDocumentId = contentDocumentId;
        link.LinkedEntityId = lien.Id;
        link.ShareType = 'V';
        link.Visibility = 'AllUsers';
        insert link;

        Lien__c lienUpdate = new Lien__c(
            Id = lien.Id,
            Finance_Instruction_Generated_At__c = generatedAt,
            Finance_Instruction_Generated_By__c = UserInfo.getUserId(),
            Finance_Instruction_Filename__c = filename
        );
        update lienUpdate;

        FinanceInstructionResult result = new FinanceInstructionResult();
        result.filename = filename;
        result.contentDocumentId = contentDocumentId;
        result.generatedAt = generatedAt;
        result.claimantName = lien.Claimant_Name__c;
        result.agreedAmount = lien.Agreed_Amount__c;
        result.remittanceAmount = lien.Remittance_Amount__c;
        result.healthPlanAllocation = lien.Health_Plan_Allocation__c;
        result.rawlingsAllocation = lien.Rawlings_Allocation__c;
        return result;
    }

    private static void validateEligibility(Lien__c lien) {
        if (lien.Stage__c != 'Closed') {
            throw businessError('Close the lien before generating a Finance instruction.');
        }
        if (lien.Disbursement_Status__c != 'Approved') {
            throw businessError('Approve the disbursement before generating a Finance instruction.');
        }
        if (lien.Agreed_Amount__c == null || lien.Recovery_Amount__c == null || lien.Remittance_Amount__c == null
            || lien.Health_Plan_Allocation__c == null || lien.Rawlings_Allocation__c == null
            || lien.Agreed_Amount__c < 0 || lien.Recovery_Amount__c < 0 || lien.Remittance_Amount__c < 0
            || lien.Health_Plan_Allocation__c < 0 || lien.Rawlings_Allocation__c < 0) {
            throw businessError('Complete all recovery, remittance, and allocation amounts before generating the instruction.');
        }
        if (lien.Payment_Variance__c == null || lien.Payment_Variance__c.abs() > TOLERANCE) {
            throw businessError('The remittance does not match the agreed amount. Resolve the payment variance first.');
        }
        Decimal allocationTotal = lien.Health_Plan_Allocation__c + lien.Rawlings_Allocation__c;
        if ((allocationTotal - lien.Remittance_Amount__c).abs() > TOLERANCE) {
            throw businessError('Health plan and Rawlings allocations must equal the remittance amount.');
        }
    }

    private static String buildCsv(Lien__c lien, String instructionId, Datetime generatedAt) {
        List<String> row = new List<String>{
            csvField(instructionId),
            csvField(lien.Settlement__r?.Name),
            csvField(lien.Id),
            csvField(lien.Claimant_ID__c),
            csvField(lien.Claimant_Name__c),
            csvField(formatCurrency(lien.Agreed_Amount__c)),
            csvField(formatCurrency(lien.Recovery_Amount__c)),
            csvField(formatCurrency(lien.Remittance_Amount__c)),
            csvField(formatCurrency(lien.Payment_Variance__c)),
            csvField(formatCurrency(lien.Health_Plan_Allocation__c)),
            csvField(formatCurrency(lien.Rawlings_Allocation__c)),
            csvField(lien.Disbursement_Status__c),
            csvField(generatedAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')),
            csvField(UserInfo.getName())
        };
        return CSV_HEADER + '\n' + String.join(row, ',') + '\n';
    }

    private static String csvField(String value) {
        String safeValue = value == null ? '' : value;
        return '"' + safeValue.replace('"', '""') + '"';
    }

    private static String formatCurrency(Decimal value) {
        if (value == null) {
            return '';
        }
        return String.valueOf(value.setScale(2));
    }

    private static String sanitizeForFilename(String claimantId) {
        if (claimantId == null) {
            return '';
        }
        return claimantId.replaceAll('[^A-Za-z0-9_-]', '_');
    }

    private static AuraHandledException businessError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
