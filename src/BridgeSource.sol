//SPDX-License-Identifier:MIT
pragma solidity ^0.8.30;

import {USDC} from "./USDC.sol";

error AmountShouldBeGreaterThanZero();
error DestinationChainIdNotSupported();
contract BridgeSource {
    USDC usdc_token;
    uint256 nonce;
    mapping(uint256 => bool) public supportedDstChains;



    event BridgeRequest(address indexed from, address indexed to, address indexed token,uint256 amount,uint256 srcChainId,uint256 dstChainId,uint256 nonce, uint256 timestamp);

    constructor(USDC _usdc) {
        usdc_token = _usdc;
        
    }

    function bridgeOut(uint256 _amount,address _to,uint256 _dstChainId) public{
        if(_amount==0){
            revert AmountShouldBeGreaterThanZero();
        }
        if(supportedDstChains[_dstChainId]==false){
            revert DestinationChainIdNotSupported();
        }

        usdc_token.burnFrom(msg.sender,_amount);
        
        

        emit BridgeRequest(msg.sender,_to,address(usdc_token),_amount,block.chainid,_dstChainId,nonce,block.timestamp);
        nonce++;

    }
    function setSupportedChain(uint256 _chainId,bool _value)public{
        supportedDstChains[_chainId]==_value;
    }
    function nextNonce() external view returns (uint256){
        return nonce;
    }

}
