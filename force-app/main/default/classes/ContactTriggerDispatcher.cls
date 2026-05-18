/**
 * @description Routes Contact trigger context to all registered handlers.
 *              Each Flow→Apex conversion produces a separate handler class;
 *              register it by adding ONE line inside dispatch() below.
 *
 *              Each handler's run() method is responsible for filtering by
 *              System.TriggerOperation, so the dispatcher itself stays operation-agnostic.
 */
public with sharing class ContactTriggerDispatcher {

    public static void dispatch(
        System.TriggerOperation op,
        List<Contact> records,
        Map<Id, Contact> oldMap
    ) {
        // -----------------------------------------------------------------
        // Register handlers below — order matters for before-save handlers
        // when one's output is another's input.
        //
        // Example:
        //   ContactNormalizeEmailHandler.run(op, records, oldMap);
        //   ContactCopyAccountPhoneHandler.run(op, records, oldMap);
        // -----------------------------------------------------------------
    }
}
