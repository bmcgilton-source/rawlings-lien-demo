public with sharing class SettlementLienSummaryController {

    // Escalated is broken out as its own tile, not part of the pipeline order (architecture.md §4.1/§4.3).
    private static final List<String> STAGE_ORDER = new List<String>{
        'Intake', 'Coverage Confirmed', 'Response Ready', 'Response Submitted',
        'Negotiation', 'Agreed', 'Pre-Validation', 'Recovery Calculated', 'Collected', 'Closed'
    };

    @AuraEnabled(cacheable=true)
    public static LienSummary getSummary(Id settlementId) {
        Map<String, Integer> countsByStage = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Stage__c stage, COUNT(Id) cnt
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            GROUP BY Stage__c
        ]) {
            countsByStage.put((String) ar.get('stage'), (Integer) ar.get('cnt'));
        }

        Integer total = 0;
        for (Integer count : countsByStage.values()) {
            total += count;
        }

        LienSummary summary = new LienSummary();
        summary.totalLiens = total;
        summary.escalatedCount = countsByStage.containsKey('Escalated') ? countsByStage.get('Escalated') : 0;

        summary.stageCounts = new List<StageCount>();
        for (String stage : STAGE_ORDER) {
            Integer count = countsByStage.containsKey(stage) ? countsByStage.get(stage) : 0;
            summary.stageCounts.add(new StageCount(stage, count));
        }

        // Deadline breakdown filters on the underlying Days_Remaining__c number field rather than
        // GROUP BY on the Deadline_Status__c formula (text) field — see architecture.md §4.1 design note.
        summary.greenCount = [
            SELECT COUNT()
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c NOT IN ('Closed', 'Collected')
            AND Days_Remaining__c > 20
        ];
        summary.yellowCount = [
            SELECT COUNT()
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c NOT IN ('Closed', 'Collected')
            AND Days_Remaining__c > 10
            AND Days_Remaining__c <= 20
        ];
        summary.redCount = [
            SELECT COUNT()
            FROM Lien__c
            WHERE Settlement__c = :settlementId
            AND Stage__c NOT IN ('Closed', 'Collected')
            AND Days_Remaining__c <= 10
        ];

        return summary;
    }

    public class LienSummary {
        @AuraEnabled public Integer totalLiens;
        @AuraEnabled public Integer escalatedCount;
        @AuraEnabled public List<StageCount> stageCounts;
        @AuraEnabled public Integer greenCount;
        @AuraEnabled public Integer yellowCount;
        @AuraEnabled public Integer redCount;
    }

    public class StageCount {
        @AuraEnabled public String stage;
        @AuraEnabled public Integer count;

        public StageCount(String stage, Integer count) {
            this.stage = stage;
            this.count = count;
        }
    }
}
