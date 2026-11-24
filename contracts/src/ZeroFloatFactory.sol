// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ZeroFloatAccount} from "./ZeroFloatAccount.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/**
 * @title ZeroFloatFactory
 * @notice Factory for deploying deterministic ZeroFloatAccount contracts via CREATE2.
 * @dev Enables off-chain counterfactual address prediction for smart wallets prior to deployment.
 */
contract ZeroFloatFactory {
    /// @notice Default FloatPool contract address wired to created accounts
    address public floatPool;

    /// @notice Default PaymentRequestHub contract address wired to created accounts
    address public hub;

    /// @notice Primary settlement token (mUSD)
    address public immutable token;

    /// @notice Tracks deployed account addresses by owner and salt
    mapping(bytes32 => address) public getAccount;

    /// @notice Registry of recognized accounts created by this factory
    mapping(address => bool) public isAccount;

    /// @notice Emitted when a new ZeroFloatAccount is created
    event AccountCreated(address indexed owner, address indexed account, bytes32 salt);

    error AccountAlreadyExists(address account);
    error DeploymentFailed();
    error InvalidAddress();

    /**
     * @param _floatPool Default FloatPool address
     * @param _hub Default PaymentRequestHub address
     * @param _token Settlement token address (mUSD)
     */
    constructor(address _floatPool, address _hub, address _token) {
        if (_token == address(0)) revert InvalidAddress();
        floatPool = _floatPool;
        hub = _hub;
        token = _token;
    }

    /**
     * @notice Computes deterministic CREATE2 address of an account before deployment.
     * @param owner Address of the account owner.
     * @param salt Unique salt chosen by user or derived from owner address.
     * @return predicted The predicted contract address.
     */
    function getAccountAddress(address owner, bytes32 salt) public view returns (address predicted) {
        bytes memory bytecode =
            abi.encodePacked(type(ZeroFloatAccount).creationCode, abi.encode(owner, floatPool, hub, token));
        bytes32 combinedSalt = keccak256(abi.encode(owner, salt));
        predicted = Create2.computeAddress(combinedSalt, keccak256(bytecode), address(this));
    }

    /**
     * @notice Deploys a new ZeroFloatAccount using CREATE2.
     * @param owner Address of the account owner.
     * @param salt Unique salt for address derivation.
     * @return account The deployed account address.
     */
    function deployAccount(address owner, bytes32 salt) external returns (address account) {
        if (owner == address(0)) revert InvalidAddress();

        bytes32 combinedSalt = keccak256(abi.encode(owner, salt));
        if (getAccount[combinedSalt] != address(0)) {
            revert AccountAlreadyExists(getAccount[combinedSalt]);
        }

        bytes memory bytecode =
            abi.encodePacked(type(ZeroFloatAccount).creationCode, abi.encode(owner, floatPool, hub, token));

        account = Create2.deploy(0, combinedSalt, bytecode);
        if (account == address(0)) revert DeploymentFailed();

        getAccount[combinedSalt] = account;
        isAccount[account] = true;

        emit AccountCreated(owner, account, salt);
    }
}
