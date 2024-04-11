pragma solidity 0.8.13;

import "../interfaces/VBep20Interface.sol";
import "../interfaces/NomoInterface.sol";
import "@contracts/Governance/AccessControlledV8.sol";

contract BoundValidator is AccessControlledV8, BoundValidatorInterface {
    struct ValidateConfig {
        address asset;
        uint256 upperBoundRatio;
        uint256 lowerBoundRatio;
    }

    mapping(address => ValidateConfig) public validateConfigs;

    event ValidateConfigAdded(address indexed asset, uint256 indexed upperBound, uint256 indexed lowerBound);

    constructor() {
        _disableInitializers();
    }

    function initialize(address accessControlManager_) external initializer {
        __AccessControlled_init(accessControlManager_);
    }

    function setValidateConfigs(ValidateConfig[] memory configs) external {
        uint256 length = configs.length;
        if (length == 0) revert("invalid validate config length");
        for (uint256 i; i < length; ) {
            setValidateConfig(configs[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setValidateConfig(ValidateConfig memory config) public {
        _checkAccessAllowed("setValidateConfig(ValidateConfig)");

        if (config.asset == address(0)) revert("asset can't be zero address");
        if (config.upperBoundRatio == 0 || config.lowerBoundRatio == 0) revert("bound must be positive");
        if (config.upperBoundRatio <= config.lowerBoundRatio) revert("upper bound must be higher than lowner bound");
        validateConfigs[config.asset] = config;
        emit ValidateConfigAdded(config.asset, config.upperBoundRatio, config.lowerBoundRatio);
    }

    function validatePriceWithAnchorPrice(
        address asset,
        uint256 reportedPrice,
        uint256 anchorPrice
    ) public view virtual override returns (bool) {
        if (validateConfigs[asset].upperBoundRatio == 0) revert("validation config not exist");
        if (anchorPrice == 0) revert("anchor price is not valid");
        return _isWithinAnchor(asset, reportedPrice, anchorPrice);
    }

    function _isWithinAnchor(address asset, uint256 reportedPrice, uint256 anchorPrice) private view returns (bool) {
        if (reportedPrice != 0) {
            uint256 anchorRatio = (anchorPrice * 1e18) / reportedPrice;
            uint256 upperBoundAnchorRatio = validateConfigs[asset].upperBoundRatio;
            uint256 lowerBoundAnchorRatio = validateConfigs[asset].lowerBoundRatio;
            return anchorRatio <= upperBoundAnchorRatio && anchorRatio >= lowerBoundAnchorRatio;
        }
        return false;
    }

    uint256[49] private __gap;
}
