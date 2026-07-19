/** Tests the Hosted MCP action that starts reply generation. */
@IsTest
private class EventMessageMCPControllerTest {
    private static final String EXPECTED_MESSAGE =
        'お礼メッセージの一括生成ジョブをバックグラウンドで開始しました。完了までしばらくお待ちください。';

    @IsTest
    static void shouldStartOneBatchAndReturnAcceptanceMessageWhenInvoked() {
        User runningUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(runningUser) {
            // Given: no pending records, so the batch completes without calling Prompt Builder.
            // When
            Test.startTest();
            List<String> responses = EventMessageMCPController.executeReplyBatch();
            Test.stopTest();

            // Then
            Assert.areEqual(1, responses.size(), 'The tool should return one response.');
            Assert.areEqual(EXPECTED_MESSAGE, responses[0],
                'The tool should immediately acknowledge the background job.');

            List<AsyncApexJob> jobs = [
                SELECT Id, ApexClass.Name, JobType
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'EventMessageReplyBatch'
            ];
            Assert.areEqual(1, jobs.size(), 'Exactly one reply batch should be started.');
            Assert.areEqual('BatchApex', jobs[0].JobType,
                'The asynchronous job should be Batch Apex.');
        }
    }
}
