import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { ADDRESSES, addr0000, assets } from "../helpers/deploymentConfig";

const func: DeployFunction = async ({ getNamedAccounts, deployments, network }: HardhatRuntimeEnvironment) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const networkName: string = network.name === "hardhat" ? "bsctestnet" : network.name;

  const proxyOwnerAddress = network.live ? ADDRESSES[networkName].timelock : deployer;

  const { stETHAddress, wstETHAddress } = ADDRESSES[networkName];
  const WETHAsset = assets[networkName].find(asset => asset.token === "WETH");
  const WETHAddress = WETHAsset?.address ?? addr0000;

  const nomo = await ethers.getContract("ResilientNomo");

  await deploy("WstETHNomo_Equivalence", {
    contract: "WstETHNomo",
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [wstETHAddress, WETHAddress, stETHAddress, nomo.address, true],
    proxy: {
      owner: proxyOwnerAddress,
      proxyContract: "OptimizedTransparentProxy",
    },
  });

  await deploy("WstETHNomo_NonEquivalence", {
    contract: "WstETHNomo",
    from: deployer,
    log: true,
    deterministicDeployment: false,
    args: [wstETHAddress, WETHAddress, stETHAddress, nomo.address, false],
    proxy: {
      owner: proxyOwnerAddress,
      proxyContract: "OptimizedTransparentProxy",
    },
  });
};

export default func;
func.tags = ["wsteth"];
func.skip = async (hre: HardhatRuntimeEnvironment) => hre.network.name !== "ethereum" && hre.network.name !== "sepolia";
