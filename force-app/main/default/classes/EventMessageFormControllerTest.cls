@IsTest
private class EventMessageFormControllerTest {
    private static final String EXPECTED_CHANNEL_ID = 'C0BEZGCPPSP';

    @IsTest
    static void shouldCreateEventMessageWhenInputIsValid() {
        SlackMock mock = new SlackMock();
        mock.expectedTextFragment = '【一般】の方から意気込みが届きました！';
        Test.setMock(HttpCalloutMock.class, mock);
        User eventUser = createEventUser();

        Id messageId;
        System.runAs(eventUser) {
            Test.startTest();
            messageId = EventMessageFormController.submitMessage(' 一般 ', ' LTを楽しみにしています ');
            Test.stopTest();
        }

        EventMessage__c savedMessage = [
            SELECT AttendeeRole__c, Enthusiasm__c
            FROM EventMessage__c
            WHERE Id = :messageId
            LIMIT 1
        ];
        Assert.areEqual('一般', savedMessage.AttendeeRole__c, 'Attendee role should be trimmed and saved.');
        Assert.areEqual(
            'LTを楽しみにしています',
            savedMessage.Enthusiasm__c,
            'Enthusiasm should be trimmed and saved.'
        );
    }

    @IsTest
    static void shouldThrowExceptionWhenRoleIsBlank() {
        User eventUser = createEventUser();

        System.runAs(eventUser) {
            Test.startTest();
            try {
                EventMessageFormController.submitMessage('', 'イベントに参加します');
                Assert.fail('Expected AuraHandledException for blank attendee role.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('必須'),
                    'Exception should explain that required inputs are missing.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shouldThrowExceptionWhenEnthusiasmIsBlank() {
        User eventUser = createEventUser();

        System.runAs(eventUser) {
            Test.startTest();
            try {
                EventMessageFormController.submitMessage('登壇者', '   ');
                Assert.fail('Expected AuraHandledException for blank enthusiasm.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('必須'),
                    'Exception should explain that required inputs are missing.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void shouldThrowSaveExceptionWhenRoleIsRejectedByObjectMetadata() {
        User eventUser = createEventUser();

        System.runAs(eventUser) {
            Test.startTest();
            try {
                EventMessageFormController.submitMessage('未定義ロール', '不正な選択肢を検証します');
                Assert.fail('Expected AuraHandledException when user-mode DML rejects the picklist value.');
            } catch (AuraHandledException error) {
                Assert.isTrue(
                    error.getMessage().contains('送信'),
                    'Exception should use the sanitized save message.'
                );
            }
            Test.stopTest();
        }
    }

    /**
     * Creates a user with the same least-privilege event permission set used by public submissions.
     *
     * @return test user assigned to EventDemo_GuestUser
     */
    private static User createEventUser() {
        String unique = String.valueOf(DateTime.now().getTime())
            + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User eventUser = new User(
            Alias = 'evtusr',
            Email = 'event.user.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'EventUser',
            LanguageLocaleKey = 'ja',
            LocaleSidKey = 'ja_JP',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'Asia/Tokyo',
            Username = 'event.user.' + unique + '@example.com'
        );
        insert eventUser;

        PermissionSet eventPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'EventDemo_GuestUser'
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = eventUser.Id,
            PermissionSetId = eventPermissionSet.Id
        );
        return eventUser;
    }

    /** Mocks the Slack callout queued by the EventMessage__c after-insert trigger. */
    private class SlackMock implements HttpCalloutMock {
        private String expectedTextFragment;

        /**
         * Returns a successful Slack response after validating the outbound request.
         *
         * @param request outbound Slack Web API request
         * @return successful mock Slack response
         */
        public HttpResponse respond(HttpRequest request) {
            Assert.areEqual(
                'callout:Slack_API/chat.postMessage',
                request.getEndpoint(),
                'Slack request should use the configured named credential endpoint.'
            );

            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            Assert.areEqual(
                EXPECTED_CHANNEL_ID,
                payload.get('channel'),
                'Slack payload should use the custom metadata channel ID.'
            );
            Assert.isTrue(
                String.valueOf(payload.get('text')).contains(expectedTextFragment),
                'Slack payload should include the submitted participant role.'
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(JSON.serialize(new Map<String, Object>{ 'ok' => true }));
            return response;
        }
    }
}
