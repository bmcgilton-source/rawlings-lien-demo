public with sharing class ClaimantImportController {

    @AuraEnabled
    public static ClaimantImportResult importClaimants(Id settlementId) {
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'SampleClaimants'
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            throw businessError('Sample file not found. Upload SampleClaimants static resource.');
        }

        try {
            return ClaimantImportService.importFromCsv(settlementId, resources[0].Body);
        } catch (ClaimantImportService.ClaimantFileException e) {
            throw businessError(e.getMessage());
        } catch (DmlException e) {
            throw businessError(e.getMessage());
        }
    }

    private static AuraHandledException businessError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
