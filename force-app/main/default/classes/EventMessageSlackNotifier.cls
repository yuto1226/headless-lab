/**
 * Sends Slack notifications for newly created event messages.
 */
public with sharing class EventMessageSlackNotifier implements Queueable, Database.AllowsCallouts {
    private static final String SETTING_NAME = 'Default';
    private static final String ENDPOINT = 'callout:Slack_API/chat.postMessage';
    private static final String METHOD_POST = 'POST';
    private static final String HEADER_CONTENT_TYPE = 'Content-Type';
    private static final String CONTENT_TYPE_JSON = 'application/json';
    private static final String MESSAGE_TEMPLATE = '【{0}】の方から意気込みが届きました！\n「{1}」';
    private static final String DEFAULT_ROLE = '未指定';
    private static final String DEFAULT_ENTHUSIASM = '（未入力）';

    private List<EventMessage__c> eventMessages;

    /**
     * @param eventMessages event message records to include in the Slack notification
     */
    public EventMessageSlackNotifier(List<EventMessage__c> eventMessages) {
        this.eventMessages = eventMessages == null
            ? new List<EventMessage__c>()
            : new List<EventMessage__c>(eventMessages);
    }

    /**
     * Sends one Slack message containing notifications for all supplied event messages.
     *
     * @param context queueable execution context
     * @throws EventMessageSlackNotifierException when Slack settings are missing or Slack returns an error
     */
    public void execute(QueueableContext context) {
        if (this.eventMessages.isEmpty()) {
            return;
        }

        String channelId = getChannelId();
        String text = buildNotificationText(this.eventMessages);
        sendSlackMessage(channelId, text);
    }

    /** Returns the configured Slack channel ID from custom metadata. */
    private static String getChannelId() {
        SlackSetting__mdt setting = SlackSetting__mdt.getInstance(SETTING_NAME);
        if (setting == null || String.isBlank(setting.ChannelId__c)) {
            throw new EventMessageSlackNotifierException('Slack notification channel is not configured.');
        }
        return setting.ChannelId__c;
    }

    /** Builds the combined Slack notification text for the inserted records. */
    private static String buildNotificationText(List<EventMessage__c> messages) {
        List<String> notifications = new List<String>();
        for (EventMessage__c message : messages) {
            notifications.add(String.format(
                MESSAGE_TEMPLATE,
                new List<String>{
                    getDisplayValue(message.AttendeeRole__c, DEFAULT_ROLE),
                    getDisplayValue(message.Enthusiasm__c, DEFAULT_ENTHUSIASM)
                }
            ));
        }
        return String.join(notifications, '\n\n');
    }

    /** Returns a display-safe value for optional text fields. */
    private static String getDisplayValue(String value, String defaultValue) {
        return String.isBlank(value) ? defaultValue : value.trim();
    }

    /** Posts the notification to Slack through the configured named credential. */
    private static void sendSlackMessage(String channelId, String text) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT);
        request.setMethod(METHOD_POST);
        request.setHeader(HEADER_CONTENT_TYPE, CONTENT_TYPE_JSON);
        request.setBody(JSON.serialize(new Map<String, String>{
            'channel' => channelId,
            'text' => text
        }));

        HttpResponse response = new Http().send(request);
        Integer statusCode = response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new EventMessageSlackNotifierException(
                'Slack notification failed with status ' + String.valueOf(statusCode) + '.'
            );
        }
    }

    /**
     * Raised when Slack notification configuration or callout processing fails.
     */
    public class EventMessageSlackNotifierException extends Exception {
    }
}
