//SPDX-License-Identifier:MIT

pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
error AmountShouldBeGreaterThanZero();

contract USDCToken is ERC20, AccessControl {
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    constructor() ERC20("USDCToken", "USDC") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(
        address _account,
        uint256 _value
    ) external onlyRole(MINT_ROLE) {
        if (_value == 0) {
            revert AmountShouldBeGreaterThanZero();
        }
        _mint(_account, _value);
    }

    function burn(uint256 _value) public {
        if (_value == 0) {
            revert AmountShouldBeGreaterThanZero();
        }
        _burn(msg.sender, _value);
    }

    function burnFrom(address _account, uint256 _value) public virtual {
        if (_value == 0) {
            revert AmountShouldBeGreaterThanZero();
        }
        _spendAllowance(_account, msg.sender, _value);
        _burn(_account, _value);
    }

    function decimals() public pure  override returns (uint8) {
        return 6;
    }

    function grantMintRole(address _account) external {
        grantRole(MINT_ROLE, _account);
    }
}
