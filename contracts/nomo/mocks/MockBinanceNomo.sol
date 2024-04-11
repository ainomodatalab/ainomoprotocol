pragma solidity 0.8.13;

import { OwnableUpgradeable } from "../contracts-upgradeable/access/OwnableUpgradeable.sol";
import { NomoInterface } from "../../interfaces/NomoInterface.sol";

contract MockBinanceNomo is OwnableUpgradeable, NomoInterface {
    mapping(address => uint256) public assetPrices;

    constructor() {}

    function initialize() public initializer {}

    function setPrice(address asset, uint256 price) external {
        assetPrices[asset] = price;
    }

    function getPrice(address token) public view returns (uint256) {
        return assetPrices[token];
    }
}
