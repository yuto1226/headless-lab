/**
 * Exposes event-message reply generation as a Salesforce Hosted MCP tool.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
global with sharing class EventMessageMCPController {
    private static final String ACCEPTED_MESSAGE =
        'お礼メッセージの一括生成ジョブをバックグラウンドで開始しました。完了までしばらくお待ちください。';

    /**
     * Starts one background batch job for all pending event messages.
     * This tool intentionally exposes no input parameters.
     *
     * @return one immediate job-acceptance message
     */
    @InvocableMethod(
        label='未処理のお礼メッセージを一括生成'
        description='お礼メッセージが未作成（Status__c が「受付済」）の全レコードを対象に、Batch Apexを1回だけ起動します。引数は不要です。'
        category='Headless360Bot'
    )
    global static List<String> executeReplyBatch() {
        Database.executeBatch(new EventMessageReplyBatch(), 1);
        return new List<String>{ ACCEPTED_MESSAGE };
    }
}
