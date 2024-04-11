pragma solidity 0.8.13;

import { NomoInterface } from "../interfaces/NomoInterface.sol";
import { IStETH } from "../interfaces/IStETH.sol";
import { ensureNonzeroAddress } from "../contracts/validators.sol";
import { EXP_SCALE } from "../contracts/constants.sol";

contract WstETHNomo is NomoInterface {
    bool public immutable ASSUME_STETH_ETH_EQUIVALENCE;

    IStETH public immutable STETH;

    address public immutable WSTETH_ADDRESS;

    address public immutable WETH_ADDRESS;

    NomoInterface public immutable RESILIENT_NOMO;

    constructor(
        address wstETHAddress,
        address wETHAddress,
        address stETHAddress,
        address resilientNomoAddress,
        bool assumeEquivalence
    ) {
        ensureNonzeroAddress(wstETHAddress);
        ensureNonzeroAddress(wETHAddress);
        ensureNonzeroAddress(stETHAddress);
        ensureNonzeroAddress(resilientNomoAddress);
        WSTETH_ADDRESS = wstETHAddress;
        WETH_ADDRESS = wETHAddress;
        STETH = IStETH(stETHAddress);
        RESILIENT_NOMO = NomoInterface(resilientNomoAddress);
        ASSUME_STETH_ETH_EQUIVALENCE = assumeEquivalence;
    }

    function getPrice(address asset) public view returns (uint256) {
        if (asset != WSTETH_ADDRESS) revert("wrong wstETH address");

        uint256 stETHAmount = STETH.getPooledEthByShares(1 ether);

        uint256 stETHUSDPrice = RESILIENT_NOMO.getPrice(ASSUME_STETH_ETH_EQUIVALENCE ? WETH_ADDRESS : address(STETH));

        return (stETHAmount * stETHUSDPrice) / EXP_SCALE;
    }
}
