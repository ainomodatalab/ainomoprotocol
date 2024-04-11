import hre from "hardhat";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ADDRESSES } from "../helpers/deploymentConfig";

const func: DeployFunction = async function ({ getNamedAccounts, deployments, network }: HardhatRuntimeEnvironment) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const proxyOwnerAddress = network.live ? ADDRESSES[network.name].timelock : deployer;

  await deploy("RedStoneNomo", {
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
        args: network.live ? [ADDRESSES[network.name].acm] : [],
      },
    },
  });

  const redStoneNomo = await hre.ethers.getContract("RedStoneNomo");
  const redStoneNomoOwner = await redStoneNomo.owner();

  if (redStoneNomoOwner === deployer && network.live) {
    await redStoneNomo.transferOwnership(proxyOwnerAddress);
  }
};

func.tags = ["deploy-redstone"];
export default func;
