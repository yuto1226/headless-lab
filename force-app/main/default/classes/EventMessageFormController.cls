/**
 * Accepts public Experience Cloud event-message submissions from an LWC form.
 */
public with sharing class EventMessageFormController {
    private static final String DEFAULT_ERROR_MESSAGE = '意気込みを送信できませんでした。';

    /**
     * Creates an event message record using the caller's CRUD and FLS permissions.
     *
     * @param attendeeRole participant role selected on the public form
     * @param enthusiasm participant message body
     * @return the Id of the created EventMessage__c record
     * @throws AuraHandledException when validation, permissions, or insert processing fails
     */
    @AuraEnabled
    public static Id submitMessage(String attendeeRole, String enthusiasm) {
        String cleanRole = normalizeRequired(attendeeRole);
        String cleanEnthusiasm = normalizeRequired(enthusiasm);

        if (String.isBlank(cleanRole) || String.isBlank(cleanEnthusiasm)) {
            throw createHandledException(Label.EventMessageForm_Validation_Error);
        }

        ensureCreateAccess();
        return createMessage(cleanRole, cleanEnthusiasm);
    }

    /**
     * Inserts the normalized event message.
     *
     * @param attendeeRole participant role selected on the public form
     * @param enthusiasm participant message body
     * @return the Id of the created EventMessage__c record
     * @throws AuraHandledException when user-mode DML fails
     */
    private static Id createMessage(String attendeeRole, String enthusiasm) {
        try {
            EventMessage__c message = new EventMessage__c(
                AttendeeRole__c = attendeeRole,
                Enthusiasm__c = enthusiasm
            );
            Database.insert(message, AccessLevel.USER_MODE);
            return message.Id;
        } catch (AuraHandledException handledError) {
            throw handledError;
        } catch (Exception error) {
            throw createHandledException(Label.EventMessageForm_Save_Error);
        }
    }

    /**
     * Normalizes user-entered text.
     *
     * @param value form text to normalize
     * @return trimmed text, or null when the value is blank
     */
    private static String normalizeRequired(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    /** Ensures the guest/current user can create the target object and editable fields. */
    private static void ensureCreateAccess() {
        if (!Schema.sObjectType.EventMessage__c.isCreateable()
            || !EventMessage__c.AttendeeRole__c.getDescribe().isCreateable()
            || !EventMessage__c.Enthusiasm__c.getDescribe().isCreateable()) {
            throw createHandledException(Label.EventMessageForm_Save_Error);
        }
    }

    /**
     * Builds the sanitized exception returned to the LWC.
     *
     * @param message candidate user-facing message
     * @return sanitized AuraHandledException for LWC callers
     */
    private static AuraHandledException createHandledException(String message) {
        String safeMessage = String.isBlank(message) ? DEFAULT_ERROR_MESSAGE : message;
        AuraHandledException handledException = new AuraHandledException(safeMessage);
        handledException.setMessage(safeMessage);
        return handledException;
    }
}
