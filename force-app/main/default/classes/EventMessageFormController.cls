/**
 * Accepts public Experience Cloud event-message submissions from an LWC form.
 */
public without sharing class EventMessageFormController {
    private static final String DEFAULT_ERROR_MESSAGE = '意気込みを送信できませんでした。';
    private static final String DEFAULT_READ_ERROR_MESSAGE = 'メッセージ一覧を取得できませんでした。';
    private static final Integer TIMELINE_LIMIT = 50;

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
     * Retrieves the public timeline and the latest state of a submitted message.
     *
     * @param messageId optional EventMessage__c record Id to monitor for an AI reply
     * @return timeline records and the monitored record state, when available
     * @throws AuraHandledException when read permissions or query processing fail
     */
    @AuraEnabled
    public static MessageFeedResponse getMessageFeed(Id messageId) {
        try {
            ensureReadAccess();

            List<EventMessage__c> timelineRecords = [
                SELECT Id, AttendeeRole__c, Enthusiasm__c, ReplyMessage__c, CreatedDate
                FROM EventMessage__c
                WITH SECURITY_ENFORCED
                ORDER BY CreatedDate DESC
                LIMIT :TIMELINE_LIMIT
            ];

            MessageFeedItem submittedMessage;
            if (messageId != null) {
                List<EventMessage__c> submittedRecords = [
                    SELECT Id, AttendeeRole__c, Enthusiasm__c, ReplyMessage__c, CreatedDate
                    FROM EventMessage__c
                    WHERE Id = :messageId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!submittedRecords.isEmpty()) {
                    submittedMessage = new MessageFeedItem(submittedRecords[0]);
                }
            }

            return new MessageFeedResponse(timelineRecords, submittedMessage);
        } catch (AuraHandledException handledError) {
            throw handledError;
        } catch (Exception error) {
            throw createHandledException(DEFAULT_READ_ERROR_MESSAGE);
        }
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

    /** Ensures the guest/current user can read the timeline fields. */
    private static void ensureReadAccess() {
        if (!Schema.sObjectType.EventMessage__c.isAccessible()
            || !EventMessage__c.AttendeeRole__c.getDescribe().isAccessible()
            || !EventMessage__c.Enthusiasm__c.getDescribe().isAccessible()
            || !EventMessage__c.ReplyMessage__c.getDescribe().isAccessible()
            || !EventMessage__c.CreatedDate.getDescribe().isAccessible()) {
            throw createHandledException(DEFAULT_READ_ERROR_MESSAGE);
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

    /** Response returned to the polling LWC. */
    public class MessageFeedResponse {
        /** Newest event messages for the public timeline. */
        @AuraEnabled
        public List<MessageFeedItem> messages { get; set; }
        /** Latest state of the viewer's submitted message, when an Id is monitored. */
        @AuraEnabled
        public MessageFeedItem submittedMessage { get; set; }

        /**
         * Builds the response for LWC polling.
         *
         * @param timelineRecords newest event messages for the public timeline
         * @param submittedMessage latest state of the viewer's submitted message
         */
        public MessageFeedResponse(List<EventMessage__c> timelineRecords, MessageFeedItem submittedMessage) {
            this.messages = new List<MessageFeedItem>();
            for (EventMessage__c timelineRecord : timelineRecords) {
                this.messages.add(new MessageFeedItem(timelineRecord));
            }
            this.submittedMessage = submittedMessage;
        }
    }

    /** Timeline item returned to the LWC. */
    public class MessageFeedItem {
        /** EventMessage__c record Id. */
        @AuraEnabled
        public Id id { get; set; }
        /** Participant role selected on the public form. */
        @AuraEnabled
        public String attendeeRole { get; set; }
        /** Participant enthusiasm message. */
        @AuraEnabled
        public String enthusiasm { get; set; }
        /** Agentforce-generated thank-you reply, when available. */
        @AuraEnabled
        public String replyMessage { get; set; }
        /** Record creation timestamp. */
        @AuraEnabled
        public Datetime createdDate { get; set; }

        /**
         * Maps an event message record into an Aura-safe DTO.
         *
         * @param message source event message record
         */
        public MessageFeedItem(EventMessage__c message) {
            this.id = message.Id;
            this.attendeeRole = message.AttendeeRole__c;
            this.enthusiasm = message.Enthusiasm__c;
            this.replyMessage = message.ReplyMessage__c;
            this.createdDate = message.CreatedDate;
        }
    }
}
