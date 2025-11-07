//SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {USDCToken} from "../../src/USDC.sol";

import {Test} from "forge-std/Test.sol";

contract USDCHandler is Test {
    USDCToken public token;
    address[] private actors;

    constructor(USDCToken _token, address[] memory _actors) {
        token = _token;
        actors = _actors;
    }

    function getActors() public view returns (address[] memory) {
        return actors;
    }

    function mint(uint256 actorIndex, uint256 amount) external {
        if (amount == 0) return;

        actorIndex = actorIndex % actors.length;

        address to = actors[actorIndex];

        try token.mint(to, amount) {} catch {}
    }

    function transfer(
        uint256 fromIndex,
        uint256 toIndex,
        uint256 amount
    ) external {
        fromIndex = fromIndex % actors.length;
        toIndex = toIndex % actors.length;
        address from = actors[fromIndex];
        address to = actors[toIndex];
        if (from == to || amount == 0) return;
        vm.prank(from);
        try token.transfer(to, amount) {} catch {}
    }

    function burn(uint256 actorIndex, uint256 amount) external {
        actorIndex = actorIndex % actors.length;
        address from = actors[actorIndex];
        vm.prank(from);
        try token.burn(amount) {} catch {}
    }
}
