//SPDX-License-Identifier:MIT
pragma solidity ^0.8.30;
import {USDCToken} from "./USDC.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

error AlreadyProcessed();
error SourceBridgeNotAuthorizedForTransaction(address srcBridgeAddress);
error RelayerNotAuthorized(address relayer);
contract BridgeDestination is AccessControl {
    USDCToken immutable usdc_token;
    mapping(bytes32 => bool) public processed;
    mapping(address => bool) public relayers;
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");
    mapping(uint256 => address) public  sourceBridgeForChain;

    event BridgeExecuted(
        bytes32 messageId,
        uint256 srcChainId,
        address sourceBridgeAddress,
        uint256 nonce,
        address from,
        address to,
        address token,
        uint256 amount,
        address executedBy,
        uint256 timestamp
    );
    event SourceBridgeSet(uint256 chainId, address bridgeAddress);

    constructor(USDCToken _usdc) {
        usdc_token = _usdc;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function executeMint(
        uint256 srcChainId,
        address srcBridgeAddress,
        uint256 nonce,
        address token,
        address from,
        address to,
        uint256 amount
    ) public onlyRole(RELAYER_ROLE) {
        bytes32 messageId = keccak256(
            abi.encodePacked(srcChainId, srcBridgeAddress,token, nonce)
        );

        if (processed[messageId] == true) {
            revert AlreadyProcessed();
        }
        if (sourceBridgeForChain[srcChainId] != srcBridgeAddress) {
            revert SourceBridgeNotAuthorizedForTransaction(srcBridgeAddress);
        }
        if(relayers[msg.sender]==false){
            revert RelayerNotAuthorized(msg.sender);
        }

        processed[messageId] = true;

        usdc_token.mint(to, amount);

        emit BridgeExecuted(
            messageId,
            srcChainId,
            srcBridgeAddress,
            nonce,
            from,
            to,
            token,
            amount,
            msg.sender,
            block.timestamp
        );
    }

    function setSourceBridge(
        uint256 _chainId,
        address _sourceBridgeAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sourceBridgeForChain[_chainId] = _sourceBridgeAddress;
    }

    function grantRelayerRole(address _account) external {
        grantRole(RELAYER_ROLE, _account);
    }
}
