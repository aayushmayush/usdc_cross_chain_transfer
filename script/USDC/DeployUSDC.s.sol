// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {USDCToken} from "../../src/USDC.sol";

contract DeployUSDC is Script {
    function run() external returns (address, address, USDCToken) {
        uint256 deployerKey;
        if (block.chainid == 11155111) {
            deployerKey = vm.envUint("SEPOLIA_PRIVATE_KEY");
        } else if (block.chainid == 421614) {
            deployerKey = vm.envUint("ARB_SEPOLIA_PRIVATE_KEY");
        } else {
            deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
        }

        address minter = vm.addr(deployerKey);

        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployer);

        // Deploy the USDCToken
        USDCToken token = new USDCToken();

        // If a relayer address was provided (non-zero), grant it mint role via wrapper
        if (minter != address(0)) {
            // uses the grantMintRole wrapper on your token contract
            token.grantMintRole(minter);
        } else {
            console.log("No RELAYER_ADDRESS provided; skipping grantMintRole.");
        }

        vm.stopBroadcast();

        return (deployer, minter, token);
    }
}
