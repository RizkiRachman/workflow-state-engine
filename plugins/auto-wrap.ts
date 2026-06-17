import {appendFileSync, mkdirSync} from "fs";
import {resolve} from "path";

const ENABLED = process.env.AUTO_WRAP_ENABLED !== "false";
const HINT = "[workflow-contract-state]";
const LOG = resolve(process.env.OPENCODE_DIR || process.cwd(), ".opencode/auto-wrap.log");

function log(msg: string) {
    const line = `[${new Date().toISOString()}] [INFO] ${msg}\n`;
    appendFileSync(LOG, line, "utf-8");
}

interface MessagePart {
    type: string;
    text: string;
}

interface MessageInfo {
    role: string;
}

interface Message {
    info: MessageInfo;
    parts: MessagePart[];
}

const AutoWrapPlugin = async (): Promise<Record<string, unknown>> => {
    if (!ENABLED) return {};

    mkdirSync(resolve(LOG, ".."), {recursive: true});
    log("plugin.load: enabled=true");

    const seen = new Set<string>();

    return {
        "experimental.chat.messages.transform": async (
            _input: Record<string, never>,
            output: { messages: Message[] },
        ): Promise<void> => {
            try {
                output.messages
                    .filter((m) => m.info?.role === "user")
                    .forEach((m) => {
                        m.parts.forEach((p) => {
                            if (p.type === "text") {
                                const raw = (p.text ?? "").replace(/[\r\n]+/g, " ").trim();
                                if (raw.includes(HINT) || seen.has(raw)) return;
                                seen.add(raw);
                                p.text = `${HINT} ${raw}`;
                                log(`wrapped: "${p.text}"`);
                            }
                        });
                    });
            } catch (err) {
                log(`transform error: ${err}`);
            }
        },
    };
};

export default AutoWrapPlugin;
