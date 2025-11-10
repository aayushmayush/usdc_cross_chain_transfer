// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {USDCToken} from "../../../src/USDC.sol";
import {IUSDC} from "../../../src/interfaces/IUSDC.sol";
import {DeployUSDC} from "../../../script/USDC/DeployUSDC.s.sol";

contract TestUSDC is Test {
    USDCToken token;
    address deployer;
    address relayer; // arbitrary relayer address
    IUSDC i_USDC;
    address admin;

    address aayush = makeAddr("aayush");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Deploy token as "admin" (this test contract)
        DeployUSDC deploy = new DeployUSDC();
        (deployer, relayer, token) = deploy.run();
        i_USDC = IUSDC(address(token));
        admin = deployer;
    }

    function test_fuzz_totalSupply_equals_sumOfBalances(uint256 seed) public {
        if (seed == 0) {
            seed = 1;
        }

        address[4] memory actors = [relayer, aayush, alice, bob];

        uint256 ops = 200;

        for (uint256 i = 0; i < ops; ++i) {
            uint256 rand = uint256(keccak256(abi.encodePacked(seed, i)));

            uint8 op = uint8(rand % 5); //0..4

            uint amt = (rand % 1_000_000) + 1;

            address actor = actors[rand % actors.length];

            address target = actors[(rand / 7) % actors.length];

            // perform operation; use try/catch to skip reverts (we still require invariant)
            if (op == 0) {
                // mint: only relayer (if has role) should succeed
                try token.mint(actor, amt) {
                    // minted
                } catch {
                    // ignore revert, state unchanged
                }
            } else if (op == 1) {
                // transfer from actor -> target (may revert if balance insufficient)
                // impersonate actor to attempt transfer
                vm.prank(actor);
                try token.transfer(target, amt) returns (bool) {} catch {}
            } else if (op == 2) {
                // approve + burnFrom: actor approves relayer, relayer attempts burnFrom
                vm.prank(actor);
                try token.approve(relayer, amt) returns (bool) {} catch {}

                vm.prank(relayer);
                try token.burnFrom(actor, amt) {} catch {}
            } else if (op == 3) {
                // burn by actor
                vm.prank(actor);
                try token.burn(amt) {} catch {}
            } else {
                // op == 4: toggle relayer mint role randomly (grant or revoke)
                if ((rand & 1) == 0) {
                    // grant
                    vm.prank(admin);
                    try token.grantMintRole(relayer) {} catch {}
                } else {
                    // revoke
                    vm.prank(admin);
                    try token.revokeRole(token.MINT_ROLE(), relayer) {} catch {}
                }
            }

            uint256 sum = 0;
            for (uint256 j = 0; j < actors.length; ++j) {
                sum += token.balanceOf(actors[j]);
            }

            uint256 total = token.totalSupply();
            // assert equality every iteration — if it ever fails, Foundry will report the seed & step
            assertEq(
                total,
                sum,
                "invariant broken: totalSupply != sum(balances)"
            );
        }
    }
}
