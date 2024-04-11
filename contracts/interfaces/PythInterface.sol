pragma solidity 0.8.13;

contract PythStructs {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    struct PriceFeed {
        bytes32 id;
        Price price;
        Price emaPrice;
    }
}

interface IPyth {
    event PriceFeedUpdate(
        bytes32 indexed id,
        bool indexed fresh,
        uint16 chainId,
        uint64 sequenceNumber,
        uint256 lastPublishTime,
        uint256 publishTime,
        int64 price,
        uint64 conf
    );

    event BatchPriceFeedUpdate(uint16 chainId, uint64 sequenceNumber, uint256 batchSize, uint256 freshPricesInBatch);

    event UpdatePriceFeeds(address indexed sender, uint256 batchCount, uint256 fee);

    function getValidTimePeriod() external view returns (uint256 validTimePeriod);

    function getPrice(bytes32 id) external view returns (PythStructs.Price memory price);

    function getEmaPrice(bytes32 id) external view returns (PythStructs.Price memory price);

    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);

    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (PythStructs.Price memory price);

    function getEmaPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);

    function getEmaPriceNoOlderThan(bytes32 id, uint256 age) external view returns (PythStructs.Price memory price);

    function updatePriceFeeds(bytes[] calldata updateData) external payable;

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable;

    function getUpdateFee(uint256 updateDataSize) external view returns (uint256 feeAmount);
}

abstract contract AbstractPyth is IPyth {
    function queryPriceFeed(bytes32 id) public view virtual returns (PythStructs.PriceFeed memory priceFeed);

    function priceFeedExists(bytes32 id) public view virtual returns (bool exists);

    function getValidTimePeriod() public view virtual override returns (uint256 validTimePeriod);

    function getPrice(bytes32 id) external view override returns (PythStructs.Price memory price) {
        return getPriceNoOlderThan(id, getValidTimePeriod());
    }

    function getEmaPrice(bytes32 id) external view override returns (PythStructs.Price memory price) {
        return getEmaPriceNoOlderThan(id, getValidTimePeriod());
    }

    function getPriceUnsafe(bytes32 id) public view override returns (PythStructs.Price memory price) {
        PythStructs.PriceFeed memory priceFeed = queryPriceFeed(id);
        return priceFeed.price;
    }

    function getPriceNoOlderThan(
        bytes32 id,
        uint256 age
    ) public view override returns (PythStructs.Price memory price) {
        price = getPriceUnsafe(id);

        require(diff(block.timestamp, price.publishTime) <= age, "no price available which is recent enough");

        return price;
    }

    function getEmaPriceUnsafe(bytes32 id) public view override returns (PythStructs.Price memory price) {
        PythStructs.PriceFeed memory priceFeed = queryPriceFeed(id);
        return priceFeed.emaPrice;
    }

    function getEmaPriceNoOlderThan(
        bytes32 id,
        uint256 age
    ) public view override returns (PythStructs.Price memory price) {
        price = getEmaPriceUnsafe(id);

        require(diff(block.timestamp, price.publishTime) <= age, "no ema price available which is recent enough");

        return price;
    }

    function diff(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > y) {
            return x - y;
        } else {
            return y - x;
        }
    }

    function updatePriceFeeds(bytes[] calldata updateData) public payable virtual override;

    function updatePriceFeedsIfNecessary(
        bytes[] calldata updateData,
        bytes32[] calldata priceIds,
        uint64[] calldata publishTimes
    ) external payable override {
        require(priceIds.length == publishTimes.length, "priceIds and publishTimes arrays should have same length");

        bool updateNeeded = false;
        for (uint256 i = 0; i < priceIds.length; ) {
            if (!priceFeedExists(priceIds[i]) || queryPriceFeed(priceIds[i]).price.publishTime < publishTimes[i]) {
                updateNeeded = true;
                break;
            }
            unchecked {
                i++;
            }
        }

        require(updateNeeded, "no prices in the submitted batch have fresh prices, so this update will have no effect");

        updatePriceFeeds(updateData);
    }
}
