import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";
import fetch from "node-fetch";
import { DynamoDBClient, PutItemCommand, DeleteItemCommand, ScanCommand, GetItemCommand } from "@aws-sdk/client-dynamodb";

const cacheSsmGetParameter = (params, cacheTime) => {
	let lastRefreshed = undefined;
	let lastResult = undefined;
	let queue = Promise.resolve();
	return () => {
		const res = queue.then(async () => {
			const currentTime = new Date().getTime();
			if (lastResult === undefined || lastRefreshed + cacheTime < currentTime) {
				lastResult = await new SSMClient().send(new GetParameterCommand(params));
				lastRefreshed = currentTime;
			}
			return lastResult;
		});
		queue = res.catch(() => {});
		return res;
	};
};

const getParam = cacheSsmGetParameter({Name: process.env.token_parameter, WithDecryption: true}, 15 * 1000);

class TelegramError extends Error {
	constructor(message, response) {
		super(message);
		this.response = response;
	}
}

export const sendTelegramCommand = async (url, params) => {
	const token = (await getParam()).Parameter.Value;

	const res = await fetch(`https://api.telegram.org/bot${token}/${url}`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json"
		},
		body: JSON.stringify(params),
	});
	if (!res.ok) {
		throw new TelegramError(res.statusText, res);
	}
	const result = await res.json();
	if (!result.ok) {
		throw new TelegramError(result.description, res);
	}
	return result;
};

export const handler = async (event) => {
	if (event.setWebhook) {
		const {domain, path_key} = process.env;
		await sendTelegramCommand("setWebhook", {
			url: `${domain}/${path_key}/`
		});
		await sendTelegramCommand("setMyCommands", {
			commands: [
				{
					command: "/start",
					description: "Listen to events",
				},
				{
					command: "/stop",
					description: "Stop listening",
				},
				{
					command: "/status",
					description: "Gets the status",
				},
			]
		});
	}else {
		const client = new DynamoDBClient();
		const {subscribers_table} = process.env;
		const stop = async (chat_id) => {
			await client.send(new DeleteItemCommand({
				TableName: subscribers_table,
				Key: {chat_id: {S: String(chat_id)}},
			}));
		};
		const start = async (chat_id) => {
			await client.send(new PutItemCommand({
				TableName: subscribers_table,
				Item: {
					chat_id: {S: String(chat_id)},
				},
			}));
		};
		const isListening = async (chat_id) => {
			const res = await client.send(new GetItemCommand({
				TableName: subscribers_table,
				Key: {chat_id: {S: String(chat_id)}},
			}));
			return res.Item !== undefined;
		};

		const update = JSON.parse(event.body);
		console.log(update);
		if (update.message) {
			const {message: {chat: {id: chat_id}, text}} = update;
			try {
				if (text === "/start") {
					await start(chat_id);
					await sendTelegramCommand("sendMessage", {
						chat_id,
						text: "Subscribed to updates",
					});
				}
				if (text === "/stop") {
					await stop(chat_id);
					await sendTelegramCommand("sendMessage", {
						chat_id,
						text: "Updates stopped",
					});
				}
				if (text === "/status") {
					const status = await isListening(chat_id);
					await sendTelegramCommand("sendMessage", {
						chat_id,
						text: String(status),
					});
				}
			}catch(e) {
				if (e instanceof TelegramError && e.response.status === 403) {
					await stop(chat_id);
				}else {
					throw e;
				}
			}
		}
		if (update.my_chat_member) {
			if (update.my_chat_member.new_chat_member.status === "kicked") {
				await stop(update.my_chat_member.chat.id);
			}
		}
	}
};

