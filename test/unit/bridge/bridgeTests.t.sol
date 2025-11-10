// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {USDCToken} from "../../../src/USDC.sol";
import {IUSDC} from "../../../src/interfaces/IUSDC.sol";
import {DeployUSDC} from "../../../script/USDC/DeployUSDC.s.sol";
import {BridgeSource} from "../../../src/BridgeSource.sol";

contract TestUSDC is Test {
    USDCToken token;
    address deployer;
    address relayer; // arbitrary relayer address
    IUSDC i_USDC;
    BridgeSource bridge;

    address aayush = makeAddr("aayush");
    address alice = makeAddr("alice");

    function setUp() public {
        // Deploy token as "admin" (this test contract)
        DeployUSDC deploy = new DeployUSDC();
        (deployer, relayer, token) = deploy.run();
        i_USDC = IUSDC(address(token));
        vm.prank(deployer);
        bridge = new BridgeSource(token);
    }

    function testOnlyAdminCanSetSupportedChain() public {
        vm.prank(deployer);

        bridge.setSupportedChain(1234, true);
    }

    function testOnlyNonAdminCantSetSupportedChain() public {
        vm.prank(aayush);
        vm.expectRevert();
        bridge.setSupportedChain(1234, true);
    }

    function testStartingNonceIsZero() public {
        assertEq(bridge.nextNonce(), 0);
    }

    function testBridgeOut() public {
        _setSupportedChain(1234);
        uint256 minted = 2_000_000_000; // 2000 USDC
        vm.prank(relayer);
        token.mint(aayush, minted);

        assertEq(token.balanceOf(aayush), 2000e6);

        vm.startPrank(aayush);
        token.approve(address(bridge), 100_000_000);
        bridge.bridgeOut(100_000_000, alice, 1234); //100 USDC bridged

        vm.stopPrank();

        assertEq(token.balanceOf(aayush), 1900e6);
        assertEq(bridge.nextNonce(),1);
    }

    function testBridgeOutRevertOnAmountZero() public {
        _setSupportedChain(1234);
        uint256 minted = 2_000_000_000; // 2000 USDC
        vm.prank(relayer);
        token.mint(aayush, minted);

        assertEq(token.balanceOf(aayush), 2000e6);

        vm.startPrank(aayush);
        token.approve(address(bridge), 100_000_000);
        vm.expectRevert();
        bridge.bridgeOut(0, alice, 1234); //100 USDC bridged

        vm.stopPrank();
    }

    function testBridgeOutRevertOnAddressZero() public {
        _setSupportedChain(1234);
        uint256 minted = 2_000_000_000; // 2000 USDC
        vm.prank(relayer);
        token.mint(aayush, minted);

        assertEq(token.balanceOf(aayush), 2000e6);

        vm.startPrank(aayush);
        token.approve(address(bridge), 100_000_000);
        vm.expectRevert();
        bridge.bridgeOut(100_000_000, address(0), 1234); //100 USDC bridged

        vm.stopPrank();
    }
    function testBridgeOutRevertOnUnsupportedDestinationId() public {
        _setSupportedChain(1234);
        uint256 minted = 2_000_000_000; // 2000 USDC
        vm.prank(relayer);
        token.mint(aayush, minted);

        assertEq(token.balanceOf(aayush), 2000e6);

        vm.startPrank(aayush);
        token.approve(address(bridge), 100_000_000);
        vm.expectRevert();
        bridge.bridgeOut(100_000_000, alice, 13456); //100 USDC bridged

        vm.stopPrank();
    }

    function _setSupportedChain(uint256 _id) internal {
        vm.prank(deployer);

        bridge.setSupportedChain(_id, true);
    }
}
