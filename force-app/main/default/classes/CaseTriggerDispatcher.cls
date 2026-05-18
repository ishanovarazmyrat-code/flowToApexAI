/**
 * @description Routes Case trigger events to all active handlers registered in
 *              Trigger_Handler__mdt for Object__c = 'Case'.
 *              Adding a new handler requires no code change — insert a CMT record instead.
 */
public with sharing class CaseTriggerDispatcher {

    @TestVisible static List<Trigger_Handler__mdt> testHandlers;

    public static void dispatch(
        System.TriggerOperation op,
        List<Case> records,
        Map<Id, Case> oldMap
    ) {
        List<SObject> sRecords = records;
        Map<Id, SObject> sOldMap = oldMap != null ? new Map<Id, SObject>(oldMap.values()) : null;

        for (Trigger_Handler__mdt h : activeHandlers('Case')) {
            IFlowMigrationHandler handler =
                (IFlowMigrationHandler) Type.forName(h.Handler_Class__c).newInstance();
            handler.run(op, sRecords, sOldMap);
        }
    }

    private static List<Trigger_Handler__mdt> activeHandlers(String objectName) {
        if (testHandlers != null) return testHandlers;
        return [
            SELECT Handler_Class__c
            FROM   Trigger_Handler__mdt
            WHERE  Object__c = :objectName
            AND    Active__c = true
            ORDER BY Order__c ASC NULLS LAST
        ];
    }
}
