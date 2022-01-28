import {sendTelegramCommand} from "./telegram-control.js";
import { DynamoDBClient, paginateScan} from "@aws-sdk/client-dynamodb";

export const handler = async (event) => {
	const client = new DynamoDBClient();
	const {subscribers_table} = process.env;

	for await (const page of paginateScan({client}, {TableName: subscribers_table})) {
		await Promise.all(page.Items.map(async ({chat_id: {S: chat_id}}) => {
			await Promise.all(event.Records.map((async (record) => {
				await sendTelegramCommand("sendMessage", {
					chat_id,
					text: record.Sns.Message,
				});
			})));
		}));
	}
};

