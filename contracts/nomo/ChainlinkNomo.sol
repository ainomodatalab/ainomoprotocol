pragma solidity 0.8.13;

import "../interfaces/VBep20Interface.sol";
import "../interfaces/OracleInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import "@contracts/Governance/AccessControlledV8.sol";

contract ChainlinkNomo is AccessControlledV8, NomoInterface {
    struct TokenConfig {
        address asset;
        address feed;
        uint256 maxStalePeriod;
    }

    mapping(address => uint256) public prices;

    mapping(address => TokenConfig) public tokenConfigs;

    event PricePosted(address indexed asset, uint256 previousPriceMantissa, uint256 newPriceMantissa);

    event TokenConfigAdded(address indexed asset, address feed, uint256 maxStalePeriod);

    modifier notNullAddress(address someone) {
        if (someone == address(0)) revert("can't be zero address");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address accessControlManager_) external initializer {
        __AccessControlled_init(accessControlManager_);
    }

    function setDirectPrice(address asset, uint256 price) external notNullAddress(asset) {
        _checkAccessAllowed("setDirectPrice(address,uint256)");

        uint256 previousPriceMantissa = prices[asset];
        prices[asset] = price;
        emit PricePosted(asset, previousPriceMantissa, price);
    }

    function setTokenConfigs(TokenConfig[] memory tokenConfigs_) external {
        if (tokenConfigs_.length == 0) revert("length can't be 0");
        uint256 numTokenConfigs = tokenConfigs_.length;
        for (uint256 i; i < numTokenConfigs; ) {
            setTokenConfig(tokenConfigs_[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setTokenConfig(
        TokenConfig memory tokenConfig
    ) public notNullAddress(tokenConfig.asset) notNullAddress(tokenConfig.feed) {
        _checkAccessAllowed("setTokenConfig(TokenConfig)");

        if (tokenConfig.maxStalePeriod == 0) revert("stale period can't be zero");
        tokenConfigs[tokenConfig.asset] = tokenConfig;
        emit TokenConfigAdded(tokenConfig.asset, tokenConfig.feed, tokenConfig.maxStalePeriod);
    }

    function getPrice(address asset) public view virtual returns (uint256) {
        uint256 decimals;

        if (asset == NATIVE_TOKEN_ADDR) {
            decimals = 18;
        } else {
            IERC20Metadata token = IERC20Metadata(asset);
            decimals = token.decimals();
        }

        return _getPriceInternal(asset, decimals);
    }

    function _getPriceInternal(address asset, uint256 decimals) internal view returns (uint256 price) {
        uint256 tokenPrice = prices[asset];
        if (tokenPrice != 0) {
            price = tokenPrice;
        } else {
            price = _getChainlinkPrice(asset);
        }

        uint256 decimalDelta = 18 - decimals;
        return price * (10 ** decimalDelta);
    }

    function _getChainlinkPrice(
        address asset
    ) private view notNullAddress(tokenConfigs[asset].asset) returns (uint256) {
        TokenConfig memory tokenConfig = tokenConfigs[asset];
        AggregatorInterface feed = AggregatorInterface(tokenConfig.feed);

        uint256 maxStalePeriod = tokenConfig.maxStalePeriod;

        uint256 decimalDelta = 18 - feed.decimals();

        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        if (answer <= 0) revert("chainlink price must be positive");
        if (block.timestamp < updatedAt) revert("updatedAt exceeds block time");

        uint256 deltaTime;
        unchecked {
            deltaTime = block.timestamp - updatedAt;
        }

        if (deltaTime > maxStalePeriod) revert("chainlink price expired");

        return uint256(answer) * (10 ** decimalDelta);
    }
}
