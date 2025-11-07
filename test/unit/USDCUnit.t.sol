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

    // ---------- Role / grant tests ----------
    function testdeployerHasDefaultAdminRole() public {
        // AccessControl DEFAULT_ADMIN_ROLE should be granted to deployer (msg.sender)
        bytes32 adminRole = i_USDC.DEFAULT_ADMIN_ROLE();
        assertTrue(token.hasRole(adminRole, deployer), "deployer must have DEFAULT_ADMIN_ROLE");
    }

    function test_admin_can_grant_mint_role() public {
        // impersonate deployer (who should have DEFAULT_ADMIN_ROLE)
        vm.prank(deployer);
        token.grantMintRole(aayush);

        bytes32 mintRole = token.MINT_ROLE();
        assertTrue(token.hasRole(mintRole, aayush), "relayer must have MINT_ROLE after grant");
    }

    function test_non_admin_cannot_grant_mint_role() public {
        // non-admin trying to grant should revert
        vm.prank(aayush);
        vm.expectRevert();
        token.grantMintRole(aayush);
    }

    function test_minter_can_mint_and_balance_updates() public {
        uint256 oneUSDC = 1_000_000; // because decimals() == 6
        vm.prank(relayer);
        token.mint(alice, oneUSDC);

        assertEq(token.balanceOf(alice), oneUSDC, "alice should have 1 USDC (6 decimals)");
        assertEq(token.totalSupply(), oneUSDC, "totalSupply should reflect mint");
    }

    function test_unauthorized_mint_reverts() public {
        vm.prank(aayush);
        vm.expectRevert();
        token.mint(aayush, 1_000_000);
    }

    function test_mint_zero_amount_reverts() public {
        // grant role so revert is due to zero amount, not authorization
        vm.prank(deployer);
        token.grantMintRole(relayer);

        vm.prank(relayer);
        vm.expectRevert();
        token.mint(alice, 0);
    }

    function test_burn_reduces_balance_and_supply() public {
        uint256 minted = 2_000_000; // 2 USDC
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice burns part of it
        uint256 burnAmt = 500_000; // 0.5 USDC
        vm.prank(alice);
        token.burn(burnAmt);

        assertEq(token.balanceOf(alice), minted - burnAmt, "alice balance should be reduced by burn");
        assertEq(token.totalSupply(), minted - burnAmt, "totalSupply must be reduced by burn");
    }

    function test_burn_zero_reverts() public {
        // grant minter and mint to alice first
        vm.prank(deployer);
        token.grantMintRole(relayer);

        uint256 minted = 2_000_000; // 2 USDC
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice burns part of it
        uint256 burnAmt = 0;
        vm.prank(alice);
        vm.expectRevert();
        token.burn(burnAmt);
    }

    function test_burnFrom_respects_allowance_and_reduces_it() public {
        // // grant minter and mint to alice
        // vm.prank(deployer);
        // token.grantMintRole(relayer);

        uint256 minted = 3_000_000; // 3 USDC
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice approves relayer to burn 1 USDC
        uint256 allowanceAmt = 1_000_000;
        vm.prank(alice);
        token.approve(relayer, allowanceAmt);
        assertEq(token.allowance(alice, relayer), allowanceAmt, "allowance should be set");

        // relayer calls burnFrom
        vm.prank(relayer);
        token.burnFrom(alice, allowanceAmt);

        assertEq(token.balanceOf(alice), minted - allowanceAmt, "alice balance decreased by burned amount");
        assertEq(token.allowance(alice, relayer), 0, "allowance should be consumed");
        assertEq(token.totalSupply(), minted - allowanceAmt, "totalSupply should reflect burned amount");
    }

    function test_burnFrom_insufficient_allowance_reverts() public {
        // // mint to alice
        // vm.prank(deployer);
        // token.grantMintRole(relayer);

        uint256 minted = 1_500_000;
        vm.prank(relayer);
        token.mint(alice, minted);

        // alice gives small allowance
        vm.prank(alice);
        token.approve(relayer, 100);

        // relayer tries to burn more than allowance -> revert
        vm.prank(relayer);
        vm.expectRevert();
        token.burnFrom(alice, 200);
    }

    function test_decimals_is_six() public {
        assertEq(i_USDC.decimals(), 6, "token decimals must be 6 (USDC-like)");
    }

    function test_minter_cant_mint_if_role_is_revoked() public {
        _revokingroleOfMinter(relayer);
        uint256 oneUSDC = 1_000_000; // because decimals() == 6
        vm.prank(relayer);
        vm.expectRevert();
        token.mint(alice, oneUSDC);
    }

    function test_admin_cant_grantRole_if_renounced_ownership() public {
        _revokingroleOfAdmin();
        vm.prank(deployer);
        vm.expectRevert();
        token.grantMintRole(aayush);
    }

    function _revokingroleOfMinter(address _account) internal {
        bytes32 mintRole = i_USDC.MINT_ROLE();
        vm.prank(deployer);
        token.revokeRole(mintRole, _account);
    }

    function _revokingroleOfAdmin() internal {
        bytes32 adminRole = i_USDC.DEFAULT_ADMIN_ROLE();
        vm.prank(deployer);
        token.renounceRole(adminRole, deployer);
    }
}
