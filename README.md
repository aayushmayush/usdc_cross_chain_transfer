
---

# USDC Cross-Chain Transfer (Sepolia ↔ Arbitrum Sepolia)

This repository is a **minimal educational cross-chain bridge** example.

It shows how to:

* Deploy an **ERC20-like USDC token** on two testnets
* Build a **burn → message → mint** style bridge
* Run an **off-chain relayer** that listens to events on the source chain and executes mints on the destination chain
* Test the whole flow end-to-end with Foundry and small Node.js scripts

> ⚠️ **Not production ready** — this is for learning and experimentation only.
> Do **not** use with real assets or mainnet.

---

## High-Level Idea

We bridge a fake USDC between:

* **Source chain:** Ethereum Sepolia (`SOURCE_CHAIN_ID = 11155111`) 
* **Destination chain:** Arbitrum Sepolia (`DEST_CHAIN_ID = 421614`)
You can use other blockchains just make sure you dont use my deployed contracts in that case. Just redeploy in your own blockchain before running scripts which you will understand below

Flow for a user:

1. User has **USDC on Sepolia**
2. User calls `BridgeSource.bridgeOut(amount, to, dstChainId)`

   * `BridgeSource` calls `USDC_SRC.burnFrom(user, amount)`
   * Emits `BridgeRequest` event (with `from`, `to`, `amount`, `srcChainId`, `dstChainId`, `nonce`, token address, timestamp)
3. **Relayer (off-chain)** listens to `BridgeRequest` on Sepolia

   * Waits for confirmations
   * Computes a `messageId` and checks if already processed on destination
   * Calls `BridgeDestination.executeMint(...)` on Arbitrum
4. `BridgeDestination`:

   * Validates `srcChainId` and `sourceBridgeForChain[srcChainId]`
   * Ensures `messageId` was not processed before
   * Marks `messageId` as processed
   * Mints `amount` of `USDC_DST` to `to` (destination recipient)

Result: User’s USDC is **burned on Sepolia** and **minted on Arbitrum Sepolia**.

---

## Repo Structure

```text
aayushmayush-usdc_cross_chain_transfer/
├── README.md
├── package.json
├── foundry.toml
├── foundry.lock
├── .env.example
├── relayer.js
├── relayer-db.json                 # simple JSON DB for processed messageIds
├── setup_source.js                 # configure source chain + mint test USDC
├── setup_destination.js            # configure destination chain
├── bridge_out.js                   # user script to bridge tokens
├── broadcast/                      # forge script broadcast artifacts
│   ├── DeployBridgeDestination.s.sol/421614/...
│   ├── DeployBridgeSource.s.sol/11155111/...
│   └── DeployUSDC.s.sol/{11155111,421614}/...
├── script/
│   ├── DeployBridgeDestination.s.sol  
│   ├── DeployBridgeSource.s.sol
│   └── USDC/DeployUSDC.s.sol
├── src/
│   ├── USDC.sol                    # ERC20 + AccessControl + 6 decimals
│   ├── BridgeSource.sol            # burns + emits BridgeRequest
│   ├── BridgeDestination.sol       # validates + mints
│   └── interfaces/IUSDC.sol
├── test/
│   ├── USDC/                       # fuzz, invariants, unit tests
│   │   ├── USDCFuzzTests.t.sol
│   │   ├── USDCUnit.t.sol
│   │   ├── InvariantTotalSupply.t.sol
│   │   ├── fuzzTotalSupply.t.sol
│   │   └── handlers/USDCHandler.sol
│   ├── bridge/                     # unit tests for bridge contracts
│   │   ├── bridgeSourceUnitTests.t.sol
│   │   └── bridgeDestinationUnitTest.t.sol
│   └── completeIntegration/
│       └── forkTestSimulationAnvil.t.sol   # 2-fork integration sim
└── .github/workflows/test.yml      # CI – runs forge tests
```

---

## Smart Contracts Overview

### `USDC.sol`

* ERC20 with:

  * `decimals()` = **6** (USDC-style)
  * `MINT_ROLE` via `AccessControl`
* Key functions:

  * `mint(address to, uint256 value) onlyRole(MINT_ROLE)`
  * `burn(uint256 value)` (burn from `msg.sender`)
  * `burnFrom(address from, uint256 value)` (uses allowance)

We deploy **one instance on Sepolia** (`USDC_SRC`) and **one on Arbitrum Sepolia** (`USDC_DST`). They are separate contracts but behave like the same token symbol on each chain.

---

### `BridgeSource.sol`

On **Sepolia**. Responsibilities:

* Tracks:

  * `USDCToken usdc_token` (immutable)
  * `mapping(uint256 => bool) supportedDstChains`
  * `uint256 nonce` (incremental id per bridge request)
* Owned via `Ownable`.

Key function:

```solidity
function bridgeOut(uint256 amount, address to, uint256 dstChainId) external;
```

Steps:

1. Check:

   * `amount > 0`
   * `to != address(0)`
   * `supportedDstChains[dstChainId] == true`
2. Call `usdc_token.burnFrom(msg.sender, amount)`
3. Emit:

```solidity
event BridgeRequest(
  address indexed from,
  address indexed to,
  address indexed token,
  uint256 amount,
  uint256 srcChainId,
  uint256 dstChainId,
  uint256 nonce,
  uint256 timestamp
);
```

4. Increment `nonce`

---

### `BridgeDestination.sol`

On **Arbitrum Sepolia**. Responsibilities:

* Holds:

  * `USDCToken usdc_token` (immutable)
  * `mapping(bytes32 => bool) processed`  (replay protection)
  * `mapping(uint256 => address) sourceBridgeForChain` (trusted source bridges)
  * `RELAYER_ROLE` via `AccessControl`

Key function:

```solidity
function executeMint(
  uint256 srcChainId,
  address srcBridgeAddress,
  uint256 nonce,
  address token,
  address from,
  address to,
  uint256 amount
) external onlyRole(RELAYER_ROLE);
```

Steps:

1. Compute `messageId`:

```solidity
bytes32 messageId = keccak256(
  abi.encodePacked(srcChainId, srcBridgeAddress, token, nonce)
);
```

2. Check:

   * `!processed[messageId]`
   * `sourceBridgeForChain[srcChainId] == srcBridgeAddress`
3. Mark `processed[messageId] = true`
4. Mint: `usdc_token.mint(to, amount)`
5. Emit `BridgeExecuted` event

---

## Off-Chain Relayer (`relayer.js`)

The relayer:

* Connects to:

  * **Sepolia** via `SEPOLIA_RPC_URL`
  * **Arbitrum Sepolia** via `ARB_SEPOLIA_RPC_URL`
* Listens to `BridgeRequest` events on `SOURCE_BRIDGE`
* For each event:

  1. Parses `from, to, token, amount, srcChainId, dstChainId, nonce`
  2. Skips if `dstChainId != DEST_CHAIN_ID`
  3. Waits `CONFIRMATIONS` blocks on Sepolia
  4. Computes **same** `messageId` as contract:

     ```js
     ethers.utils.keccak256(
       ethers.utils.solidityPack(
         ["uint256", "address", "address", "uint256"],
         [srcChainId, SOURCE_BRIDGE, token, nonce]
       )
     );
     ```
  5. Checks `BridgeDestination.processed(messageId) == false`
  6. Optionally checks `sourceBridgeForChain(srcChainId)` matches `SOURCE_BRIDGE`
  7. Calls `executeMint(...)` on Arbitrum as `RELAYER_ADDRESS`
  8. Stores `messageId` in local `relayer-db.json` to avoid duplicates

---

## Prerequisites

* **Node.js** (v18+ recommended)
* **npm** or **yarn** (repo uses plain `npm` in examples)
* **Foundry** (forge + cast)
  Install: see Foundry docs (forgeup)

Make sure `forge` and `cast` are on your PATH.

---

## Install & Setup

### 1. Clone & install JS deps

```bash
git clone <this-repo-url> aayushmayush-usdc_cross_chain_transfer
cd aayushmayush-usdc_cross_chain_transfer

npm install
```

### 2. Copy `.env.example` → `.env`

```bash
cp .env.example .env
```

Fill in:

```env
SEPOLIA_RPC_URL=...           # e.g. Alchemy/Infura Sepolia
ARB_SEPOLIA_RPC_URL=...       # Arbitrum Sepolia RPC

SEPOLIA_PRIVATE_KEY=0x...     # admin on Sepolia (USDC_SRC + BridgeSource owner)
ARB_SEPOLIA_PRIVATE_KEY=0x... # admin on Arbitrum (USDC_DST + BridgeDestination owner)
ANVIL_PRIVATE_KEY=0x...       # used only for local Anvil tests if needed

RELAYER_ADDRESS=0xa4e0...     # EOA of relayer
RELAYER_PRIVATE_KEY=0x...     # same EOA’s private key

CONFIRMATIONS=6
MAX_RETRIES=5
RETRY_BASE_MS=1000

SOURCE_CHAIN_ID=11155111
DEST_CHAIN_ID=421614

USDC_SRC=0xaEa6EF034DcA53DDF3b02B9944E00888543b9bdA
USDC_DST=0x6206521798aD35784A52DDd393f9A242138Ed55E

SOURCE_BRIDGE=0x5388887B8b444170B5fd0F22919073579Cc5bFEC
DEST_BRIDGE=0xb81A7F4dc018ef56481654B5C1c448D5d71FA2cA

USER_PRIVATE_KEY=0x...        # user that holds USDC on Sepolia
DEST_RECEPIENT=0xa4e0...      # recipient on destination chain (can be same as user)

# optional
BRIDGE_AMOUNT=10              # in whole USDC, e.g. 10 => 10 USDC
SOURCE_MINT_AMOUNT=1000       # for setup_source: mint 1000 USDC to user
```

> The addresses for `USDC_SRC`, `USDC_DST`, `SOURCE_BRIDGE`, `DEST_BRIDGE` are already deployed in your current test setup.
> If you redeploy with your own scripts, just update them here.

---

## Contract Deployment (optional / advanced)

You already have broadcast artifacts under `broadcast/`, but if you want to redeploy:

```bash
# Example: deploy USDC to Sepolia
forge script script/USDC/DeployUSDC.s.sol:DeployUSDC \
  --rpc-url $SEPOLIA_RPC_URL --private-key $SEPOLIA_PRIVATE_KEY --broadcast

# Example: deploy USDC to Arbitrum Sepolia
forge script script/USDC/DeployUSDC.s.sol:DeployUSDC \
  --rpc-url $ARB_SEPOLIA_RPC_URL --private-key $ARB_SEPOLIA_PRIVATE_KEY --broadcast

# Example: deploy BridgeSource to Sepolia
forge script script/DeployBridgeSource.s.sol:DeployBridgeSource \
  --rpc-url $SEPOLIA_RPC_URL --private-key $SEPOLIA_PRIVATE_KEY --broadcast

# Example: deploy BridgeDestination to Arbitrum Sepolia
forge script script/DeployBridgeDestination.s.sol:DeployBridgeDestination \
  --rpc-url $ARB_SEPOLIA_RPC_URL --private-key $ARB_SEPOLIA_PRIVATE_KEY --broadcast
```

Then plug the resulting addresses into `.env`.

---

## End-to-End Flow (What to Run, In Order)

### 1. Configure Source Chain + Mint User Balance

```bash
node setup_source.js
```

This script on **Sepolia**:

* Calls `BridgeSource.setSupportedChain(DEST_CHAIN_ID, true)`
* Ensures admin has `MINT_ROLE` on `USDC_SRC`
* Mints `SOURCE_MINT_AMOUNT` USDC to `USER_PRIVATE_KEY` address
* Logs user’s source balance and current `nextNonce()`

### 2. Configure Destination Chain

```bash
node setup_destination.js
```

This script on **Arbitrum Sepolia**:

* Calls `BridgeDestination.setSourceBridge(SOURCE_CHAIN_ID, SOURCE_BRIDGE)`
* Calls `BridgeDestination.grantRelayerRole(RELAYER_ADDRESS)`
* Calls `USDC_DST.grantMintRole(DEST_BRIDGE)`

So now:

* Destination bridge trusts this source bridge
* Relayer is authorized to call `executeMint`
* Destination bridge can mint USDC_DST

### 3. Start the Relayer

In a separate terminal:

```bash
node relayer.js
```

You should see logs like:

```text
Relayer starting
 SOURCE: 0x5388... (Sepolia bridge)
 DEST:   0xb81A... (Arb bridge)
 RELAYER ADDRESS: 0xa4e0...

Listening for BridgeRequest events...
```

Keep this running.

### 4. Trigger a Bridge Out (User Script)

```bash
node bridge_out.js
```

This script on **Sepolia**:

* Uses `USER_PRIVATE_KEY`
* Reads `BRIDGE_AMOUNT` (default 10 USDC)
* Calls `USDC_SRC.approve(SOURCE_BRIDGE, amount)`
* Calls `BridgeSource.bridgeOut(amount, DEST_RECEPIENT, DEST_CHAIN_ID)`
* Logs user’s USDC_SRC balance before/after + `nextNonce`

The relayer will:

* Pick up the `BridgeRequest` event
* Wait `CONFIRMATIONS` on Sepolia
* Call `executeMint(...)` on Arbitrum
* Log success or retries

### 5. Verify Destination Balance

Use `cast` or a block explorer:

```bash
# On Arbitrum Sepolia
cast call $USDC_DST "balanceOf(address)(uint256)" $DEST_RECEPIENT \
  --rpc-url $ARB_SEPOLIA_RPC_URL
```

If `BRIDGE_AMOUNT = 10` and decimals=6, you should see:

* `10000000` (10 * 10⁶)

---

## Running Tests

All tests:

```bash
forge test -vvv
```

What’s covered:

* **USDC tests:**

  * Unit tests for mint/burn/allowance
  * Fuzz tests (randomized amounts)
  * Invariant: `totalSupply == sum(balances)`
* **Bridge tests:**

  * Unit tests for `BridgeSource` and `BridgeDestination`
  * Check reverts when:

    * amount = 0
    * unsupported chain
    * zero address recipient
    * double processing on destination
* **Integration test (`forkTestSimulationAnvil.t.sol`):**

  * Uses two forks (Sepolia + Arb) on Anvil  (anvil --port 8545 --chain-id 11155111 and anvil --port 8546 --chain-id 421614 on two different terminals)

  * Simulates cross-chain flow:

    * Mint on source
    * Approve + bridgeOut
    * Capture event logs
    * Simulate relayer calling `executeMint` on destination

---

## How to Learn From This Repo

Things you can explore / modify:

* Change how `messageId` is computed and see how replay protection works
* Add **fees** to the bridge and pay them to the relayer
* Track more metadata in events (`bridgeId`, `bridgeFee`, etc.)
* Add a “wrapped token” model instead of native mints on destination
* Add a return bridge (Arbitrum → Sepolia) using the same pattern

This repo is deliberately **simple and explicit** so you can:

* Read the Solidity contracts in `src/`
* Run tests in `test/`
* Follow the full path:

  * `bridgeOut` tx → event → relayer.js log → `executeMint` → dst balance

---

