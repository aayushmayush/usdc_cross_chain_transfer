// relayer.js - plain Node (CommonJS) ready to run with `node relayer.js`
const ethers = require("ethers");
const fs = require("fs");
const path = require("path");
require("dotenv").config();

// ------------------ CONFIG (from .env) ------------------
const SOURCE_RPC = process.env.SOURCE_RPC || process.env.SEPOLIA_RPC_URL;
const DEST_RPC = process.env.DEST_RPC || process.env.ARB_SEPOLIA_RPC_URL;
const SOURCE_BRIDGE = process.env.SOURCE_BRIDGE;
const DEST_BRIDGE = process.env.DEST_BRIDGE;

const SOURCE_CHAIN_ID = Number(process.env.SOURCE_CHAIN_ID || 11155111);
const DEST_CHAIN_ID = Number(process.env.DEST_CHAIN_ID || 421614);

const RELAYER_PK = process.env.RELAYER_PRIVATE_KEY;
const RELAYER_ADDR = process.env.RELAYER_ADDRESS;
const CONFIRMATIONS = Number(process.env.CONFIRMATIONS || 6);
const MAX_RETRIES = Number(process.env.MAX_RETRIES || 5);
const RETRY_BASE_MS = Number(process.env.RETRY_BASE_MS || 1000);

// ------------------ DB ------------------
const DB_FILE = path.join(__dirname, "relayer-db.json");
let db = { processed: {} };
if (fs.existsSync(DB_FILE)) {
    try {
        db = JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
    } catch (e) {
        console.warn("Could not parse db file, starting fresh", e);
    }
}
function saveDb() {
    fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2));
}

// -------- ABI SHAPES (minimal) --------
const SOURCE_ABI = [
    "event BridgeRequest(address indexed from, address indexed to, address indexed token,uint256 amount,uint256 srcChainId,uint256 dstChainId,uint256 nonce, uint256 timestamp)"
];
const DEST_ABI = [
    "function executeMint(uint256 srcChainId,address srcBridgeAddress,uint256 nonce,address token,address from,address to,uint256 amount) external",
    "function processed(bytes32) view returns (bool)",
    "function sourceBridgeForChain(uint256) view returns (address)",
];

function sleep(ms) {
    return new Promise((res) => setTimeout(res, ms));
}

async function main() {
    if (!SOURCE_RPC || !DEST_RPC || !SOURCE_BRIDGE || !DEST_BRIDGE || !RELAYER_PK) {
        console.error("Missing required env. Check .env variables.");
        process.exit(1);
    }

    const srcProvider = new ethers.JsonRpcProvider(SOURCE_RPC);
    const dstProvider = new ethers.JsonRpcProvider(DEST_RPC);

    const relayerWallet = new ethers.Wallet(RELAYER_PK, dstProvider);

    const srcIface = new ethers.Interface(SOURCE_ABI);
    const dstIface = new ethers.Interface(DEST_ABI);


    // event topic (keccak256 signature)
    const bridgeRequestSignature = "BridgeRequest(address,address,address,uint256,uint256,uint256,uint256,uint256)";
    const bridgeRequestTopic = ethers.id(bridgeRequestSignature);

    const srcFilter = {
        address: SOURCE_BRIDGE,
        topics: [bridgeRequestTopic],
    };

    const dstBridgeContract = new ethers.Contract(DEST_BRIDGE, DEST_ABI, relayerWallet);

    console.log("Relayer starting");
    console.log(" SOURCE:", SOURCE_BRIDGE, "via", SOURCE_RPC);
    console.log(" DEST:", DEST_BRIDGE, "via", DEST_RPC);
    console.log(" RELAYER ADDRESS:", RELAYER_ADDR || relayerWallet.address);

    function computeMessageId(srcChainId, srcBridge, tokenAddr, nonce) {
        // match solidity: keccak256(abi.encodePacked(uint256, address, address, uint256))
        return ethers.keccak256(
            ethers.solidityPacked(
                ["uint256", "address", "address", "uint256"],
                [BigInt(srcChainId).toString(), srcBridge, tokenAddr, BigInt(nonce).toString()]
            )
        );
    }

    srcProvider.on(srcFilter, async (log) => {
        try {
            console.log("Event log received, tx:", log.transactionHash);

            const parsed = srcIface.parseLog(log);
            const from = parsed.args.from;
            const to = parsed.args.to;
            const token = parsed.args.token;
            const amount = BigInt(parsed.args.amount.toString());
            const srcChainId = Number(parsed.args.srcChainId.toString());
            const dstChainId = Number(parsed.args.dstChainId.toString());
            const nonce = BigInt(parsed.args.nonce.toString());

            console.log("Parsed:", { from, to, token, amount: amount.toString(), srcChainId, dstChainId, nonce: nonce.toString() });

            if (dstChainId !== DEST_CHAIN_ID) {
                console.log("dstChainId doesn't match this relayer. skipping.");
                return;
            }

            // wait confirmations
            const txBlock = Number(log.blockNumber);
            console.log("Waiting confirmations from block", txBlock);
            while (true) {
                const currentBlock = await srcProvider.getBlockNumber();
                if ((Number(currentBlock) - txBlock) >= CONFIRMATIONS) break;
                await sleep(1000);
            }
            console.log("Confirmed on source chain.");

            const messageId = computeMessageId(srcChainId, SOURCE_BRIDGE, token, nonce);
            console.log("messageId:", messageId);

            // check on dest
            const alreadyProcessed = await dstBridgeContract.processed(messageId);
            if (alreadyProcessed) {
                console.log("Already processed on destination - skipping");
                db.processed[messageId] = true;
                saveDb();
                return;
            }
            if (db.processed[messageId]) {
                console.log("Already processed (local DB) - skipping");
                return;
            }

            // optional: verify sourceBridgeForChain mapping on dest
            try {
                const expected = await dstBridgeContract.sourceBridgeForChain(srcChainId);
                if (expected && expected.toLowerCase() !== SOURCE_BRIDGE.toLowerCase()) {
                    console.warn("Destination expects different source bridge", expected, " — refusing relay.");
                    return;
                }
            } catch (e) {
                console.warn("Could not read sourceBridgeForChain:", e.message || e);
            }

            // prepare call args matching solidity order:
            // (srcChainId, srcBridgeAddress, nonce, token, from, to, amount)
            const callArgs = [
                srcChainId,
                SOURCE_BRIDGE,
                BigInt(nonce).toString(),
                token,
                from,
                to,
                amount.toString(),
            ];

            // submit with retries
            let attempt = 0;
            while (attempt < MAX_RETRIES) {
                attempt++;
                try {
                    console.log("Submitting executeMint attempt", attempt);
                    const tx = await dstBridgeContract.executeMint(...callArgs);
                    console.log("tx sent:", tx.hash);
                    const rec = await tx.wait();
                    console.log("tx mined:", rec.transactionHash);
                    db.processed[messageId] = true;
                    saveDb();
                    console.log("Relay completed for", messageId);
                    break;
                } catch (err) {
                    console.error("executeMint failed:", err && err.message ? err.message : err);
                    if (attempt >= MAX_RETRIES) {
                        console.error("Max retries hit, giving up for this message");
                        break;
                    }
                    const backoff = RETRY_BASE_MS * 2 ** (attempt - 1);
                    console.log("Retrying in", backoff, "ms");
                    await sleep(backoff);
                }
            }
        } catch (e) {
            console.error("Handler error:", e && e.message ? e.message : e);
        }
    });

    console.log("Listening for BridgeRequest events...");
}

main().catch((e) => {
    console.error("Fatal error:", e);
    process.exit(1);
});
