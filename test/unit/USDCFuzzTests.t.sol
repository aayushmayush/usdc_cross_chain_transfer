// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {USDCToken} from "../../src/USDC.sol";
import {IUSDC} from "../../src/interfaces/IUSDC.sol";
import {DeployUSDC} from "../../script/DeployUSDC.s.sol";

contract TestUSDC is Test {
    USDCToken token;
    address deployer;
    address relayer; // arbitrary relayer address
    IUSDC i_USDC;

    address aayush = makeAddr("aayush");
    address alice = makeAddr("alice");

    function setUp() public {
        // Deploy token as "admin" (this test contract)
        DeployUSDC deploy = new DeployUSDC();
        (deployer, relayer, token) = deploy.run();
        i_USDC = IUSDC(address(token));
    }

    function testFuzz_minter_can_mint_and_balance_updates(uint256 amount) public {
        // skip zero (as requested) and extremely large values that could cause test flakiness
        vm.assume(amount != 0);

        // ensure deployer grants MINT_ROLE to relayer (or aayush depending on your roles)
        vm.prank(deployer);
        token.grantMintRole(relayer);

        // perform mint as relayer
        vm.prank(relayer);
        token.mint(alice, amount);

        // assertions: alice's balance and totalSupply reflect the minted amount
        assertEq(token.balanceOf(alice), amount, "alice should have minted amount");
        assertEq(token.totalSupply(), amount, "totalSupply should reflect mint");
    }

    function testFuzz_burn_reduces_balance_and_supply(uint256 mintAmt, uint256 burnAmt) public {
        // 1️⃣ Bound inputs to realistic values (avoid overflows / invalid fuzz cases)
        vm.assume(mintAmt > 0);
        vm.assume(mintAmt <= 1e30); // optional large upper cap
        vm.assume(burnAmt > 0);
        vm.assume(burnAmt <= mintAmt);

        // // 2️⃣ Grant relayer minting role
        // vm.prank(deployer);
        // token.grantMintRole(relayer);

        // 3️⃣ Mint to Alice
        vm.prank(relayer);
        token.mint(alice, mintAmt);

        // 4️⃣ Alice burns a fuzzed amount
        vm.prank(alice);
        token.burn(burnAmt);

        // 5️⃣ Assertions
        assertEq(token.balanceOf(alice), mintAmt - burnAmt, "Alice's balance should reduce correctly after burn");

        assertEq(token.totalSupply(), mintAmt - burnAmt, "Total supply must decrease equally to burn amount");
    }

    function testFuzz_burnFrom_respects_allowance_and_reduces_it(uint256 minted, uint256 allowanceAmt) public {
        // Basic bounds to avoid pathological fuzz values
        vm.assume(minted > 0);
        vm.assume(minted <= 1e30); // optional cap
        vm.assume(allowanceAmt > 0);
        vm.assume(allowanceAmt <= minted); // allowance cannot exceed minted for this successful path
        vm.assume(allowanceAmt <= 1e30); // optional cap

        // grant relayer mint role
        vm.prank(deployer);
        token.grantMintRole(relayer);

        // mint minted tokens to alice
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice approves relayer to burn `allowanceAmt`
        vm.prank(alice);
        token.approve(relayer, allowanceAmt);

        // sanity check (optional, but keeps parity with original test)
        assertEq(token.allowance(alice, relayer), allowanceAmt, "allowance should be set");

        // relayer calls burnFrom
        vm.prank(relayer);
        token.burnFrom(alice, allowanceAmt);

        // assertions: balances, allowance and totalSupply updated correctly
        assertEq(token.balanceOf(alice), minted - allowanceAmt, "alice balance decreased by burned amount");

        assertEq(token.allowance(alice, relayer), 0, "allowance should be consumed");

        assertEq(token.totalSupply(), minted - allowanceAmt, "totalSupply should reflect burned amount");
    }

    function testFuzz_transfer_have_balance_conserved(uint256 mintAmt, uint256 transferAmt) public {
        // 1️⃣ Bound inputs to realistic values (avoid overflows / invalid fuzz cases)
        vm.assume(mintAmt > 0);
        vm.assume(mintAmt <= 1e30); // optional large upper cap
        vm.assume(transferAmt > 0);
        vm.assume(transferAmt <= mintAmt);

        // // 2️⃣ Grant relayer minting role
        // vm.prank(deployer);
        // token.grantMintRole(relayer);

        // 3️⃣ Mint to Alice
        vm.prank(relayer);
        token.mint(alice, mintAmt);

        // 4️⃣ Alice burns a fuzzed amount
        vm.prank(alice);
        token.transfer(aayush, transferAmt);

        // 5️⃣ Assertions
        assertEq(
            token.balanceOf(alice), mintAmt - transferAmt, "Alice's balance should reduce correctly after transfer"
        );

        assertEq(token.balanceOf(aayush), transferAmt, "Aayush should have transfer amount");
    }

    function testFuzz_transferFrom_respects_allowance_and_reduces_it(uint256 minted, uint256 allowanceAmt) public {
        // Basic bounds to avoid pathological fuzz values
        vm.assume(minted > 0);
        vm.assume(minted <= 1e30); // optional cap
        vm.assume(allowanceAmt > 0);
        vm.assume(allowanceAmt <= minted); // allowance cannot exceed minted for this successful path
        vm.assume(allowanceAmt <= 1e30); // optional cap

        // // grant relayer mint role
        // vm.prank(deployer);
        // token.grantMintRole(relayer);

        // mint minted tokens to alice
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice approves relayer to burn `allowanceAmt`
        vm.prank(alice);
        token.approve(relayer, allowanceAmt);

        // sanity check (optional, but keeps parity with original test)
        assertEq(token.allowance(alice, relayer), allowanceAmt, "allowance should be set");

        // relayer calls burnFrom
        vm.prank(relayer);
        token.transferFrom(alice, aayush, allowanceAmt);

        // assertions: balances, allowance and totalSupply updated correctly
        assertEq(token.balanceOf(alice), minted - allowanceAmt, "alice balance decreased by burned amount");

        assertEq(token.allowance(alice, relayer), 0, "allowance should be consumed");

        assertEq(token.balanceOf(aayush), allowanceAmt, "aayush should have allowance amount");
    }
}
