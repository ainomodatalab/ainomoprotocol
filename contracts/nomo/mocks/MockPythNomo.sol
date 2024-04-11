pragma solidity 0.8.13;

import { OwnableUpgradeable } from "../contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IPyth } from "../PythNomo.sol";
import { NomoInterface } from "../../interfaces/NomoInterface.sol";

contract MockPythNomo is OwnableUpgradeable {
    mapping(address => uint256) public assetPrices;

    IPyth public underlyingPythNomo;

    constructor() {}

    function initialize(address underlyingPythNomo_) public initializer {
        __Ownable_init();
        if (underlyingPythNomo_ == address(0)) revert("pyth nomo cannot be zero address");
        underlyingPythNomo = IPyth(underlyingPythNomo_);
    }

    function setPrice(address asset, uint256 price) external {
        assetPrices[asset] = price;
    }

    function getPrice(address token) public view returns (uint256) {
        return assetPrices[token];
    }
}
