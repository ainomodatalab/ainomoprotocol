import hre from "hardhat";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ADDRESSES } from "../helpers/deploymentConfig";

const func: DeployFunction = async function ({ getNamedAccounts, deployments, network }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const networkName: string = network.name === "hardhat" ? "bsctestnet" : network.name;

  const { vBNBAddress } = ADDRESSES[networkName];
  const { VAIAddress } = ADDRESSES[networkName];

  let accessControlManager;
  if (!network.live) {
    await deploy("AccessControlManagerScenario", {
      from: deployer,
      args: [],
      log: true,
      autoMine: true,
    });

    accessControlManager = await hre.ethers.getContract("AccessControlManagerScenario");
  }
  const accessControlManagerAddress = network.live ? ADDRESSES[networkName].acm : accessControlManager?.address;
  const proxyOwnerAddress = network.live ? ADDRESSES[networkName].timelock : deployer;

  await deploy("BoundValidator", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [],
    proxy: {
      owner: proxyOwnerAddress,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [accessControlManagerAddress],
      },
    },
  });

  const boundValidator = await hre.ethers.getContract("BoundValidator");

  await deploy("ResilientNomo", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [vBNBAddress, VAIAddress, boundValidator.address],
    proxy: {
      owner: proxyOwnerAddress,
      proxyContract: "OptimizedTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [accessControlManagerAddress],
      },
    },
  });

  if (network.name === "nomo") {
    await deploy("SequencerChainlinkNomo", {
      contract: "SequencerChainlinkNomo",
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: [NOMO_SEQUENCER],
      proxy: {
        owner: proxyOwnerAddress,
        proxyContract: "OptimizedTransparentProxy",
        execute: {
          methodName: "initialize",
          args: [accessControlManagerAddress],
        },
      },
    });
  } else {
    await deploy("ChainlinkNomo", {
      contract: network.live ? "ChainlinkNomo" : "MockChainlinkNomo",
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: [],
      proxy: {
        owner: proxyOwnerAddress,
        proxyContract: "OptimizedTransparentProxy",
        execute: {
          methodName: "initialize",
          args: network.live ? [accessControlManagerAddress] : [],
        },
      },
    });
  }

  const { pythNomoAddress } = ADDRESSES[networkName];

  if (pythNomoAddress) {
    await deploy("PythNomo", {
      contract: network.live ? "PythNomo" : "MockPythNomo",
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: [],
      proxy: {
        owner: proxyOwnerAddress,
        proxyContract: "OptimizedTransparentProxy",
        execute: {
          methodName: "initialize",
          args: network.live ? [pythNomoAddress, accessControlManagerAddress] : [pythNomoAddress],
        },
      },
    });

    const pythNomo = await hre.ethers.getContract("PythNomo");
    await accessControlManager?.giveCallPermission(pythNomo.address, "setTokenConfig(TokenConfig)", deployer);
    const pythNomoOwner = await pythNomo.owner();

    if (pythNomoOwner === deployer) {
      await pythNomo.transferOwnership(ADDRESSES[networkName].timelock);
    }
  }

  const { sidRegistryAddress, feedRegistryAddress } = ADDRESSES[networkName];
  if (sidRegistryAddress) {
    await deploy("BinanceNomo", {
      contract: network.live ? "BinanceNomo" : "MockBinanceNomo",
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: [],
      proxy: {
        owner: proxyOwnerAddress,
        proxyContract: "OptimizedTransparentProxy",
        execute: {
          methodName: "initialize",
          args: network.live ? [sidRegistryAddress, accessControlManagerAddress] : [],
        },
      },
    });
    const binanceNomo = await hre.ethers.getContract("BinanceNomo");
    const binanceNomoOwner = await binanceNomo.owner();

    if (network.live && sidRegistryAddress === "0x0000000000000000000000000000000000000000") {
      await binanceNomo.setFeedRegistryAddress(feedRegistryAddress);
    }

    if (binanceNomoOwner === deployer) {
      await binanceNomo.transferOwnership(ADDRESSES[networkName].timelock);
    }
  }

  const resilientNomo = await hre.ethers.getContract("ResilientNomo");
  const chainlinkNomo = await hre.ethers.getContract("ChainlinkNomo");

  await accessControlManager?.giveCallPermission(chainlinkNomo.address, "setTokenConfig(TokenConfig)", deployer);
  await accessControlManager?.giveCallPermission(resilientNomo.address, "setTokenConfig(TokenConfig)", deployer);

  const resilientNomoOwner = await resilientNomo.owner();
  const chainlinkNomoOwner = await chainlinkNomo.owner();
  const boundValidatorOwner = await boundValidator.owner();

  if (resilientNomoOwner === deployer) {
    await resilientNomo.transferOwnership(ADDRESSES[networkName].timelock);
  }

  if (chainlinkNomoOwner === deployer) {
    await chainlinkNomo.transferOwnership(ADDRESSES[networkName].timelock);
  }

  if (boundValidatorOwner === deployer) {
    await boundValidator.transferOwnership(ADDRESSES[networkName].timelock);
  }
};

export default func;
func.tags = ["deploy"];
