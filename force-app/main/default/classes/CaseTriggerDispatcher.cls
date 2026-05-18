/**
 * @description Routes Case trigger context to all registered handlers.
 *              Each Flow→Apex conversion produces a separate handler class;
 *              register it by adding ONE line inside dispatch() below.
 *
 *              Each handler's run() method is responsible for filtering by
 *              System.TriggerOperation, so the dispatcher itself stays operation-agnostic.
 */
public with sharing class CaseTriggerDispatcher {

    public static void dispatch(
        System.TriggerOperation op,
        List<Case> records,
        Map<Id, Case> oldMap
    ) {
        // -----------------------------------------------------------------
        // Register handlers below — order matters for before-save handlers
        // when one's output is another's input.
        //
        // Example:
        //   CaseAutoAssignPriorityHandler.run(op, records, oldMap);
        //   CaseEscalateOnReopenHandler.run(op, records, oldMap);
        // -----------------------------------------------------------------
    }
}
