// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IUSDC
/// @notice Interface for your USDCToken contract to be used by bridge contracts or other external systems.
interface IUSDC {
    // ========= ERC20 Standard ========= //
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    // ========= Custom USDC Extensions ========= //
    function mint(address _account, uint256 _value) external;

    function burn(uint256 _value) external;

    function burnFrom(address _account, uint256 _value) external;

    function grantMintRole(address _account) external;

    function renounceRole(bytes32 role, address callerConfirmation) external;

    // ========= Access Control Roles ========= //
    function MINT_ROLE() external view returns (bytes32);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}
