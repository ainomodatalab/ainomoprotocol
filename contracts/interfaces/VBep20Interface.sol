pragma solidity 0.8.13;

import "@contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface VBep20Interface is IERC20Metadata {
    function underlying() external view returns (address);
}
