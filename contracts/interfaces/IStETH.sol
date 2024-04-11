pragma solidity 0.8.13;

interface IStETH {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
}
