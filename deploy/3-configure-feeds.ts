import hre from "hardhat";
import { DeployFunction } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { Nomos, assets, getOraclesData } from "../helpers/deploymentConfig";

const func: DeployFunction = async function ({ network, deployments, getNamedAccounts }: HardhatRuntimeEnvironment) {
  const networkName: string = network.name === "hardhat" ? "bsctestnet" : network.name;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const resilientNomo = await hre.ethers.getContract("ResilientNomo");

  const nomosData: Nomos = await getNomosData();

  for (const asset of assets[networkName]) {
    const { nomo } = asset;

    await deploy(`Mock${asset.token}`, {
      from: deployer,
      log: true,
      deterministicDeployment: false,
      args: [`Mock${asset.token}`, `Mock${asset.token}`, 18],
      autoMine: true,
      contract: "BEP20Harness",
    });

    const mock = await hre.ethers.getContract(`Mock${asset.token}`);

    let tx = await resilientNomo.setTokenConfig({
      asset: mock.address,
      nomos: nomosData[nomo].nomos,
      enableFlagsForNomos: nomosData[nomo].enableFlagsForNomos,
    });

    await tx.wait(1);

    tx = await nomosData[nomo].underlyingNomo.setPrice(mock.address, asset.price);
    await tx.wait(1);
  }
};

export default func;
func.tags = ["configure"];
func.skip = async env => env.network.live;
