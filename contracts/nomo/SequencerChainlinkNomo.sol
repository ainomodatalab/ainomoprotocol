pragma solidity 0.8.13;

import { ChainlinkNomo } from "./ChainlinkNomo.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SequencerChainlinkNomo is ChainlinkNomo {
    AggregatorV3Interface public immutable sequencer;

    uint256 public constant GRACE_PERIOD_TIME = 3600;

    constructor(AggregatorV3Interface _sequencer) ChainlinkNomo() {
        require(address(_sequencer) != address(0), "zero address");

        sequencer = _sequencer;
    }

    function getPrice(address asset) public view override returns (uint) {
        if (!isSequencerActive()) revert("L2 sequencer unavailable");
        return super.getPrice(asset);
    }

    function isSequencerActive() internal view returns (bool) {
        (int256 answer, uint256 startedAt) = sequencer.latestRoundData();
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME || answer == 1) return false;
        return true;
    }
}
