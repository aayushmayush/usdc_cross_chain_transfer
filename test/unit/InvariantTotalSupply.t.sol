//SPDX-License-Identifier:MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {USDCToken} from "../../src/USDC.sol";
import {USDCHandler} from "../handlers/USDCHandler.sol";

contract InvariantTotalSupply is Test {
    USDCToken public token;
    USDCHandler public handler;
     address[] public actors;

    address relayer = makeAddr("relayer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        token = new USDCToken();

        vm.startPrank(address(this));
        token.grantMintRole(relayer);
        vm.stopPrank();

       
        actors = [relayer,alice,bob];
       

        handler = new USDCHandler(token, actors);

        targetContract(address(handler));
    }

    function invariant_totalSupply_equals_sumOfBalances() public {
        uint256 sum = 0;
        address[] memory actors = handler.getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(
            sum,
            token.totalSupply(),
            "Invariant broken: totalSupply != sum of balances"
        );
    }
}
