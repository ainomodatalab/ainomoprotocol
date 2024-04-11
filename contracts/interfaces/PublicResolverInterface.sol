pragma solidity 0.8.13;

interface PublicResolverInterface {
    function addr(bytes32 node) external view returns (address payable);
}
