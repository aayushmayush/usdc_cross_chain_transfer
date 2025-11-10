//SPDX-License-Identifier:MIT
pragma solidity ^0.8.30;

import {USDCToken} from "./USDC.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
error AmountShouldBeGreaterThanZero();
error DestinationChainIdNotSupported();
error RecepientAddressCannotBeZero();

contract BridgeSource is Ownable {
    USDCToken immutable usdc_token;
    uint256 private nonce;
    mapping(uint256 => bool) public supportedDstChains;

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
    event SupportedChainUpdated(uint256 chainId, bool enabled);

    constructor(USDCToken _usdc) Ownable(msg.sender){
        usdc_token = _usdc;
    }

    function bridgeOut(
        uint256 _amount,
        address _to,
        uint256 _dstChainId
    ) public {
        if (_amount == 0) {
            revert AmountShouldBeGreaterThanZero();
        }
        if (_to == address(0)) {
            revert RecepientAddressCannotBeZero();
        }
        if (supportedDstChains[_dstChainId] == false) {
            revert DestinationChainIdNotSupported();
        }

        usdc_token.burnFrom(msg.sender, _amount);

        emit BridgeRequest(
            msg.sender,
            _to,
            address(usdc_token),
            _amount,
            block.chainid,
            _dstChainId,
            nonce,
            block.timestamp
        );
        nonce++;
    }

    function setSupportedChain(uint256 _chainId, bool _value) public onlyOwner{
        supportedDstChains[_chainId] = _value;
        emit SupportedChainUpdated(_chainId,_value);
    }

    function nextNonce() external view returns (uint256) {
        return nonce;
    }
}
