/**
 * @description Routes Lead trigger context to all registered handlers.
 *              Each Flow→Apex conversion produces a separate handler class;
 *              register it by adding ONE line inside dispatch() below.
 *
 *              Each handler's run() method is responsible for filtering by
 *              System.TriggerOperation, so the dispatcher itself stays operation-agnostic.
 */
public with sharing class LeadTriggerDispatcher {

    public static void dispatch(
        System.TriggerOperation op,
        List<Lead> records,
        Map<Id, Lead> oldMap
    ) {
        // -----------------------------------------------------------------
        // Register handlers below — order matters for before-save handlers
        // when one's output is another's input.
        //
        // Example:
        //   LeadAutoConvertOnQualifyHandler.run(op, records, oldMap);
        //   LeadNormalizeCompanyHandler.run(op, records, oldMap);
        // -----------------------------------------------------------------
    }
}
