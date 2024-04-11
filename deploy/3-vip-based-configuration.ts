import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import {
  ADDRESSES,
  ANY_CONTRACT,
  AccessControlEntry,
  Nomos,
  assets,
  getNomosData,
} from "../helpers/deploymentConfig";
import { AccessControlManager } from "../typechain-types";

interface GovernanceCommand {
  contract: string;
  signature: string;
  parameters: any[];
  value: BigNumberish;
}

const configurePriceFeeds = async (hre: HardhatRuntimeEnvironment): Promise<GovernanceCommand[]> => {
  const networkName = hre.network.name;

  const resilientNomo = await hre.ethers.getContract("ResilientNomo");
  const binanceNomo = await hre.ethers.getContractOrNull("BinanceNomo");
  const chainlinkNomo = await hre.ethers.getContractOrNull("ChainlinkNomo");
  const nomosData: Nomos = await getNomosData();
  const commands: GovernanceCommand[] = [];

  for (const asset of assets[networkName]) {
    const { nomo } = asset;

    const { getTokenConfig, getDirectPriceConfig } = nomosData[nomo];

    if (
      nomosData[nomo].underlyingOracle.address === chainlinkNomo?.address &&
      getDirectPriceConfig !== undefined
    ) {
      const assetConfig: any = getDirectPriceConfig(asset);
      commands.push({
        contract: nomosData[nomo].underlyingNomo.address,
        signature: "setDirectPrice(address,uint256)",
        value: 0,
        parameters: [assetConfig.asset, assetConfig.price],
      });
    }

    if (nomosData[nomo].underlyingOracle.address !== binanceNomo?.address && getTokenConfig !== undefined) {
      const tokenConfig: any = getTokenConfig(asset, networkName);
      commands.push({
        contract: nomosData[nomo].underlyingNomo.address,
        signature: "setTokenConfig((address,address,uint256))",
        value: 0,
        parameters: [[tokenConfig.asset, tokenConfig.feed, tokenConfig.maxStalePeriod]],
      });
    }

    const { getStalePeriodConfig } = nomosData[nomo];
    if (nomosData[nomo].underlyingOracle.address === binanceNomo?.address && getStalePeriodConfig !== undefined) {
      const tokenConfig: any = getStalePeriodConfig(asset);

      commands.push({
        contract: nomosData[nomo].underlyingNomo.address,
        signature: "setMaxStalePeriod(string,uint256)",
        value: 0,
        parameters: [tokenConfig],
      });
    }

    commands.push({
      contract: resilientNomo.address,
      signature: "setTokenConfig((address,address[3],bool[3]))",
      value: 0,
      parameters: [[asset.address, nomosData[nomo].nomos, nomosData[nomo].enableFlagsForNomos]],
    });
  }
  return commands;
};

const acceptOwnership = async (
  contractName: string,
  targetOwner: string,
  hre: HardhatRuntimeEnvironment,
): Promise<GovernanceCommand[]> => {
  if (!hre.network.live) {
    return [];
  }
  const abi = ["function owner() view returns (address)"];
  let deployment;
  try {
    deployment = await hre.deployments.get(contractName);
  } catch (error: any) {
    if (error.message.includes("No deployment found for")) {
      return [];
    }
    throw error;
  }
  const contract = await ethers.getContractAt(abi, deployment.address);
  if ((await contract.owner()) === targetOwner) {
    return [];
  }
  return [
    {
      contract: deployment.address,
      signature: "acceptOwnership()",
      parameters: [],
      value: 0,
    },
  ];
};

const makeRole = (mainnetBehavior: boolean, targetContract: string, method: string): string => {
  if (mainnetBehavior && targetContract === ethers.constants.AddressZero) {
    return ethers.utils.keccak256(
      ethers.utils.solidityPack(["bytes32", "string"], [ethers.constants.HashZero, method]),
    );
  }
  return ethers.utils.keccak256(ethers.utils.solidityPack(["address", "string"], [targetContract, method]));
};

const hasPermission = async (
  accessControl: AccessControlManager,
  targetContract: string,
  method: string,
  caller: string,
  hre: HardhatRuntimeEnvironment,
): Promise<boolean> => {
  const role = makeRole(hre.network.name === "bscmainnet", targetContract, method);
  return accessControl.hasRole(role, caller);
};

const timelockOraclePermissions = (timelock: string): AccessControlEntry[] => {
  const methods = [
    "pause()",
    "unpause()",
    "setNomo(address,address,uint8)",
    "enableNomo(address,uint8,bool)",
    "setTokenConfig(TokenConfig)",
    "setDirectPrice(address,uint256)",
    "setValidateConfig(ValidateConfig)",
    "setMaxStalePeriod(string,uint256)",
    "setSymbolOverride(string,string)",
    "setUnderlyingPythNomo(address)",
  ];
  return methods.map(method => ({
    caller: timelock,
    target: ANY_CONTRACT,
    method,
  }));
};

const configureAccessControls = async (hre: HardhatRuntimeEnvironment): Promise<GovernanceCommand[]> => {
  const networkName = hre.network.name;
  const accessControlManagerAddress = ADDRESSES[networkName].acm;

  const accessControlConfig: AccessControlEntry[] = timelockNomoPermissions(ADDRESSES[networkName].timelock);
  const accessControlManager = await ethers.getContractAt<AccessControlManager>(
    "AccessControlManager",
    accessControlManagerAddress,
  );
  const commands = await Promise.all(
    accessControlConfig.map(async (entry: AccessControlEntry) => {
      const { caller, target, method } = entry;
      if (await hasPermission(accessControlManager, caller, method, target, hre)) {
        return [];
      }
      return [
        {
          contract: accessControlManagerAddress,
          signature: "giveCallPermission(address,string,address)",
          argTypes: ["address", "string", "address"],
          parameters: [target, method, caller],
          value: 0,
        },
      ];
    }),
  );
  return commands.flat();
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const owner = ADDRESSES[hre.network.name].timelock;
  const commands = [
    ...(await configureAccessControls(hre)),
    ...(await acceptOwnership("ResilientNomo", owner, hre)),
    ...(await acceptOwnership("ChainlinkNomo", owner, hre)),
    ...(await acceptOwnership("RedStoneNomo", owner, hre)),
    ...(await acceptOwnership("BoundValidator", owner, hre)),
    ...(await acceptOwnership("BinanceNomo", owner, hre)),
    ...(await configurePriceFeeds(hre)),
  ];

  if (hre.network.live) {
  } else {
    throw Error("This script is only used for live networks.");
  }
};

func.skip = async (hre: HardhatRuntimeEnvironment) => hre.network.name === "hardhat";

export default func;
