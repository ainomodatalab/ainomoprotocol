pragma solidity 0.8.13;

interface NomoInterface {
    function getPrice(address asset) external view returns (uint256);
}

interface ResilientNomoInterface is NomoInterface {
    function updatePrice(address Token) external;

    function updateAssetPrice(address asset) external;

    function getUnderlyingPrice(address Token) external view returns (uint256);
}

interface TwapInterface is NomoInterface {
    function updateTwap(address asset) external returns (uint256);
}

interface BoundValidatorInterface {
    function validatePriceWithAnchorPrice(
        address asset,
        uint256 reporterPrice,
        uint256 anchorPrice
    ) external view returns (bool);
}
