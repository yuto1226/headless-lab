# Headless360Bot Graph Response

## LLM System Prompt Addendum

Headless360Bot が Salesforce Hosted MCP Server の `GetEventMessageSummaryAction` を使ってイベントの意気込みを集計したら、Slack への回答には必ず視覚的なグラフを含める。

- `summaryJson.roleBreakdown` の `role`, `count`, `percentage`, `emoji`, `textBar` を使い、参加者種別ごとの割合を Slack のテキスト棒グラフで表示する。
- トーンは、小さなマスコットが一生懸命に集計を届けるような、かわいくポップで前向きな日本語にする。特定キャラクターの名前や口癖をそのまま模倣しない。
- グラフは可読性を優先し、各行を `{emoji} {role} {textBar} {percentage}% ({count}件)` の形にそろえる。
- `quickChartUrl` がある場合は、Slack Bot に `chart_url` として渡す。画像グラフが表示できない環境でも、必ず `slackTextChart` を本文に含める。
- 集計対象が 0 件の場合は、未投稿であることを明るく伝え、投稿を促す短い一言で終える。

Example Slack text:

```text
集計できました。みんなの意気込み、ぎゅっと集まっています。

*参加者タイプ別 意気込みグラフ*
🛠️ 管理者 🟩🟩🟩🟩⬜⬜⬜⬜⬜⬜ 40% (2件)
🌟 ユーザー 🟩🟩🟩🟩⬜⬜⬜⬜⬜⬜ 40% (2件)
💻 開発者 🟩🟩⬜⬜⬜⬜⬜⬜⬜⬜ 20% (1件)

小さな意気込みが、会場をぽんっと盛り上げています。
```

## Apex MCP Response Shape

`GetEventMessageSummaryAction` returns one response per request:

```json
{
  "isSuccess": true,
  "totalCount": 5,
  "roleBreakdownJson": "[{\"role\":\"管理者\",\"count\":2,\"percentage\":40.0,\"emoji\":\"🛠️\",\"color\":\"#2F80ED\",\"textBar\":\"🟩🟩🟩🟩⬜⬜⬜⬜⬜⬜\"}]",
  "recentMessagesJson": "[{\"role\":\"管理者\",\"enthusiasm\":\"LTを楽しみにしています\"}]",
  "slackTextChart": "*参加者タイプ別 意気込みグラフ*\\n...",
  "quickChartUrl": "https://quickchart.io/chart?...",
  "summaryJson": "{\"totalCount\":5,\"roleBreakdown\":[...]}"
}
```

## Slack Bolt + QuickChart Block Kit Snippet

```js
import { App } from '@slack/bolt';

const app = new App({
  token: process.env.SLACK_BOT_TOKEN,
  signingSecret: process.env.SLACK_SIGNING_SECRET,
});

function buildBlocksFromSummary(summary) {
  const blocks = [
    {
      type: 'section',
      text: {
        type: 'mrkdwn',
        text: [
          '集計できました。みんなの意気込み、ぎゅっと集まっています。',
          '',
          summary.slackTextChart,
        ].join('\n'),
      },
    },
  ];

  if (summary.quickChartUrl) {
    blocks.push({
      type: 'image',
      image_url: summary.quickChartUrl,
      alt_text: '参加者タイプ別 意気込みグラフ',
      title: {
        type: 'plain_text',
        text: '参加者タイプ別 意気込みグラフ',
        emoji: true,
      },
    });
  }

  return blocks;
}

app.command('/ikigomi-summary', async ({ ack, respond, client }) => {
  await ack();

  const mcpResponse = await callHostedMcpTool({
    toolName: 'GetEventMessageSummaryAction',
    input: [{ recentMessageLimit: 10 }],
  });
  const actionResult = mcpResponse[0];
  const summary = JSON.parse(actionResult.summaryJson);

  await respond({
    text: summary.slackTextChart,
    blocks: buildBlocksFromSummary(summary),
    unfurl_links: false,
    unfurl_media: false,
  });
});

async function callHostedMcpTool({ toolName, input }) {
  // Replace this with your MCP client invocation.
  // Expected return value is the Apex invocable response array.
  throw new Error(`Implement Hosted MCP call for ${toolName}: ${JSON.stringify(input)}`);
}

await app.start(process.env.PORT || 3000);
```
